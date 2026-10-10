#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include "request_builder.h"

class QNetworkReply;

// Envia um BuiltRequest e traduz o QNetworkReply em sinais. Única classe que
// conhece QNetworkAccessManager: o resto do app não lida com objetos de reply.
class HttpClient : public QObject
{
    Q_OBJECT
public:
    explicit HttpClient(QObject *parent = nullptr);

    void send(const BuiltRequest &request);
    void cancel();
    bool busy() const;

signals:
    void started();                     // request despachado
    void canceled();                    // request abortado pelo usuário
    void responseReady(int status, const QString &statusText, const QVariantList &headers,
                       const QString &body, int elapsedMs, int sizeBytes);
    void responseMeta(const QVariantMap &meta);
    void historyEntry(const QVariantMap &entry);
    // código + argumentos; a UI monta o texto (Strings.js::backendError)
    void error(const QString &code, const QVariantList &args);

private:
    void attachReply(QNetworkReply *reply, const BuiltRequest &request);

    QNetworkAccessManager m_nam;
    QNetworkReply *m_currentReply = nullptr;
};
