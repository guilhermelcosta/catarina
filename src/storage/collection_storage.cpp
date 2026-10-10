#include "collection_storage.h"

#include "core/request_schema.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSet>

namespace {
namespace RS = RequestSchema;

bool copyDirRecursive(const QString &src, const QString &dst)
{
    QDir srcDir(src);
    if (!QDir().mkpath(dst))
        return false;
    for (const QString &f : srcDir.entryList(QDir::Files)) {
        if (!QFile::copy(src + QLatin1Char('/') + f, dst + QLatin1Char('/') + f))
            return false;
    }
    for (const QString &d : srcDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (!copyDirRecursive(src + QLatin1Char('/') + d, dst + QLatin1Char('/') + d))
            return false;
    }
    return true;
}
} // namespace

CollectionStorage::CollectionStorage(QObject *parent)
    : QObject(parent)
{
}

void CollectionStorage::setRoot(const QString &dir)
{
    if (dir == m_root)
        return;
    m_root = dir;
    clearCaches();
}

QString CollectionStorage::root() const { return m_root; }

void CollectionStorage::clearCaches()
{
    m_methodCache.clear();
    m_varsCache.clear();
    m_headersCache.clear();
    m_authCache.clear();
}

QString CollectionStorage::requestPath(const QString &relPath) const
{
    QString safe = relPath;
    safe.replace(QLatin1String(".."), QString());
    while (safe.startsWith(QLatin1Char('/')))
        safe.remove(0, 1);
    return m_root + QLatin1Char('/') + safe + QStringLiteral(".json");
}

void CollectionStorage::walk(const QString &rel, int depth, QVariantList &out) const
{
    const QString abs = m_root + (rel.isEmpty() ? QString() : QLatin1Char('/') + rel);
    QDir dir(abs);
    for (const QString &sub : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (sub.startsWith(QLatin1Char('.')))   // .catarina and the like stay out of the tree
            continue;
        const QString childRel = rel.isEmpty() ? sub : rel + QLatin1Char('/') + sub;
        out.append(QVariantMap{{QStringLiteral("name"), sub},
                               {QStringLiteral("relPath"), childRel},
                               {QStringLiteral("isFolder"), true},
                               {QStringLiteral("depth"), depth}});
        walk(childRel, depth + 1, out);
    }
    for (const QString &file : dir.entryList({QStringLiteral("*.json")}, QDir::Files, QDir::Name)) {
        if (file.startsWith(QLatin1Char('.')))
            continue;
        QString base = file;
        base.chop(5);
        const QString childRel = rel.isEmpty() ? base : rel + QLatin1Char('/') + base;
        // method with cache (mtime): avoids reopening/parsing each request on every reload
        const QString absFile = m_root + QLatin1Char('/') + childRel + QStringLiteral(".json");
        const qint64 mt = QFileInfo(absFile).lastModified().toMSecsSinceEpoch();
        QString method;
        auto it = m_methodCache.constFind(childRel);
        if (it != m_methodCache.constEnd() && it->first == mt) {
            method = it->second;
        } else {
            method = QStringLiteral("GET");
            QFile f(absFile);
            if (f.open(QIODevice::ReadOnly))
                method = QJsonDocument::fromJson(f.readAll()).object().value(RS::kMethod).toString(method);
            m_methodCache.insert(childRel, {mt, method});
        }
        out.append(QVariantMap{{QStringLiteral("name"), base},
                               {QStringLiteral("relPath"), childRel},
                               {QStringLiteral("isFolder"), false},
                               {RS::kMethod, method},
                               {QStringLiteral("depth"), depth}});
    }
}

QVariantList CollectionStorage::tree() const
{
    QVariantList out;
    walk(QString(), 0, out);
    // hasChildren in O(n): marks the ancestors of each entry
    QSet<QString> parents;
    for (const QVariant &v : out) {
        QString rp = v.toMap().value(QStringLiteral("relPath")).toString();
        for (int idx = rp.lastIndexOf(QLatin1Char('/')); idx > 0; idx = rp.lastIndexOf(QLatin1Char('/'))) {
            rp.truncate(idx);
            parents.insert(rp);
        }
    }
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("isFolder")).toBool())
            m[QStringLiteral("hasChildren")] = parents.contains(m.value(QStringLiteral("relPath")).toString());
        v = m;
    }
    return out;
}

QVariantMap CollectionStorage::loadRequest(const QString &relPath) const
{
    QFile f(requestPath(relPath));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}

bool CollectionStorage::isCollection(const QString &relPath) const
{
    if (relPath.isEmpty())
        return false;
    return QFileInfo(m_root + QLatin1Char('/') + relPath).isDir();
}

bool CollectionStorage::saveRequest(const QString &relPath, const QVariantMap &data)
{
    const QString path = requestPath(relPath);
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument(QJsonObject::fromVariantMap(data)).toJson(QJsonDocument::Indented));
    if (!f.commit())
        return false;
    emit changed();
    return true;
}

bool CollectionStorage::deleteEntry(const QString &relPath)
{
    const QString abs = m_root + QLatin1Char('/') + relPath;
    QFileInfo info(abs);
    bool ok = false;
    if (info.isDir())
        ok = QDir(abs).removeRecursively();
    else
        ok = QFile::remove(abs) || QFile::remove(abs + QStringLiteral(".json"));
    if (ok)
        emit changed();
    return ok;
}

bool CollectionStorage::createFolder(const QString &relPath)
{
    const bool ok = QDir().mkpath(m_root + QLatin1Char('/') + relPath);
    if (ok)
        emit changed();
    return ok;
}

bool CollectionStorage::renameEntry(const QString &relPath, const QString &newName)
{
    if (relPath.isEmpty() || newName.isEmpty())
        return false;
    if (newName.contains(QLatin1Char('/')) || newName.contains(QLatin1Char('\\')))
        return false;
    const QString parent = relPath.section(QLatin1Char('/'), 0, -2);
    const QString to = parent.isEmpty() ? newName : parent + QLatin1Char('/') + newName;
    if (to == relPath)
        return false;

    const QString srcAbs = m_root + QLatin1Char('/') + relPath;
    const QString dstAbs = m_root + QLatin1Char('/') + to;
    const bool isDir = QFileInfo(srcAbs).isDir();
    if (QFileInfo::exists(dstAbs) || QFileInfo::exists(dstAbs + QStringLiteral(".json")))
        return false;
    QDir().mkpath(QFileInfo(isDir ? dstAbs : dstAbs + QStringLiteral(".json")).absolutePath());

    const bool ok = isDir ? QDir().rename(srcAbs, dstAbs)
                          : QFile::rename(srcAbs + QStringLiteral(".json"), dstAbs + QStringLiteral(".json"));
    if (ok) {
        // renaming a collection (top-level folder) needs to repoint the scope of the
        // environment variables that reference it by name
        if (isDir && !relPath.contains(QLatin1Char('/')))
            emit collectionRenamed(relPath, newName);
        emit changed();
    }
    return ok;
}

bool CollectionStorage::duplicateEntry(const QString &relPath)
{
    if (relPath.isEmpty())
        return false;
    const QString parent = relPath.section(QLatin1Char('/'), 0, -2);
    const QString base = relPath.section(QLatin1Char('/'), -1);
    const QString srcAbs = m_root + QLatin1Char('/') + relPath;
    const QString parentAbs = parent.isEmpty() ? m_root : m_root + QLatin1Char('/') + parent;
    const bool isDir = QFileInfo(srcAbs).isDir();

    QString name = base + QStringLiteral(" copy");
    int n = 2;
    while (QFileInfo::exists(parentAbs + QLatin1Char('/') + name + (isDir ? QString() : QStringLiteral(".json"))))
        name = base + QStringLiteral(" copy ") + QString::number(n++);

    const QString dstAbs = parentAbs + QLatin1Char('/') + name;
    const bool ok = isDir ? copyDirRecursive(srcAbs, dstAbs)
                          : QFile::copy(srcAbs + QStringLiteral(".json"), dstAbs + QStringLiteral(".json"));
    if (ok)
        emit changed();
    return ok;
}

bool CollectionStorage::moveEntry(const QString &from, const QString &toFolder)
{
    if (from.isEmpty())
        return false;
    if (toFolder == from || toFolder.startsWith(from + QLatin1Char('/')))
        return false;   // can't move into itself

    const QString base = from.section(QLatin1Char('/'), -1);
    const QString dest = (toFolder.isEmpty() ? QString() : toFolder + QLatin1Char('/')) + base;
    if (dest == from)
        return false;

    const QString srcAbs = m_root + QLatin1Char('/') + from;
    const QString dstAbs = m_root + QLatin1Char('/') + dest;
    const bool isDir = QFileInfo(srcAbs).isDir();
    if (QFileInfo::exists(dstAbs) || QFileInfo::exists(dstAbs + QStringLiteral(".json")))
        return false;   // already exists at the destination

    // creates only the destination's PARENT directory (the destination itself can't exist)
    QDir().mkpath(QFileInfo(isDir ? dstAbs : dstAbs + QStringLiteral(".json")).absolutePath());

    bool ok = false;
    if (isDir)
        ok = QDir().rename(srcAbs, dstAbs);
    else
        ok = QFile::rename(srcAbs + QStringLiteral(".json"), dstAbs + QStringLiteral(".json"));

    if (ok)
        emit changed();
    return ok;
}

// reads a field from a .json (with cache validated by mtime); writing the file invalidates it by itself
QVariant CollectionStorage::cachedJson(const QString &path, const QString &key, CachedJson &slot) const
{
    const qint64 mt = QFileInfo(path).lastModified().toMSecsSinceEpoch();
    if (slot.mtime == mt)
        return slot.value;
    QVariant value;
    QFile f(path);
    if (f.open(QIODevice::ReadOnly))
        value = QJsonDocument::fromJson(f.readAll()).object().value(key).toVariant();
    slot.mtime = mt;
    slot.value = value;
    return value;
}

QVariantList CollectionStorage::variables(const QString &collection) const
{
    if (collection.isEmpty())
        return {};
    const QString path = m_root + QLatin1Char('/') + collection + QStringLiteral("/.variables.json");
    return cachedJson(path, RS::kVars, m_varsCache[collection]).toList();
}

bool CollectionStorage::saveVariables(const QString &collection, const QVariantList &vars)
{
    if (collection.isEmpty())
        return false;
    const QString dir = m_root + QLatin1Char('/') + collection;
    QDir().mkpath(dir);
    QSaveFile f(dir + QStringLiteral("/.variables.json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    const QJsonObject obj{{RS::kVars, QJsonArray::fromVariantList(vars)}};
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    const bool ok = f.commit();
    if (ok) {
        m_varsCache[collection].mtime = -1;   // forces a re-read (mtime may have coarse granularity)
        emit changed();
    }
    return ok;
}

QVariantList CollectionStorage::headers(const QString &collection) const
{
    if (collection.isEmpty())
        return {};
    const QString path = m_root + QLatin1Char('/') + collection + QStringLiteral("/.headers.json");
    return cachedJson(path, RS::kHeaders, m_headersCache[collection]).toList();
}

bool CollectionStorage::saveHeaders(const QString &collection, const QVariantList &headers)
{
    if (collection.isEmpty())
        return false;
    const QString dir = m_root + QLatin1Char('/') + collection;
    QDir().mkpath(dir);
    QSaveFile f(dir + QStringLiteral("/.headers.json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    const QJsonObject obj{{RS::kHeaders, QJsonArray::fromVariantList(headers)}};
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    const bool ok = f.commit();
    if (ok) {
        m_headersCache[collection].mtime = -1;
        emit changed();
    }
    return ok;
}

QVariantMap CollectionStorage::auth(const QString &collection) const
{
    if (collection.isEmpty())
        return {};
    const QString path = m_root + QLatin1Char('/') + collection + QStringLiteral("/.auth.json");
    return cachedJson(path, RS::kAuth, m_authCache[collection]).toMap();
}

bool CollectionStorage::saveAuth(const QString &collection, const QVariantMap &auth)
{
    if (collection.isEmpty())
        return false;
    const QString dir = m_root + QLatin1Char('/') + collection;
    QDir().mkpath(dir);
    QSaveFile f(dir + QStringLiteral("/.auth.json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    const QJsonObject obj{{RS::kAuth, QJsonObject::fromVariantMap(auth)}};
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    const bool ok = f.commit();
    if (ok) {
        m_authCache[collection].mtime = -1;
        emit changed();
    }
    return ok;
}
