#include "http_client.h"

#include "core/request_schema.h"

#include <QDateTime>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QHttpPart>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslError>

namespace {
namespace RS = RequestSchema;
} // namespace

HttpClient::HttpClient(QObject *parent)
    : QObject(parent)
{
}

bool HttpClient::busy() const { return m_currentReply != nullptr; }

void HttpClient::cancel()
{
    if (m_currentReply)
        m_currentReply->abort();
}

void HttpClient::send(const BuiltRequest &request)
{
    QElapsedTimer timer;
    timer.start();
    QNetworkReply *reply = nullptr;

    if (request.bodyType == RS::kMultipart) {
        auto *multi = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        for (const QVariant &v : request.fields) {
            const QVariantMap m = v.toMap();
            if (!m.value(RS::kEnabled, true).toBool())
                continue;
            const QString name = m.value(RS::kName).toString();
            if (name.isEmpty())
                continue;
            QHttpPart part;
            if (m.value(RS::kType).toString() == QLatin1String("file")) {
                const QString path = m.value(QStringLiteral("fileName")).toString();
                auto *file = new QFile(path, multi);
                if (!file->open(QIODevice::ReadOnly)) {
                    emit error(QStringLiteral("fileOpen"), {path});
                    multi->deleteLater();
                    return;
                }
                part.setHeader(QNetworkRequest::ContentDispositionHeader,
                               QStringLiteral("form-data; name=\"%1\"; filename=\"%2\"")
                                   .arg(name, QFileInfo(path).fileName()));
                part.setBodyDevice(file);
            } else {
                part.setHeader(QNetworkRequest::ContentDispositionHeader,
                               QStringLiteral("form-data; name=\"%1\"").arg(name));
                part.setBody(m.value(RS::kValue).toString().toUtf8());
            }
            multi->append(part);
        }
        reply = (request.method == QLatin1String("PUT")) ? m_nam.put(request.req, multi)
                                                         : m_nam.post(request.req, multi);
        multi->setParent(reply);
    } else {
        reply = m_nam.sendCustomRequest(request.req, request.method.toUtf8(), request.payload);
    }

    m_currentReply = reply;
    emit started();

    const bool ignoreSsl = request.ignoreSsl;
    const QString method = request.method;
    const QUrl url = request.url;
    const QVariantList sentHeaders = request.sentHeaders;
    const QString sentBody = request.sentBody;

    if (ignoreSsl)
        connect(reply, &QNetworkReply::sslErrors, reply,
                [reply](const QList<QSslError> &) { reply->ignoreSslErrors(); });

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, timer, method, url, sentHeaders, sentBody]() {
        if (reply == m_currentReply)
            m_currentReply = nullptr;
        reply->deleteLater();
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            emit canceled();
            return;
        }
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).isNull()) {
            emit error(QStringLiteral("network"), {reply->errorString()});
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString statusText = reply->attribute(QNetworkRequest::HttpReasonPhraseAttribute).toString();
        QVariantList respHeaders;
        for (const auto &pair : reply->rawHeaderPairs())
            respHeaders.append(QVariantMap{{QStringLiteral("name"), QString::fromUtf8(pair.first)},
                                           {QStringLiteral("value"), QString::fromUtf8(pair.second)}});
        const QByteArray bytes = reply->readAll();
        const QJsonDocument doc = QJsonDocument::fromJson(bytes);
        const QString text = doc.isNull() ? QString::fromUtf8(bytes)
                                          : QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
        emit responseReady(status, statusText, respHeaders, text, int(timer.elapsed()), bytes.size());

        // network metadata for the corresponding tab
        const bool encrypted = reply->attribute(QNetworkRequest::ConnectionEncryptedAttribute).toBool();
        const bool http2 = reply->attribute(QNetworkRequest::Http2WasUsedAttribute).toBool();
        emit responseMeta({
            {QStringLiteral("method"), method},
            {QStringLiteral("url"), url.toString()},
            {QStringLiteral("host"), url.host()},
            {QStringLiteral("port"), url.port(url.scheme() == QLatin1String("https") ? 443 : 80)},
            {QStringLiteral("elapsedMs"), int(timer.elapsed())},
            {QStringLiteral("sizeBytes"), bytes.size()},
            {QStringLiteral("encrypted"), encrypted},
            {QStringLiteral("http2"), http2},
            {QStringLiteral("requestHeaders"), sentHeaders},
            {QStringLiteral("requestBody"), sentBody}
        });
        emit historyEntry({{QStringLiteral("method"), method},
                           {QStringLiteral("url"), url.toString()},
                           {QStringLiteral("status"), status},
                           {QStringLiteral("time"), int(timer.elapsed())},
                           {QStringLiteral("ts"), QDateTime::currentSecsSinceEpoch()}});
    });
}
