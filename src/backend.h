#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "settings.h"
#include "core/variable_resolver.h"
#include "storage/collection_storage.h"
#include "storage/environment_store.h"
#include "storage/history_store.h"
#include "storage/secret_store.h"

#include <memory>

class HttpClient;

// Backend: fachada QML. Envia requests (variáveis resolvidas por escopo, params,
// auth, multipart) e delega a persistência aos stores:
//   - CollectionStorage  ~/catarina-collections (.json versionáveis)
//   - EnvironmentStore   <dir>/.catarina/environments.json
//   - HistoryStore       ~/.local/share/catarina/history.json
//   - SecretStore        cofre do SO ou ~/.local/share/catarina/secrets.json (0600)
// Mantém os sinais e a API Q_INVOKABLE que o QML já usa.
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString storageDir READ storageDir CONSTANT)
    Q_PROPERTY(QString activeEnvironment READ activeEnvironment NOTIFY environmentsChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    // injeção (testes): troca o armazenamento de segredos por um em memória,
    // evitando tocar no cofre do SO ou em arquivos
    void setSecretStore(std::unique_ptr<SecretStore> store);

    QString storageDir() const;
    Q_INVOKABLE void setStorageDir(const QString &dir);
    QString activeEnvironment() const;
    // copia a coleção de exemplo embutida (:/seed) no primeiro uso; só quando o
    // storage ainda está vazio e uma única vez (marca .catarina/.seeded)
    Q_INVOKABLE void seedDefaultCollection();

    // ---- lógica pura: movida para RequestLogic (src/core/request_logic.h) ----
    // partes efetivas de um request (method/url/headers/body) para exportação: aplica
    // auth e Content-Type padrão como no send, sem resolver {{variaveis}}
    Q_INVOKABLE QVariantMap requestParts(const QVariantMap &request) const;
    // como requestParts, mas com {{variaveis}} resolvidas (valores efetivos, inclusive
    // segredos), auth herdada aplicada e params anexados à URL — é o cURL "que funciona"
    Q_INVOKABLE QVariantMap resolvedRequestParts(const QVariantMap &request,
                                                 const QString &collection) const;
    // preview do sufixo de query anexado pelos params ativos (mesma semântica do send)
    Q_INVOKABLE QString querySuffix(const QString &url, const QVariantList &params) const;

    // ---- requisição ----
    // request: { method, url, params[], headers[], body, bodyType, fields[], auth{}, vars[] }
    Q_INVOKABLE void send(const QVariantMap &request, const QString &collection);
    Q_INVOKABLE void cancel();          // aborta o request em andamento
    // por que "name" não resolve nesta coleção, por código para a UI traduzir:
    // { "code": "", "collections": [...] }, codes: "" | "disabled" | "restricted" | "undefined"
    Q_INVOKABLE QVariantMap variableNoteFor(const QString &name, const QString &collection) const;

    // ---- coleções ----
    Q_INVOKABLE QVariantList collectionTree() const;
    Q_INVOKABLE bool isCollection(const QString &relPath) const;   // é pasta/coleção?
    Q_INVOKABLE QVariantMap loadRequest(const QString &relPath) const;
    Q_INVOKABLE bool saveRequest(const QString &relPath, const QVariantMap &data);
    Q_INVOKABLE bool deleteEntry(const QString &relPath);
    Q_INVOKABLE bool createFolder(const QString &relPath);
    // move um request ou pasta para dentro de toFolder ("" = raiz)
    Q_INVOKABLE bool moveEntry(const QString &from, const QString &toFolder);
    // renomeia mantendo o mesmo pai (newName é o nome-base, sem .json)
    // renomear uma coleção (pasta de topo) também reaponta o escopo das variáveis
    // de ambiente que a referenciam
    Q_INVOKABLE bool renameEntry(const QString &relPath, const QString &newName);
    // duplica request ou pasta como "<nome> copy"
    Q_INVOKABLE bool duplicateEntry(const QString &relPath);

    // ---- variáveis de coleção (versionadas, sem segredos) ----
    Q_INVOKABLE QVariantList collectionVariables(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionVariables(const QString &collection, const QVariantList &vars);
    // primeiro nome de variável repetido na lista ("" se não houver); nomes aparados
    Q_INVOKABLE QString duplicateVariableName(const QVariantList &vars) const;

    // ---- cabeçalhos de coleção (aplicados a todos os requests dela) ----
    Q_INVOKABLE QVariantList collectionHeaders(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionHeaders(const QString &collection, const QVariantList &headers);

    // ---- autenticação de coleção (herdada por requests com auth "inherit") ----
    Q_INVOKABLE QVariantMap collectionAuth(const QString &collection) const;
    Q_INVOKABLE bool saveCollectionAuth(const QString &collection, const QVariantMap &auth);

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
    // preenche `value` das variáveis secretas a partir do cofre (para edição; o
    // valor nunca é escrito no arquivo versionado — isso continua sendo no save)
    Q_INVOKABLE QVariantList withResolvedSecrets(const QVariantList &vars) const;

    // ---- histórico ----
    Q_INVOKABLE QVariantList history() const;
    Q_INVOKABLE void clearHistory();

    // variáveis efetivas visíveis a uma coleção, já com valores de segredo resolvidos
    // como acima, mas com a origem de cada variável (request/collection/global) — para a UI
    Q_INVOKABLE QVariantList resolvedVariables(const QString &collection,
                                               const QVariantList &requestVars) const;
    // como resolvedVariables, mas com a lista da própria coleção fornecida (em edição),
    // sem escopo de request — usado pela visão geral da coleção
    Q_INVOKABLE QVariantList resolvedCollectionVariables(const QString &collection,
                                                         const QVariantList &collectionVars) const;
    // resolve tudo numa passada: { "resolved": [...], "missing": [...] }
    Q_INVOKABLE QVariantMap variablesState(const QVariantMap &request,
                                           const QString &collection) const;

signals:
    void responseReady(int status, const QString &statusText, const QVariantList &headers,
                       const QString &body, int elapsedMs, int sizeBytes);
    // metadados para a aba de rede/timeline (protocolo, ip, tls, request enviado)
    void responseMeta(const QVariantMap &meta);
    // erro com código + argumentos; a UI monta o texto (Strings.js::backendError)
    void error(const QString &code, const QVariantList &args);
    void started();                     // request despachado
    void canceled();                    // request abortado pelo usuário
    void collectionsChanged();
    void environmentsChanged();
    void historyChanged();

private:
    // variáveis do ambiente ativo (candidatas a globais na resolução)
    QVariantList activeGlobalVars() const;
    // resolver puro com o acesso a segredos deste Backend injetado
    VariableResolver resolver() const;

    // tira os segredos do arquivo (vão pro cofre); limpa o cofre se deixou de ser segredo
    QVariantList sanitizeSecrets(const QVariantList &vars);

    Settings m_settings;                       // mesma config do app (storageDir/timeout/ignoreSsl)
    QString m_dir;         // ~/catarina-collections
    QString m_envFile;     // <dir>/.catarina/environments.json
    QString m_appData;     // ~/.local/share/catarina
    QString m_secretsFile; // <m_appData>/secrets.json
    std::unique_ptr<SecretStore> m_secrets;

    HttpClient *m_http = nullptr;
    CollectionStorage *m_collections = nullptr;
    EnvironmentStore *m_envs = nullptr;
    HistoryStore *m_history = nullptr;
};
