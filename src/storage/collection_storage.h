#pragma once

#include <QHash>
#include <QObject>
#include <QPair>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// CRUD em disco das coleções: requests (.json), pastas e os arquivos de coleção
// (.variables.json / .headers.json / .auth.json). Sem lógica de negócio — não
// resolve {{variáveis}} nem mexe em segredos; recebe e devolve mapas prontos.
// Emite changed() para o Backend repassar à UI como collectionsChanged().
class CollectionStorage : public QObject
{
    Q_OBJECT
public:
    explicit CollectionStorage(QObject *parent = nullptr);

    void setRoot(const QString &dir);   // ~/catarina-collections
    QString root() const;

    QVariantList tree() const;          // itens com name/relPath/isFolder/method/depth/hasChildren
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
    // renomeou uma coleção (pasta de topo): o Backend reaponta o escopo das
    // variáveis de ambiente que a referenciam pelo nome
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
    mutable QHash<QString, QPair<qint64, QString>> m_methodCache; // relPath -> (mtime, método)
    mutable QHash<QString, CachedJson> m_varsCache;               // coleção -> variáveis
    mutable QHash<QString, CachedJson> m_headersCache;            // coleção -> cabeçalhos
    mutable QHash<QString, CachedJson> m_authCache;               // coleção -> auth
};
