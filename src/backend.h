#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "settings.h"
#include "core/variable_resolver.h"
#include "storage/collection_storage.h"
#include "storage/environment_store.h"
#include "storage/history_store.h"
#include "storage/secret_store.h"

#include <memory>

class HttpClient;

// Backend: QML facade. Sends requests (variables resolved by scope, params,
// auth, multipart) and delegates persistence to the stores:
//   - CollectionStorage  ~/catarina-collections (.json versionable)
//   - EnvironmentStore   <dir>/.catarina/environments.json
//   - HistoryStore       ~/.local/share/catarina/history.json
//   - SecretStore        OS keychain or ~/.local/share/catarina/secrets.json (0600)
// Keeps the signals and the Q_INVOKABLE API the QML already uses.
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString storageDir READ storageDir CONSTANT)
    Q_PROPERTY(QString activeEnvironment READ activeEnvironment NOTIFY environmentsChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    // injection (tests): swaps the secret storage for an in-memory one,
    // avoiding touching the OS keychain or files
    void setSecretStore(std::unique_ptr<SecretStore> store);

    QString storageDir() const;
    Q_INVOKABLE void setStorageDir(const QString &dir);
    QString activeEnvironment() const;
    // copies the built-in example collection (:/seed) on first use; only when
    // storage is still empty and just once (marks .catarina/.seeded)
    Q_INVOKABLE void seedDefaultCollection();

    // ---- pure logic: moved to RequestLogic (src/core/request_logic.h) ----
    // effective parts of a request (method/url/headers/body) for export: applies
    // auth and default Content-Type like on send, without resolving {{variables}}
    Q_INVOKABLE QVariantMap requestParts(const QVariantMap &request) const;
    // like requestParts, but with {{variables}} resolved (effective values, including
    // secrets), inherited auth applied and params appended to the URL — it's the cURL "that works"
    Q_INVOKABLE QVariantMap resolvedRequestParts(const QVariantMap &request,
                                                 const QString &collection) const;
    // preview of the query suffix appended by the active params (same semantics as send)
    Q_INVOKABLE QString querySuffix(const QString &url, const QVariantList &params) const;

    // ---- request ----
    // request: { method, url, params[], headers[], body, bodyType, fields[], auth{}, vars[] }
    Q_INVOKABLE void send(const QVariantMap &request, const QString &collection);
    Q_INVOKABLE void cancel();          // aborts the in-flight request
    // why "name" doesn't resolve in this collection, as a code for the UI to translate:
    // { "code": "", "collections": [...] }, codes: "" | "disabled" | "restricted" | "undefined"
    Q_INVOKABLE QVariantMap variableNoteFor(const QString &name, const QString &collection) const;

    // ---- collections ----
    Q_INVOKABLE QVariantList collectionTree() const;
    Q_INVOKABLE bool isCollection(const QString &relPath) const;   // is it a folder/collection?
    Q_INVOKABLE QVariantMap loadRequest(const QString &relPath) const;
    Q_INVOKABLE bool saveRequest(const QString &relPath, const QVariantMap &data);
    Q_INVOKABLE bool deleteEntry(const QString &relPath);
    Q_INVOKABLE bool createFolder(const QString &relPath);
    // moves a request or folder into toFolder ("" = root)
    Q_INVOKABLE bool moveEntry(const QString &from, const QString &toFolder);
    // renames keeping the same parent (newName is the base name, without .json)
    // renaming a collection (top-level folder) also repoints the scope of the
    // environment variables that reference it
    Q_INVOKABLE bool renameEntry(const QString &relPath, const QString &newName);
    // duplicates a request or folder as "<name> copy"
    Q_INVOKABLE bool duplicateEntry(const QString &relPath);

    // ---- collection variables (versioned, without secrets) ----
    Q_INVOKABLE QVariantList collectionVariables(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionVariables(const QString &collection, const QVariantList &vars);
    // first duplicated variable name in the list ("" if none); names trimmed
    Q_INVOKABLE QString duplicateVariableName(const QVariantList &vars) const;

    // ---- collection headers (applied to all of its requests) ----
    Q_INVOKABLE QVariantList collectionHeaders(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionHeaders(const QString &collection, const QVariantList &headers);

    // ---- collection auth (inherited by requests with auth "inherit") ----
    Q_INVOKABLE QVariantMap collectionAuth(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionAuth(const QString &collection, const QVariantMap &auth);

    // ---- global environments (with per-variable scope) ----
    Q_INVOKABLE QVariantList environments() const;
    Q_INVOKABLE QVariantList environmentVariables(const QString &name) const;
    Q_INVOKABLE bool saveEnvironment(const QString &name, const QVariantList &variables);
    Q_INVOKABLE bool deleteEnvironment(const QString &name);
    Q_INVOKABLE bool renameEnvironment(const QString &oldName, const QString &newName);
    Q_INVOKABLE void setActiveEnvironment(const QString &name);

    // ---- secrets (outside the repo) ----
    Q_INVOKABLE QString secretValue(const QString &id) const;
    Q_INVOKABLE bool saveSecret(const QString &id, const QString &value);
    Q_INVOKABLE bool removeSecret(const QString &id);
    // fills `value` of secret variables from the keychain (for editing; the
    // value is never written to the versioned file — that still happens on save)
    Q_INVOKABLE QVariantList withResolvedSecrets(const QVariantList &vars) const;

    // ---- history ----
    Q_INVOKABLE QVariantList history() const;
    Q_INVOKABLE void clearHistory();

    // effective variables visible to a collection, with secret values already resolved
    // as above, but with the origin of each variable (request/collection/global) — for the UI
    Q_INVOKABLE QVariantList resolvedVariables(const QString &collection,
                                               const QVariantList &requestVars) const;
    // like resolvedVariables, but with the collection's own list provided (while editing),
    // without request scope — used by the collection overview
    Q_INVOKABLE QVariantList resolvedCollectionVariables(const QString &collection,
                                                         const QVariantList &collectionVars) const;
    // resolves everything in one pass: { "resolved": [...], "missing": [...] }
    Q_INVOKABLE QVariantMap variablesState(const QVariantMap &request,
                                           const QString &collection) const;

signals:
    void responseReady(int status, const QString &statusText, const QVariantList &headers,
                       const QString &body, int elapsedMs, int sizeBytes);
    // metadata for the network/timeline tab (protocol, ip, tls, sent request)
    void responseMeta(const QVariantMap &meta);
    // error with code + args; the UI builds the text (Strings.js::backendError)
    void error(const QString &code, const QVariantList &args);
    void started();                     // request dispatched
    void canceled();                    // request aborted by the user
    void collectionsChanged();
    void environmentsChanged();
    void historyChanged();

private:
    // variables of the active environment (candidates for globals during resolution)
    QVariantList activeGlobalVars() const;
    // pure resolver with this Backend's secret access injected
    VariableResolver resolver() const;

    // strips secrets from the file (they go to the keychain); clears the keychain if it's no longer a secret
    QVariantList sanitizeSecrets(const QVariantList &vars);

    Settings m_settings;                       // same app config (storageDir/timeout/ignoreSsl)
    QString m_dir;         // ~/catarina-collections
    QString m_envFile;     // <dir>/.catarina/environments.json
    QString m_appData;     // ~/.local/share/catarina
    QString m_secretsFile; // <m_appData>/secrets.json
    std::unique_ptr<SecretStore> m_secrets;

    HttpClient *m_http = nullptr;
    CollectionStorage *m_collections = nullptr;
    EnvironmentStore *m_envs = nullptr;
    HistoryStore *m_history = nullptr;
};
