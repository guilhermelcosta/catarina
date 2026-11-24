#include "backend.h"
#include "core/request_logic.h"
#include "net/http_client.h"
#include "net/request_builder.h"

#include <QColor>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPalette>
#include <QStandardPaths>
#include <QStyleHints>
#include <QUuid>

namespace {

// The palette in effect when the app started. Kept so "system" can restore it
// after an explicit light/dark override.
QPalette &systemPalette()
{
    static QPalette palette = QGuiApplication::palette();
    return palette;
}

// The accent a forced scheme paints selection/checked surfaces with. A platform
// theme without a colour scheme (isolated config, minimal environment) reports a
// neutral or near-window highlight, which would paint checked controls white on
// white and hide the highlighted text; fall back to Breeze's selection blue.
QColor accentColor(const QColor &window)
{
    QColor accent;
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    accent = systemPalette().color(QPalette::Accent);
#endif
    if (!accent.isValid())
        accent = systemPalette().color(QPalette::Highlight);
    if (!accent.isValid() || accent.hsvSaturationF() < 0.2
        || qAbs(accent.lightness() - window.lightness()) < 40)
        accent = QColor(0x3d, 0xae, 0xe9);
    return accent;
}

// The text painted on top of `accent`; white only when the accent is dark.
QColor onAccentColor(const QColor &accent)
{
    return accent.lightness() > 127 ? QColor(0x23, 0x26, 0x29)
                                    : QColor(0xff, 0xff, 0xff);
}

// Qt only updates the default palette when the platform reports a system
// palette for the requested scheme. Under the offscreen platform (and some
// desktops) that never happens, so the explicit scheme is resolved here. The
// roles follow Breeze's neutral surfaces so the chrome stays the same hue.
QPalette schemePalette(Qt::ColorScheme scheme)
{
    QPalette p = systemPalette();
    if (scheme == Qt::ColorScheme::Dark) {
        const QColor accent = accentColor(QColor(0x23, 0x26, 0x29));
        const QColor onAccent = onAccentColor(accent);
        const QColor window(0x23, 0x26, 0x29);
        const QColor base(0x1b, 0x1e, 0x20);
        const QColor text(0xef, 0xf0, 0xf1);
        p.setColor(QPalette::Window, window);
        p.setColor(QPalette::WindowText, text);
        p.setColor(QPalette::Base, base);
        p.setColor(QPalette::AlternateBase, window);
        p.setColor(QPalette::ToolTipBase, window);
        p.setColor(QPalette::ToolTipText, text);
        p.setColor(QPalette::Text, text);
        p.setColor(QPalette::PlaceholderText, QColor(0xa0, 0xa4, 0xa8));
        p.setColor(QPalette::Button, window);
        p.setColor(QPalette::ButtonText, text);
        p.setColor(QPalette::BrightText, QColor(0xff, 0xff, 0xff));
        p.setColor(QPalette::Link, accent);
        p.setColor(QPalette::Highlight, accent);
        p.setColor(QPalette::HighlightedText, onAccent);
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
        p.setColor(QPalette::Accent, accent);
#endif
        p.setColor(QPalette::Disabled, QPalette::WindowText, QColor(0x7f, 0x8c, 0x8d));
        p.setColor(QPalette::Disabled, QPalette::Text, QColor(0x7f, 0x8c, 0x8d));
        p.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(0x7f, 0x8c, 0x8d));
    } else {
        const QColor accent = accentColor(QColor(0xef, 0xf0, 0xf1));
        const QColor onAccent = onAccentColor(accent);
        const QColor window(0xef, 0xf0, 0xf1);
        const QColor base(0xff, 0xff, 0xff);
        const QColor text(0x23, 0x26, 0x29);
        p.setColor(QPalette::Window, window);
        p.setColor(QPalette::WindowText, text);
        p.setColor(QPalette::Base, base);
        p.setColor(QPalette::AlternateBase, QColor(0xf7, 0xf7, 0xf7));
        p.setColor(QPalette::ToolTipBase, QColor(0xff, 0xff, 0xdc));
        p.setColor(QPalette::ToolTipText, text);
        p.setColor(QPalette::Text, text);
        p.setColor(QPalette::PlaceholderText, QColor(0x7f, 0x8c, 0x8d));
        p.setColor(QPalette::Button, window);
        p.setColor(QPalette::ButtonText, text);
        p.setColor(QPalette::BrightText, QColor(0xff, 0xff, 0xff));
        p.setColor(QPalette::Link, accent);
        p.setColor(QPalette::Highlight, accent);
        p.setColor(QPalette::HighlightedText, onAccent);
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
        p.setColor(QPalette::Accent, accent);
#endif
        p.setColor(QPalette::Disabled, QPalette::WindowText, QColor(0x8f, 0x94, 0x98));
        p.setColor(QPalette::Disabled, QPalette::Text, QColor(0x8f, 0x94, 0x98));
        p.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(0x8f, 0x94, 0x98));
    }
    return p;
}

// recursively copies a resource directory (e.g. ":/seed") to disk,
// recreating the same subfolder tree
void copyResourceDir(const QString &srcRoot, const QString &dstRoot)
{
    QDirIterator it(srcRoot, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
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
    m_seedSource = QStringLiteral(":/seed");
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

QString Backend::secretsBackend() const
{
    return m_secrets ? m_secrets->medium() : QStringLiteral("file");
}

QString Backend::colorScheme() const
{
    if (!canToggleTheme()) return QStringLiteral("system");
    return m_settings.colorScheme();
}

bool Backend::canToggleTheme() const
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    // The KDE platform theme owns the palette; Qt's color-scheme hint does not
    // override it at runtime. Forced themes are P2 work; on KDE the control is
    // hidden and the app follows the system.
    if (qEnvironmentVariable("XDG_CURRENT_DESKTOP").contains("KDE", Qt::CaseInsensitive))
        return false;
    return true;
#else
    return false;
#endif
}

void Backend::applyColorScheme(const QString &scheme)
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    if (qEnvironmentVariable("XDG_CURRENT_DESKTOP").contains("KDE", Qt::CaseInsensitive)) return;
    (void)systemPalette();   // capture the system palette before any override
    Qt::ColorScheme qtScheme = Qt::ColorScheme::Unknown;   // follow the system
    if (scheme == QLatin1String("light"))
        qtScheme = Qt::ColorScheme::Light;
    else if (scheme == QLatin1String("dark"))
        qtScheme = Qt::ColorScheme::Dark;
    QGuiApplication::styleHints()->setColorScheme(qtScheme);
    // The hint alone is a no-op on platforms without system palette updates
    // (offscreen, some compositors). Resolve the scheme into a palette so the
    // live Kirigami theme retints everywhere; "system" restores the startup one.
    if (qtScheme == Qt::ColorScheme::Unknown) {
        QGuiApplication::setPalette(systemPalette());
    } else {
        QGuiApplication::setPalette(schemePalette(qtScheme));
    }
#endif
}

void Backend::setColorScheme(const QString &scheme)
{
    applyColorScheme(scheme);
    m_settings.setScheme(scheme);
    emit colorSchemeChanged();
}


void Backend::setSecretStore(std::unique_ptr<SecretStore> store)
{
    m_secrets = std::move(store);
    m_secrets->preload();
}

void Backend::setSeedSource(const QString &src)
{
    if (!src.isEmpty())
        m_seedSource = src;
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

bool Backend::storageReadable() const
{
    const QFileInfo info(m_dir);
    return info.isDir() && info.isReadable();
}

bool Backend::canUseStorageDir(const QString &dir) const
{
    if (dir.isEmpty())
        return false;
    const QFileInfo info(dir);
    if (info.exists())
        return info.isDir() && info.isWritable();
    // not created yet: the nearest existing ancestor decides, without creating
    // anything (this runs from a live validation binding)
    QDir parent(dir);
    while (!parent.exists() && parent.cdUp()) {}
    const QFileInfo ancestor(parent.absolutePath());
    return ancestor.isDir() && ancestor.isWritable();
}

QString Backend::activeEnvironment() const { return m_envs->active(); }

void Backend::seedDefaultCollection()
{
    const QString marker = m_dir + QStringLiteral("/.catarina/.seeded");
    if (QFileInfo::exists(marker))
        return;   // already seeded (even if the user deletes the collection later)
    if (collectionTree().isEmpty()) {
        copyResourceDir(m_seedSource, m_dir);
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
