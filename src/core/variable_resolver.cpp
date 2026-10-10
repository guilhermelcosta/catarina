#include "variable_resolver.h"
#include "request_logic.h"
#include "request_schema.h"

#include <QMap>
#include <QSet>

namespace {
namespace RS = RequestSchema;

// Teto de passadas ao resolver {{variavel}} em nome/valor. Cada passada reconstrói
// o mapa nome→valor, então cadeias encadeadas se resolvem em ~1 passada por nível.
// Também é o limite de segurança: referência cíclica ({{a}}↔{{b}}) não converge e
// para aqui em vez de girar para sempre. 10 cobre folgado os níveis usados na UI.
constexpr int kMaxVariableResolvePasses = 10;
} // namespace

VariableResolver::VariableResolver(SecretFn secretOf)
    : m_secretOf(std::move(secretOf))
{
}

QString VariableResolver::duplicateVariableName(const QVariantList &vars)
{
    QSet<QString> seen;
    for (const QVariant &v : vars) {
        const QString n = v.toMap().value(RS::kName).toString().trimmed();
        if (n.isEmpty())
            continue;
        if (seen.contains(n))
            return n;
        seen.insert(n);
    }
    return {};
}

QList<ResolvedVar> VariableResolver::chain(const QVariantList &globalVars, const QString &collection,
                                           const QVariantList &collectionVars,
                                           const QVariantList &requestVars) const
{
    QList<ResolvedVar> chain;
    auto add = [&](const QVariantList &vars, const QString &source, bool global) {
        for (const QVariant &v : vars) {
            const QVariantMap m = v.toMap();
            // nome sempre "aparado": espaços/tabs nas pontas quebram a referência
            // {{nome}} (o substitute captura o nome já sem espaços). Ver check_storage.
            const QString name = m.value(RS::kName).toString().trimmed();
            if (name.isEmpty())
                continue;
            if (global) {
                const QString scope = m.value(RS::kScope, RS::kAll).toString();
                if (scope == RS::kCollections) {
                    const QStringList list = m.value(RS::kCollections).toStringList();
                    if (!collection.isEmpty() && !list.contains(collection))
                        continue;
                }
            }
            const bool secret = m.value(RS::kSecret).toBool();
            const QString secretId = m.value(RS::kSecretId).toString();
            chain.append({name,
                          secret ? (m_secretOf ? m_secretOf(secretId) : QString())
                                 : m.value(RS::kValue).toString(),
                          source, secret,
                          m.value(RS::kEnabled, true).toBool()});
        }
    };

    add(globalVars, RS::kSourceGlobal, true);
    add(collectionVars, RS::kSourceCollection, false);
    add(requestVars, RS::kSourceRequest, false);

    // Uma variável pode ter {{outra}} no nome e/ou no valor, e a referência pode
    // encadear. Itera até estabilizar; o teto de passadas é kMaxVariableResolvePasses.
    QVariantMap vals;
    for (int pass = 0; pass < kMaxVariableResolvePasses; ++pass) {
        vals.clear();
        for (const ResolvedVar &r : chain)
            if (r.enabled)
                vals.insert(r.name, r.value);          // precedência: o último vence
        bool changed = false;
        for (ResolvedVar &r : chain) {
            if (!r.enabled)
                continue;
            const QString nn = RequestLogic::substitute(r.name, vals).trimmed();
            const QString nv = RequestLogic::substitute(r.value, vals);
            if (nn != r.name) { r.name = nn; changed = true; }
            if (nv != r.value) { r.value = nv; changed = true; }
        }
        if (!changed)
            break;
    }

    return chain;
}

QVariantList VariableResolver::resolvedFromChain(const QList<ResolvedVar> &chain) const
{
    QMap<QString, QVariantMap> byName;   // melhor precedência por nome
    for (const ResolvedVar &r : chain) {
        if (byName.contains(r.name) && !r.enabled)
            continue;                    // desabilitada não sobrescreve o que já resolve
        byName.insert(r.name, {{RS::kName, r.name},
                               {RS::kValue, r.value},
                               {RS::kSecret, r.secret},
                               {QStringLiteral("source"), r.source},
                               {RS::kEnabled, r.enabled}});
    }
    QVariantList resolved;
    for (auto it = byName.constBegin(); it != byName.constEnd(); ++it)
        resolved.append(it.value());
    return resolved;
}

QStringList VariableResolver::collectTexts(const QVariantMap &request)
{
    QStringList texts;
    texts << request.value(RS::kUrl).toString();
    texts << request.value(RS::kBody).toString();
    const auto append = [&texts](const QVariantList &list) {
        for (const QVariant &v : list) {
            const QVariantMap m = v.toMap();
            texts << m.value(RS::kName).toString();
            texts << m.value(RS::kValue).toString();
        }
    };
    append(request.value(RS::kParams).toList());
    append(request.value(RS::kHeaders).toList());
    append(request.value(RS::kFields).toList());
    return texts;
}

QVariantMap VariableResolver::state(const QVariantMap &request, const QVariantList &globalVars,
                                    const QString &collection, const QVariantList &collectionVars,
                                    const QVariantMap &collectionAuth) const
{
    // uma única passada pela cadeia: resolve a lista, o mapa efetivo e o que falta
    const QList<ResolvedVar> ch =
        chain(globalVars, collection, collectionVars, request.value(RS::kVars).toList());

    QVariantMap effective;               // só habilitadas (é o que substitui {{...}})
    for (const ResolvedVar &r : ch)
        if (r.enabled)
            effective.insert(r.name, r.value);
    const QVariantList resolved = resolvedFromChain(ch);

    QStringList missing;
    QStringList texts = collectTexts(request);
    // auth efetiva: com "inherit", o token da coleção também é escaneado
    for (const QVariant &v : RequestLogic::effectiveAuth(request.value(RS::kAuth).toMap(),
                                                         collectionAuth))
        texts << v.toString();
    for (const QString &text : texts) {
        for (const QString &name : RequestLogic::variableRefs(text)) {
            if (!effective.contains(name) && !missing.contains(name))
                missing.append(name);
        }
    }

    return {{QStringLiteral("resolved"), resolved},
            {QStringLiteral("missing"), missing},
            {QStringLiteral("effective"), effective}};
}

QVariantMap VariableResolver::note(const QString &name, const QVariantList &globalVars,
                                   const QString &collection, const QVariantList &collectionVars) const
{
    // Por que "name" não resolve, por código (a UI traduz): "disabled", "restricted"
    // (com a lista em "collections"), "" (resolve) ou "undefined".
    auto note = [&](const QVariantList &vars, bool global, QVariantMap *out) {
        for (const QVariant &v : vars) {
            const QVariantMap m = v.toMap();
            if (m.value(RS::kName).toString() != name)
                continue;
            if (!m.value(RS::kEnabled, true).toBool()) {
                *out = {{QStringLiteral("code"), QStringLiteral("disabled")}};
            } else if (global) {
                const QString scope = m.value(RS::kScope, RS::kAll).toString();
                if (scope == RS::kCollections) {
                    const QStringList list = m.value(RS::kCollections).toStringList();
                    if (!collection.isEmpty() && !list.contains(collection))
                        *out = {{QStringLiteral("code"), QStringLiteral("restricted")},
                                {RS::kCollections, list}};
                    else
                        *out = {{QStringLiteral("code"), QString()}};
                } else {
                    *out = {{QStringLiteral("code"), QString()}};
                }
            } else {
                *out = {{QStringLiteral("code"), QString()}};
            }
            return true;
        }
        return false;
    };

    QVariantMap out;
    if (note(globalVars, true, &out))
        return out;
    if (note(collectionVars, false, &out))
        return out;
    return {{QStringLiteral("code"), QStringLiteral("undefined")}};
}
