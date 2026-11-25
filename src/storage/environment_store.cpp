#include "environment_store.h"

#include "core/request_schema.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace {
namespace RS = RequestSchema;
} // namespace

EnvironmentStore::EnvironmentStore(QObject *parent)
    : QObject(parent)
{
}

void EnvironmentStore::setFile(const QString &path)
{
    m_file = path;
}

void EnvironmentStore::load()
{
    m_envs.clear();
    m_active.clear();
    QFile f(m_file);
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    m_active = root.value(QStringLiteral("active")).toString();
    for (const QJsonValue &v : root.value(QStringLiteral("environments")).toArray()) {
        const QJsonObject o = v.toObject();
        m_envs.append({o.value(RS::kName).toString(),
                       o.value(QStringLiteral("variables")).toArray().toVariantList()});
    }
}

void EnvironmentStore::saveFile() const
{
    QJsonArray arr;
    for (const Env &e : m_envs)
        arr.append(QJsonObject{{RS::kName, e.name},
                               {QStringLiteral("variables"), QJsonArray::fromVariantList(e.variables)}});
    const QJsonObject root{{QStringLiteral("active"), m_active},
                           {QStringLiteral("environments"), arr}};

    QSaveFile f(m_file);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.commit();
}

QVariantList EnvironmentStore::list() const
{
    QVariantList out;
    for (const Env &e : m_envs) {
        int count = 0;
        for (const QVariant &v : e.variables)
            if (!v.toMap().value(RS::kName).toString().isEmpty())
                ++count;
        out.append(QVariantMap{{RS::kName, e.name}, {QStringLiteral("count"), count}});
    }
    return out;
}

QVariantList EnvironmentStore::variables(const QString &name) const
{
    for (const Env &e : m_envs)
        if (e.name == name)
            return e.variables;
    return {};
}

QVariantList EnvironmentStore::activeVariables() const
{
    return variables(m_active);
}

QString EnvironmentStore::active() const { return m_active; }

bool EnvironmentStore::save(const QString &name, const QVariantList &vars)
{
    if (name.isEmpty())
        return false;
    for (Env &e : m_envs) {
        if (e.name == name) {
            e.variables = vars;
            saveFile();
            emit changed();
            return true;
        }
    }
    m_envs.append({name, vars});
    if (m_active.isEmpty())
        m_active = name;
    saveFile();
    emit changed();
    return true;
}

bool EnvironmentStore::remove(const QString &name)
{
    for (int i = 0; i < m_envs.size(); ++i) {
        if (m_envs[i].name == name) {
            m_envs.removeAt(i);
            if (m_active == name)
                m_active = m_envs.isEmpty() ? QString() : m_envs.first().name;
            saveFile();
            emit changed();
            return true;
        }
    }
    return false;
}

bool EnvironmentStore::rename(const QString &oldName, const QString &newName)
{
    if (oldName.isEmpty() || newName.isEmpty() || oldName == newName)
        return false;
    for (const Env &o : m_envs)
        if (o.name == newName)
            return false;   // already exists
    for (Env &e : m_envs) {
        if (e.name == oldName) {
            e.name = newName;
            if (m_active == oldName)
                m_active = newName;
            saveFile();
            emit changed();
            return true;
        }
    }
    return false;
}

void EnvironmentStore::setActive(const QString &name)
{
    // no early-return: always persists and notifies (the UI may be out of sync)
    m_active = name;
    saveFile();
    emit changed();
}

bool EnvironmentStore::renameCollectionScope(const QString &oldName, const QString &newName)
{
    bool modified = false;
    for (Env &e : m_envs) {
        for (QVariant &v : e.variables) {
            QVariantMap m = v.toMap();
            if (m.value(RS::kScope).toString() != RS::kCollections)
                continue;
            QStringList list = m.value(RS::kCollections).toStringList();
            if (!list.contains(oldName))
                continue;
            for (QString &s : list)
                if (s == oldName)
                    s = newName;
            m.insert(RS::kCollections, list);
            v = m;
            modified = true;
        }
    }
    if (modified) {
        saveFile();
        emit changed();
    }
    return modified;
}
