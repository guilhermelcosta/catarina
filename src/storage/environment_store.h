#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Global environments (list name→variables + the active one), persisted in a file.
// Receives already-sanitized lists (without secrets) — it doesn't touch secrets.
class EnvironmentStore : public QObject
{
    Q_OBJECT
public:
    explicit EnvironmentStore(QObject *parent = nullptr);

    void setFile(const QString &path);   // <dir>/.catarina/environments.json
    void load();

    QVariantList list() const;                                    // {name, count}
    QVariantList variables(const QString &name) const;
    QVariantList activeVariables() const;                         // for the resolver
    QString active() const;

    bool save(const QString &name, const QVariantList &vars);
    bool remove(const QString &name);
    bool rename(const QString &oldName, const QString &newName);
    void setActive(const QString &name);

    // swaps oldName for newName in the environment variables' scope (collection rename)
    bool renameCollectionScope(const QString &oldName, const QString &newName);

signals:
    void changed();

private:
    struct Env {
        QString name;
        QVariantList variables;
    };
    void saveFile() const;

    QList<Env> m_envs;
    QString m_active;
    QString m_file;
};
