#include "secret_store.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

#ifdef CATARINA_HAVE_KEYCHAIN
#include <QEventLoop>
#include <qt6keychain/keychain.h>
#endif

namespace {

// ---- persistence implementations (only the medium changes; cache stays in the base) ----

class MemoryStore : public SecretStore
{
protected:
    QString readRaw() const override { return m_blob; }
    bool writeRaw(const QString &json) const override { m_blob = json; return true; }
private:
    mutable QString m_blob;
};

class FileStore : public SecretStore
{
public:
    explicit FileStore(QString path) : m_path(std::move(path)) {}
protected:
    QString readRaw() const override
    {
        QFile f(m_path);
        if (!f.open(QIODevice::ReadOnly))
            return {};
        return QString::fromUtf8(f.readAll());
    }
    bool writeRaw(const QString &json) const override
    {
        QSaveFile f(m_path);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(json.toUtf8());
        const bool ok = f.commit();
        QFile::setPermissions(m_path, QFile::ReadOwner | QFile::WriteOwner);   // 0600
        return ok;
    }
private:
    QString m_path;
};

QString readLegacyFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll());
}

#ifdef CATARINA_HAVE_KEYCHAIN
constexpr auto kKeychainService = "catarina";
constexpr auto kKeychainEntry = "secrets";

bool keychainAllowed()
{
    return qgetenv("CATARINA_SECRETS_BACKEND").toLower() != "file" && QKeychain::isAvailable();
}

bool keychainWrite(const QString &data)
{
    QKeychain::WritePasswordJob job(QString::fromLatin1(kKeychainService));
    job.setKey(QString::fromLatin1(kKeychainEntry));
    job.setTextData(data);
    QEventLoop loop;
    QObject::connect(&job, &QKeychain::Job::finished, &loop, &QEventLoop::quit);
    job.start();
    loop.exec();
    return job.error() == QKeychain::NoError;
}

// Secrets in the OS keychain as a single JSON blob. The initial read's error decides
// whether the keychain is usable (NoError), just empty (EntryNotFound) or unreachable (other).
class KeychainStore : public SecretStore
{
public:
    KeychainStore()
    {
        QKeychain::ReadPasswordJob job(QString::fromLatin1(kKeychainService));
        job.setKey(QString::fromLatin1(kKeychainEntry));
        QEventLoop loop;
        QObject::connect(&job, &QKeychain::Job::finished, &loop, &QEventLoop::quit);
        job.start();
        loop.exec();
        m_error = job.error();
        if (m_error == QKeychain::NoError)
            m_blob = job.textData();
    }

    QKeychain::Error error() const { return m_error; }

    // migrates a legacy blob (old file) to the keychain
    bool importLegacy(const QString &json) { return writeRaw(json); }

protected:
    QString readRaw() const override { return m_blob; }
    bool writeRaw(const QString &json) const override { return keychainWrite(json); }

private:
    QKeychain::Error m_error = QKeychain::NoError;
    QString m_blob;
};
#endif // CATARINA_HAVE_KEYCHAIN

} // namespace

// ---- base: cache + API ----

void SecretStore::ensureLoaded() const
{
    if (m_loaded)
        return;
    m_loaded = true;
    const QJsonObject obj = QJsonDocument::fromJson(readRaw().toUtf8()).object();
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it)
        m_cache.insert(it.key(), it.value().toString());
}

void SecretStore::preload() const { ensureLoaded(); }

QString SecretStore::value(const QString &id) const
{
    if (id.isEmpty())
        return {};
    ensureLoaded();
    return m_cache.value(id);
}

bool SecretStore::persist() const
{
    QJsonObject obj;
    for (auto it = m_cache.constBegin(); it != m_cache.constEnd(); ++it)
        obj.insert(it.key(), it.value());
    return writeRaw(QString::fromUtf8(QJsonDocument(obj).toJson()));
}

bool SecretStore::save(const QString &id, const QString &value)
{
    if (id.isEmpty())
        return false;
    ensureLoaded();
    m_cache.insert(id, value);
    return persist();
}

bool SecretStore::remove(const QString &id)
{
    if (id.isEmpty())
        return false;
    ensureLoaded();
    if (!m_cache.contains(id))
        return false;
    m_cache.remove(id);
    return persist();
}

std::unique_ptr<SecretStore> SecretStore::create(const QString &filePath)
{
#ifdef CATARINA_HAVE_KEYCHAIN
    if (keychainAllowed()) {
        auto kc = std::make_unique<KeychainStore>();
        if (kc->error() == QKeychain::NoError)
            return kc;
        if (kc->error() == QKeychain::EntryNotFound) {
            // empty keychain: migrates the legacy file, if any, and deletes the plain text
            const QString legacy = readLegacyFile(filePath);
            if (!legacy.isEmpty() && kc->importLegacy(legacy))
                QFile::remove(filePath);
            return kc;
        }
        // any other error (access denied etc.): keeps the file in plain text
    }
#endif
    return std::make_unique<FileStore>(filePath);
}

std::unique_ptr<SecretStore> SecretStore::createInMemory()
{
    return std::make_unique<MemoryStore>();
}
