#include "variable_resolver.h"
#include "request_logic.h"
#include "request_schema.h"

#include <QMap>
#include <QSet>

namespace {
namespace RS = RequestSchema;

// Cap on passes when resolving {{variable}} in name/value. Each pass rebuilds
// the name→value map, so chained references resolve in ~1 pass per level.
// It's also the safety limit: a cyclic reference ({{a}}↔{{b}}) doesn't converge and
// stops here instead of spinning forever. 10 comfortably covers the levels used in the UI.
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
            // name always "trimmed": leading/trailing spaces/tabs break the
            // {{name}} reference (substitute captures the name already without spaces). See check_storage.
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

    // A variable can have {{another}} in the name and/or the value, and the reference can
    // chain. Iterates until stable; the pass cap is kMaxVariableResolvePasses.
    QVariantMap vals;
    for (int pass = 0; pass < kMaxVariableResolvePasses; ++pass) {
        vals.clear();
        for (const ResolvedVar &r : chain)
            if (r.enabled)
                vals.insert(r.name, r.value);          // precedence: the last one wins
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
    QMap<QString, QVariantMap> byName;   // best precedence per name
    for (const ResolvedVar &r : chain) {
        if (byName.contains(r.name) && !r.enabled)
            continue;                    // a disabled one doesn't override what already resolves
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
    // a single pass over the chain: resolves the list, the effective map and what's missing
    const QList<ResolvedVar> ch =
        chain(globalVars, collection, collectionVars, request.value(RS::kVars).toList());

    QVariantMap effective;               // enabled only (that's what replaces {{...}})
    for (const ResolvedVar &r : ch)
        if (r.enabled)
            effective.insert(r.name, r.value);
    QVariantList resolved = resolvedFromChain(ch);
    // dynamic variables ({{$randomUuid}}, ...) are always resolvable: they show in autocomplete
    // and on hover (source "dynamic"), but carry no stored value. Single source: RequestLogic.
    for (const QVariant &v : RequestLogic::dynamicVariables()) {
        const QVariantMap d = v.toMap();
        const QString name = d.value(RS::kName).toString();
        bool exists = false;
        for (const QVariant &r : resolved)
            if (r.toMap().value(RS::kName).toString() == name) { exists = true; break; }
        if (!exists) {
            QVariantMap entry;
            entry[RS::kName] = name;
            entry[RS::kValue] = d.value(RS::kValue);
            entry[RS::kSecret] = false;
            entry[QStringLiteral("source")] = QStringLiteral("dynamic");
            entry[RS::kEnabled] = true;
            resolved.append(entry);
        }
    }
    QStringList missing;
    QStringList texts = collectTexts(request);
    // effective auth: with "inherit", the collection token is scanned too
    for (const QVariant &v : RequestLogic::effectiveAuth(request.value(RS::kAuth).toMap(),
                                                         collectionAuth))
        texts << v.toString();
    for (const QString &text : texts) {
        for (const QString &name : RequestLogic::variableRefs(text)) {
            // dynamic ({{$randomUuid}}, ...) resolve on send, so they're never "missing"
            if (!effective.contains(name) && !RequestLogic::isDynamicVariable(name)
                && !missing.contains(name))
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
    // Why "name" doesn't resolve, as a code (the UI translates): "disabled", "restricted"
    // (with the list in "collections"), "" (resolves) or "undefined".
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
