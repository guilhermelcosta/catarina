#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Environments globais (lista nome→variáveis + o ativo), persistidos num arquivo.
// Recebe listas já sanitizadas (sem segredos) — não mexe em segredos.
class EnvironmentStore : public QObject
{
    Q_OBJECT
public:
    explicit EnvironmentStore(QObject *parent = nullptr);

    void setFile(const QString &path);   // <dir>/.katarina/environments.json
    void load();

    QVariantList list() const;                                    // {name, count}
    QVariantList variables(const QString &name) const;
    QVariantList activeVariables() const;                         // para o resolver
    QString active() const;

    bool save(const QString &name, const QVariantList &vars);
    bool remove(const QString &name);
    bool rename(const QString &oldName, const QString &newName);
    void setActive(const QString &name);

    // troca oldName por newName no escopo das variáveis de ambiente (rename de coleção)
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
