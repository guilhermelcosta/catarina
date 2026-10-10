#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include "request_builder.h"

class QNetworkReply;

// Sends a BuiltRequest and translates the QNetworkReply into signals. The only class that
// knows QNetworkAccessManager: the rest of the app doesn't deal with reply objects.
class HttpClient : public QObject
{
    Q_OBJECT
public:
    explicit HttpClient(QObject *parent = nullptr);

    void send(const BuiltRequest &request);
    void cancel();
    bool busy() const;

signals:
    void started();                     // request dispatched
    void canceled();                    // request aborted by the user
    void responseReady(int status, const QString &statusText, const QVariantList &headers,
                       const QString &body, int elapsedMs, int sizeBytes);
    void responseMeta(const QVariantMap &meta);
    void historyEntry(const QVariantMap &entry);
    // code + args; the UI builds the text (Strings.js::backendError)
    void error(const QString &code, const QVariantList &args);

private:
    void attachReply(QNetworkReply *reply, const BuiltRequest &request);

    QNetworkAccessManager m_nam;
    QNetworkReply *m_currentReply = nullptr;
};
