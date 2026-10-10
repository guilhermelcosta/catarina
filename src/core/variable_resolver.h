#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

// already-resolved item of the global → collection → request chain
struct ResolvedVar {
    QString name;
    QString value;
    QString source;   // "global" | "collection" | "request"
    bool secret = false;
    bool enabled = true;
};

// Resolves {{variables}}: scope (global/collection/request), precedence, secrets
// (delegated to a callback) and chained references. Pure — it touches neither disk nor
// network; so it's testable in isolation. The global/collection lists are passed
// as parameters (the Backend reads from its stores and injects them here).
class VariableResolver
{
public:
    // resolves the value of a secret by secretId ("" if unknown)
    using SecretFn = std::function<QString(const QString &secretId)>;
    explicit VariableResolver(SecretFn secretOf = {});

    // first duplicated variable name in the list ("" if none); names trimmed
    static QString duplicateVariableName(const QVariantList &vars);

    // single already-resolved chain (scope, secrets and flag enabled)
    QList<ResolvedVar> chain(const QVariantList &globalVars, const QString &collection,
                             const QVariantList &collectionVars,
                             const QVariantList &requestVars) const;
    // groups by name (highest-precedence origin wins) for the UI
    QVariantList resolvedFromChain(const QList<ResolvedVar> &chain) const;

    // resolves everything in one pass: { "resolved": [...], "missing": [...], "effective": {...} }
    QVariantMap state(const QVariantMap &request, const QVariantList &globalVars,
                      const QString &collection, const QVariantList &collectionVars,
                      const QVariantMap &collectionAuth) const;

    // why "name" doesn't resolve: { "code", "collections" }
    // codes: "" (resolves) | "disabled" | "restricted" | "undefined"
    QVariantMap note(const QString &name, const QVariantList &globalVars,
                     const QString &collection, const QVariantList &collectionVars) const;

    // request texts that may contain {{variables}}
    static QStringList collectTexts(const QVariantMap &request);

private:
    SecretFn m_secretOf;
};
