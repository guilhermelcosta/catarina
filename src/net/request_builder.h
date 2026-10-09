#pragma once

#include <QByteArray>
#include <QNetworkRequest>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// Um request já pronto para enviar: URL/método resolvidos, headers montados
// (request + coleção + auth + Content-Type/Accept), corpo codificado e os
// snapshots (headers/corpo) usados pela aba de rede. Sem I/O — testável isolado.
struct BuiltRequest {
    bool valid = false;
    bool ignoreSsl = false;
    QUrl url;
    QString method;
    QString bodyType;
    QNetworkRequest req;
    QVariantList fields;      // já substituídos (multipart/urlencoded)
    QByteArray payload;       // corpo dos tipos não-multipart
    QString sentBody;         // descrição do corpo para a aba de rede
    QVariantList sentHeaders; // headers efetivamente enviados
};

// Monta o BuiltRequest a partir de um request (com {{variáveis}} já resolvidas).
class RequestBuilder
{
public:
    RequestBuilder() = delete;

    static BuiltRequest build(const QVariantMap &request, const QVariantMap &vars,
                              const QVariantList &collectionHeaders,
                              const QVariantMap &collectionAuth,
                              int timeoutSec, bool ignoreSsl);
};
