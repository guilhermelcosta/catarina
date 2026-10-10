#pragma once

#include <QHash>
#include <QString>

#include <memory>

// Secret storage (id -> value) in a single JSON blob, loaded once
// and kept in memory. Persistence sits behind readRaw/writeRaw, so the
// medium (OS keychain, 0600 file, memory) is swappable without touching the logic.
//
// No I/O in the header: tests inject the in-memory implementation via
// createInMemory() and never touch the real keychain or disk.
class SecretStore
{
public:
    virtual ~SecretStore() = default;

    QString value(const QString &id) const;          // "" if it doesn't exist
    bool save(const QString &id, const QString &value);
    bool remove(const QString &id);

    // loads the blob now (the Backend does it in the ctor, before the QML)
    void preload() const;

    // OS keychain when available (and not forced to a file by
    // CATARINA_SECRETS_BACKEND=file); otherwise a 0600 file at filePath.
    // The first time the keychain exists but is empty, it migrates the file there and deletes it.
    static std::unique_ptr<SecretStore> create(const QString &filePath);
    // in-memory implementation, for tests
    static std::unique_ptr<SecretStore> createInMemory();

protected:
    // raw JSON like {"id":"value"}; "" when empty/absent
    virtual QString readRaw() const = 0;
    virtual bool writeRaw(const QString &json) const = 0;

private:
    void ensureLoaded() const;
    bool persist() const;

    mutable bool m_loaded = false;
    mutable QHash<QString, QString> m_cache;
};
