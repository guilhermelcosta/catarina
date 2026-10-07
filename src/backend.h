#pragma once

#include <QList>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include "settings.h"

class QNetworkReply;

// Backend: envia requests (variáveis resolvidas por escopo, params, auth, multipart)
// e guarda coleções como arquivos .json versionáveis em ~/katarina-collections.
// Segredos ficam fora do repositório (~/.local/share/katarina/secrets.json, 0600).
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString storageDir READ storageDir CONSTANT)
    Q_PROPERTY(QString activeEnvironment READ activeEnvironment NOTIFY environmentsChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    QString storageDir() const;
    Q_INVOKABLE void setStorageDir(const QString &dir);
    QString activeEnvironment() const;

    // ---- lógica pura, testável sem rede ----
    static QString substitute(const QString &text, const QVariantMap &vars);
    static QVariantList substituteList(const QVariantList &list, const QVariantMap &vars);
    static QUrl buildUrl(const QString &url, const QVariantList &params);
    static QVariantMap authHeader(const QVariantMap &auth);
    static QString defaultContentType(const QString &bodyType);
    static QStringList variableRefs(const QString &text);            // nomes {{x}} num texto
    static QString encodeForm(const QVariantList &fields);           // x-www-form-urlencoded

    // ---- requisição ----
    // request: { method, url, params[], headers[], body, bodyType, fields[], auth{}, vars[] }
    Q_INVOKABLE void send(const QVariantMap &request, const QString &collection);
    Q_INVOKABLE void cancel();          // aborta o request em andamento
    Q_INVOKABLE QStringList missingVariables(const QVariantMap &request, const QString &collection) const;
    // por que "name" não resolve nesta coleção: "" (resolve), "restrita a: ..." ou "não definida"
    Q_INVOKABLE QString variableNoteFor(const QString &name, const QString &collection) const;

    // ---- coleções ----
    Q_INVOKABLE QVariantList collectionTree() const;
    Q_INVOKABLE QVariantMap loadRequest(const QString &relPath) const;
    Q_INVOKABLE bool saveRequest(const QString &relPath, const QVariantMap &data);
    Q_INVOKABLE bool deleteEntry(const QString &relPath);
    Q_INVOKABLE bool createFolder(const QString &relPath);
    // move um request ou pasta para dentro de toFolder ("" = raiz)
    Q_INVOKABLE bool moveEntry(const QString &from, const QString &toFolder);
    // renomeia mantendo o mesmo pai (newName é o nome-base, sem .json)
    Q_INVOKABLE bool renameEntry(const QString &relPath, const QString &newName);
    // duplica request ou pasta como "<nome> copy"
    Q_INVOKABLE bool duplicateEntry(const QString &relPath);

    // ---- variáveis de coleção (versionadas, sem segredos) ----
    Q_INVOKABLE QVariantList collectionVariables(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionVariables(const QString &collection, const QVariantList &vars);

    // ---- cabeçalhos de coleção (aplicados a todos os requests dela) ----
    Q_INVOKABLE QVariantList collectionHeaders(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionHeaders(const QString &collection, const QVariantList &headers);

    // ---- environments globais (com escopo por variável) ----
    Q_INVOKABLE QVariantList environments() const;
    Q_INVOKABLE QVariantList environmentVariables(const QString &name) const;
    Q_INVOKABLE bool saveEnvironment(const QString &name, const QVariantList &variables);
    Q_INVOKABLE bool deleteEnvironment(const QString &name);
    Q_INVOKABLE bool renameEnvironment(const QString &oldName, const QString &newName);
    Q_INVOKABLE void setActiveEnvironment(const QString &name);

    // ---- segredos (fora do repo) ----
    Q_INVOKABLE QString secretValue(const QString &id) const;
    Q_INVOKABLE bool saveSecret(const QString &id, const QString &value);
    Q_INVOKABLE bool removeSecret(const QString &id);

    // ---- histórico ----
    Q_INVOKABLE QVariantList history() const;
    Q_INVOKABLE void clearHistory();

    // variáveis efetivas visíveis a uma coleção, já com valores de segredo resolvidos
    Q_INVOKABLE QVariantMap effectiveVariables(const QString &collection,
                                               const QVariantList &requestVars) const;
    // como acima, mas com a origem de cada variável (request/coleção/global) — para a UI
    Q_INVOKABLE QVariantList resolvedVariables(const QString &collection,
                                               const QVariantList &requestVars) const;

signals:
    void responseReady(int status, const QString &statusText, const QVariantList &headers,
                       const QString &body, int elapsedMs, int sizeBytes);
    // metadados para a aba de rede/timeline (protocolo, ip, tls, request enviado)
    void responseMeta(const QVariantMap &meta);
    void error(const QString &message);
    void started();                     // request despachado
    void canceled();                    // request abortado pelo usuário
    void collectionsChanged();
    void environmentsChanged();
    void historyChanged();

private:
    struct Env {
        QString name;
        QVariantList variables;
    };

    QString requestPath(const QString &relPath) const;
    QString historyPath() const;
    void addHistory(const QVariantMap &entry);
    void loadEnvironments();
    void saveEnvironments() const;
    void resolveSecrets(QVariantList &vars) const;   // preenche value a partir de secretId

    QNetworkAccessManager m_nam;
    QNetworkReply *m_currentReply = nullptr;   // para cancelar
    Settings m_settings;                       // mesma config do app (storageDir/timeout/ignoreSsl)
    QString m_dir;         // ~/katarina-collections
    QString m_envFile;     // <dir>/.katarina/environments.json
    QString m_appData;     // ~/.local/share/katarina
    QString m_secretsFile; // <m_appData>/secrets.json

    QList<Env> m_envs;
    QString m_activeEnv;
};
