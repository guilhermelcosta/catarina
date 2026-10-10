#pragma once

#include <QByteArray>
#include <QNetworkRequest>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// A request ready to send: URL/method resolved, headers built
// (request + collection + auth + Content-Type/Accept), body encoded and the
// snapshots (headers/body) used by the network tab. No I/O — testable in isolation.
struct BuiltRequest {
    bool valid = false;
    bool ignoreSsl = false;
    QUrl url;
    QString method;
    QString bodyType;
    QNetworkRequest req;
    QVariantList fields;      // already substituted (multipart/urlencoded)
    QByteArray payload;       // body of the non-multipart types
    QString sentBody;         // body description for the network tab
    QVariantList sentHeaders; // headers actually sent
};

// Builds the BuiltRequest from a request (with {{variables}} already resolved).
class RequestBuilder
{
public:
    RequestBuilder() = delete;

    static BuiltRequest build(const QVariantMap &request, const QVariantMap &vars,
                              const QVariantList &collectionHeaders,
                              const QVariantMap &collectionAuth,
                              int timeoutSec, bool ignoreSsl);
};
