#include "backend.h"
#include "core/request_logic.h"
#include "net/http_client.h"
#include "net/request_builder.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUuid>

namespace {

// recursively copies a resource directory (e.g. ":/seed") to disk,
// recreating the same subfolder tree
void copyResourceDir(const QString &srcRoot, const QString &dstRoot)
{
    QDirIterator it(srcRoot, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString src = it.next();
        const QString dst = dstRoot + src.mid(srcRoot.length());
        QDir().mkpath(QFileInfo(dst).absolutePath());
        QFile::copy(src, dst);
        // QFile::copy preserves the resource permissions (read-only); without this
        // QSaveFile can't rewrite the request and the user's save fails
        QFile::setPermissions(dst, QFile::ReadOwner | QFile::WriteOwner
                                   | QFile::ReadGroup | QFile::ReadOther);
    }
}

} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    m_dir = m_settings.storageDir();
    m_envFile = m_dir + QStringLiteral("/.catarina/environments.json");
    m_appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    m_secretsFile = m_appData + QStringLiteral("/secrets.json");
    QDir().mkpath(m_dir);
    QDir().mkpath(QFileInfo(m_envFile).absolutePath());
    QDir().mkpath(m_appData);
    // secrets folder owner-only (the file is already 0600)
    QFile::setPermissions(m_appData, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);

    m_collections = new CollectionStorage(this);
    m_collections->setRoot(m_dir);
    m_envs = new EnvironmentStore(this);
    m_envs->setFile(m_envFile);
    m_history = new HistoryStore(this);
    m_history->setFile(m_appData + QStringLiteral("/history.json"));

    connect(m_collections, &CollectionStorage::changed, this, &Backend::collectionsChanged);
    connect(m_collections, &CollectionStorage::collectionRenamed, this,
            [this](const QString &oldName, const QString &newName) {
                m_envs->renameCollectionScope(oldName, newName);
            });
    connect(m_envs, &EnvironmentStore::changed, this, &Backend::environmentsChanged);
    connect(m_history, &HistoryStore::changed, this, &Backend::historyChanged);

    m_http = new HttpClient(this);
    connect(m_http, &HttpClient::responseReady, this, &Backend::responseReady);
    connect(m_http, &HttpClient::responseMeta, this, &Backend::responseMeta);
    connect(m_http, &HttpClient::error, this, &Backend::error);
    connect(m_http, &HttpClient::started, this, &Backend::started);
    connect(m_http, &HttpClient::canceled, this, &Backend::canceled);
    connect(m_http, &HttpClient::historyEntry, this,
            [this](const QVariantMap &entry) { m_history->add(entry); });

    m_envs->load();
    // loads keychain/file once, before the QML (avoids I/O in the middle of a binding)
    m_secrets = SecretStore::create(m_secretsFile);
    m_secrets->preload();
}

QString Backend::storageDir() const { return m_dir; }

void Backend::setSecretStore(std::unique_ptr<SecretStore> store)
{
    m_secrets = std::move(store);
    m_secrets->preload();
}

void Backend::setStorageDir(const QString &dir)
{
    if (dir.isEmpty() || dir == m_dir)
        return;
    m_settings.setStorageDir(dir);
    m_dir = dir;
    m_envFile = m_dir + QStringLiteral("/.catarina/environments.json");
    QDir().mkpath(m_dir);
    QDir().mkpath(QFileInfo(m_envFile).absolutePath());
    m_collections->setRoot(m_dir);   // clears the caches
    m_envs->setFile(m_envFile);
    m_envs->load();
    emit collectionsChanged();
    emit environmentsChanged();
}

QString Backend::activeEnvironment() const { return m_envs->active(); }

void Backend::seedDefaultCollection()
{
    const QString marker = m_dir + QStringLiteral("/.catarina/.seeded");
    if (QFileInfo::exists(marker))
        return;   // already seeded (even if the user deletes the collection later)
    if (collectionTree().isEmpty()) {
        copyResourceDir(QStringLiteral(":/seed"), m_dir);
        // the public DummyJSON password lives in the keychain (the versioned file only stores
        // the secretId), so the example works out of the box without exposing the password
        saveSecret(QStringLiteral("seed-dummyjson-password"), QStringLiteral("emilyspass"));
        // the seed brought an example environment; reload (the constructor already ran
        // before the copy, so without this the global variables wouldn't show up)
        m_envs->load();
        emit environmentsChanged();
    }
    QFile f(marker);
    if (f.open(QIODevice::WriteOnly))
        f.close();
}

// ---------------------------------------------------------------- pure logic

// delegated to RequestLogic (src/core/request_logic.h); kept Q_INVOKABLE
// because the QML calls backend.requestParts(...) to export cURL
QVariantMap Backend::requestParts(const QVariantMap &request) const
{
    return RequestLogic::requestParts(request);
}

QVariantMap Backend::resolvedRequestParts(const QVariantMap &request, const QString &collection) const
{
    // effective values (global → collection → request), with secrets already resolved
    const QVariantMap vars = variablesState(request, collection)
                                 .value(QStringLiteral("effective")).toMap();

    QVariantMap r = request;
    r[QStringLiteral("url")] =
        RequestLogic::substitute(request.value(QStringLiteral("url")).toString(), vars);
    r[QStringLiteral("params")] =
        RequestLogic::substituteList(request.value(QStringLiteral("params")).toList(), vars);
    r[QStringLiteral("headers")] =
        RequestLogic::substituteList(request.value(QStringLiteral("headers")).toList(), vars);
    r[QStringLiteral("fields")] =
        RequestLogic::substituteList(request.value(QStringLiteral("fields")).toList(), vars);
    r[QStringLiteral("body")] =
        RequestLogic::substitute(request.value(QStringLiteral("body")).toString(), vars);
    // effective auth ("inherit" → the collection's), with variables already resolved
    const QVariantMap effAuth = RequestLogic::effectiveAuth(
        request.value(QStringLiteral("auth")).toMap(), collectionAuth(collection));
    r[QStringLiteral("auth")] = RequestLogic::substituteList({effAuth}, vars).value(0).toMap();

    QVariantMap parts = RequestLogic::requestParts(r);
    // appends the active params to the URL, like send does
    parts[QStringLiteral("url")] = RequestLogic::buildUrl(
        r.value(QStringLiteral("url")).toString(),
        r.value(QStringLiteral("params")).toList()).toString();
    return parts;
}

QString Backend::querySuffix(const QString &url, const QVariantList &params) const
{
    return RequestLogic::querySuffix(url, params);
}

// ---------------------------------------------------------------- secrets

// Delegates to SecretStore (OS keychain or 0600 file); see storage/secret_store.h.
QString Backend::secretValue(const QString &id) const
{
    return m_secrets->value(id);
}

bool Backend::saveSecret(const QString &id, const QString &value)
{
    return m_secrets->save(id, value);
}

bool Backend::removeSecret(const QString &id)
{
    return m_secrets->remove(id);
}

QVariantList Backend::withResolvedSecrets(const QVariantList &vars) const
{
    QVariantList out = vars;
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("secret")).toBool()) {
            const QString id = m.value(QStringLiteral("secretId")).toString();
            if (!id.isEmpty())                 // no id = new secret, keeps what was typed
                m[QStringLiteral("value")] = secretValue(id);
        }
        v = m;
    }
    return out;
}

QVariantList Backend::sanitizeSecrets(const QVariantList &vars)
{
    QVariantList out = vars;
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("secret")).toBool()) {
            QString id = m.value(QStringLiteral("secretId")).toString();
            if (id.isEmpty()) {
                id = QUuid::createUuid().toString(QUuid::WithoutBraces);
                m[QStringLiteral("secretId")] = id;
            }
            saveSecret(id, m.value(QStringLiteral("value")).toString());
            m[QStringLiteral("value")] = QString();       // never goes to the file
        } else {
            const QString oldId = m.value(QStringLiteral("secretId")).toString();
            if (!oldId.isEmpty()) {
                removeSecret(oldId);                       // no longer a secret: clears the keychain
                m[QStringLiteral("secretId")] = QString();
            }
        }
        v = m;
    }
    return out;
}

// ---------------------------------------------------------------- variables

QVariantList Backend::activeGlobalVars() const
{
    return m_envs->activeVariables();
}

VariableResolver Backend::resolver() const
{
    return VariableResolver([this](const QString &id) { return m_secrets->value(id); });
}

QVariantMap Backend::variablesState(const QVariantMap &request, const QString &collection) const
{
    return resolver().state(request, activeGlobalVars(), collection,
                            collectionVariables(collection), collectionAuth(collection));
}

QVariantList Backend::resolvedVariables(const QString &collection, const QVariantList &requestVars) const
{
    return variablesState({{QStringLiteral("vars"), requestVars}}, collection)
        .value(QStringLiteral("resolved"))
        .toList();
}

QVariantList Backend::resolvedCollectionVariables(const QString &collection,
                                                  const QVariantList &collectionVars) const
{
    // collection overview: without a request, the list being edited is the collection itself
    const VariableResolver r = resolver();
    return r.resolvedFromChain(r.chain(activeGlobalVars(), collection, collectionVars, {}));
}

QVariantMap Backend::variableNoteFor(const QString &name, const QString &collection) const
{
    return resolver().note(name, activeGlobalVars(), collection, collectionVariables(collection));
}

// ---------------------------------------------------------------- request

void Backend::send(const QVariantMap &request, const QString &collection)
{
    const QVariantMap state = variablesState(request, collection);
    const QStringList missing = state.value(QStringLiteral("missing")).toStringList();
    if (!missing.isEmpty()) {
        emit error(QStringLiteral("unresolved"), {missing});
        return;
    }

    const QVariantMap vars = state.value(QStringLiteral("effective")).toMap();
    const BuiltRequest built = RequestBuilder::build(request, vars,
                                                     m_collections->headers(collection),
                                                     m_collections->auth(collection),
                                                     m_settings.timeoutSec(),
                                                     m_settings.ignoreSsl());
    if (!built.valid) {
        emit error(QStringLiteral("invalidUrl"), {});
        return;
    }
    m_http->send(built);
}

void Backend::cancel()
{
    m_http->cancel();
}

// ---------------------------------------------------------------- collections
// Everything delegated to CollectionStorage (src/storage/collection_storage.h).

QVariantList Backend::collectionTree() const { return m_collections->tree(); }
bool Backend::isCollection(const QString &relPath) const { return m_collections->isCollection(relPath); }
QVariantMap Backend::loadRequest(const QString &relPath) const { return m_collections->loadRequest(relPath); }
bool Backend::deleteEntry(const QString &relPath) { return m_collections->deleteEntry(relPath); }
bool Backend::createFolder(const QString &relPath) { return m_collections->createFolder(relPath); }
bool Backend::moveEntry(const QString &from, const QString &toFolder) { return m_collections->moveEntry(from, toFolder); }
bool Backend::renameEntry(const QString &relPath, const QString &newName) { return m_collections->renameEntry(relPath, newName); }
bool Backend::duplicateEntry(const QString &relPath) { return m_collections->duplicateEntry(relPath); }

bool Backend::saveRequest(const QString &relPath, const QVariantMap &data)
{
    QVariantMap d = data;
    if (d.contains(QStringLiteral("vars"))) {
        if (!VariableResolver::duplicateVariableName(d.value(QStringLiteral("vars")).toList()).isEmpty())
            return false;   // duplicated variable names in the request
        // secrets of the request variables never go to the file
        d[QStringLiteral("vars")] = sanitizeSecrets(d.value(QStringLiteral("vars")).toList());
    }
    return m_collections->saveRequest(relPath, d);
}

// ---------------------------------------------------------------- collection vars

QVariantList Backend::collectionVariables(const QString &collection) const
{
    return m_collections->variables(collection);
}

QString Backend::duplicateVariableName(const QVariantList &vars) const
{
    return VariableResolver::duplicateVariableName(vars);
}

bool Backend::saveCollectionVariables(const QString &collection, const QVariantList &vars)
{
    if (collection.isEmpty() || !VariableResolver::duplicateVariableName(vars).isEmpty())
        return false;
    return m_collections->saveVariables(collection, sanitizeSecrets(vars));
}

QVariantList Backend::collectionHeaders(const QString &collection) const
{
    return m_collections->headers(collection);
}

bool Backend::saveCollectionHeaders(const QString &collection, const QVariantList &headers)
{
    if (collection.isEmpty())
        return false;
    return m_collections->saveHeaders(collection, headers);
}

QVariantMap Backend::collectionAuth(const QString &collection) const
{
    return m_collections->auth(collection);
}

bool Backend::saveCollectionAuth(const QString &collection, const QVariantMap &auth)
{
    if (collection.isEmpty())
        return false;
    return m_collections->saveAuth(collection, auth);
}

// ---------------------------------------------------------------- environments

QVariantList Backend::environments() const { return m_envs->list(); }
QVariantList Backend::environmentVariables(const QString &name) const { return m_envs->variables(name); }

bool Backend::saveEnvironment(const QString &name, const QVariantList &variables)
{
    if (name.isEmpty() || !VariableResolver::duplicateVariableName(variables).isEmpty())
        return false;
    return m_envs->save(name, sanitizeSecrets(variables));
}

bool Backend::deleteEnvironment(const QString &name) { return m_envs->remove(name); }
bool Backend::renameEnvironment(const QString &oldName, const QString &newName) { return m_envs->rename(oldName, newName); }
void Backend::setActiveEnvironment(const QString &name) { m_envs->setActive(name); }

// ---------------------------------------------------------------- history

QVariantList Backend::history() const { return m_history->list(); }
void Backend::clearHistory() { m_history->clear(); }
