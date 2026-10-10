#pragma once

#include <QHash>
#include <QObject>
#include <QPair>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// On-disk CRUD for collections: requests (.json), folders and the collection files
// (.variables.json / .headers.json / .auth.json). No business logic — it doesn't
// resolve {{variables}} or touch secrets; it receives and returns ready-made maps.
// Emits changed() so the Backend relays it to the UI as collectionsChanged().
class CollectionStorage : public QObject
{
    Q_OBJECT
public:
    explicit CollectionStorage(QObject *parent = nullptr);

    void setRoot(const QString &dir);   // storageDir (default ~/Documents/catarina)
    QString root() const;

    QVariantList tree() const;          // items with name/relPath/isFolder/method/depth/hasChildren
    bool isCollection(const QString &relPath) const;
    QVariantMap loadRequest(const QString &relPath) const;
    bool saveRequest(const QString &relPath, const QVariantMap &data);
    bool deleteEntry(const QString &relPath);
    bool createFolder(const QString &relPath);
    bool renameEntry(const QString &relPath, const QString &newName);
    bool moveEntry(const QString &from, const QString &toFolder);
    bool duplicateEntry(const QString &relPath);

    QVariantList variables(const QString &collection) const;
    bool saveVariables(const QString &collection, const QVariantList &vars);
    QVariantList headers(const QString &collection) const;
    bool saveHeaders(const QString &collection, const QVariantList &headers);
    QVariantMap auth(const QString &collection) const;
    bool saveAuth(const QString &collection, const QVariantMap &auth);

signals:
    void changed();
    // renamed a collection (top-level folder): the Backend repoints the scope of the
    // environment variables that reference it by name
    void collectionRenamed(const QString &oldName, const QString &newName);

private:
    QString requestPath(const QString &relPath) const;
    void walk(const QString &rel, int depth, QVariantList &out) const;
    struct CachedJson {
        qint64 mtime = -1;
        QVariant value;
    };
    QVariant cachedJson(const QString &path, const QString &key, CachedJson &slot) const;
    void clearCaches();

    QString m_root;
    mutable QHash<QString, QPair<qint64, QString>> m_methodCache; // relPath -> (mtime, method)
    mutable QHash<QString, CachedJson> m_varsCache;               // collection -> variables
    mutable QHash<QString, CachedJson> m_headersCache;            // collection -> headers
    mutable QHash<QString, CachedJson> m_authCache;               // collection -> auth
};
