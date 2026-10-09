#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

// item já resolvido da cadeia global → coleção → request
struct ResolvedVar {
    QString name;
    QString value;
    QString source;   // "global" | "collection" | "request"
    bool secret = false;
    bool enabled = true;
};

// Resolve {{variáveis}}: escopo (global/coleção/request), precedência, segredos
// (delegados a um callback) e referências encadeadas. Puro — não toca disco nem
// rede; por isso é testável isoladamente. As listas global/coleção são passadas
// por parâmetro (o Backend lê dos seus stores e injeta aqui).
class VariableResolver
{
public:
    // resolve o valor de um segredo pelo secretId ("" se desconhecido)
    using SecretFn = std::function<QString(const QString &secretId)>;
    explicit VariableResolver(SecretFn secretOf = {});

    // primeiro nome de variável repetido na lista ("" se não houver); nomes aparados
    static QString duplicateVariableName(const QVariantList &vars);

    // cadeia única já resolvida (escopo, segredos e flag enabled)
    QList<ResolvedVar> chain(const QVariantList &globalVars, const QString &collection,
                             const QVariantList &collectionVars,
                             const QVariantList &requestVars) const;
    // agrupa por nome (origem de maior precedência vence) para a UI
    QVariantList resolvedFromChain(const QList<ResolvedVar> &chain) const;

    // resolve tudo numa passada: { "resolved": [...], "missing": [...], "effective": {...} }
    QVariantMap state(const QVariantMap &request, const QVariantList &globalVars,
                      const QString &collection, const QVariantList &collectionVars,
                      const QVariantMap &collectionAuth) const;

    // por que "name" não resolve: { "code", "collections" }
    // codes: "" (resolve) | "disabled" | "restricted" | "undefined"
    QVariantMap note(const QString &name, const QVariantList &globalVars,
                     const QString &collection, const QVariantList &collectionVars) const;

    // textos de um request que podem conter {{variáveis}}
    static QStringList collectTexts(const QVariantMap &request);

private:
    SecretFn m_secretOf;
};
