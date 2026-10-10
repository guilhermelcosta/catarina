#include "request_builder.h"

#include "core/request_logic.h"
#include "core/request_schema.h"

namespace {
namespace RS = RequestSchema;

// applies enabled headers; the request has priority over the collection (first-wins)
void applyHeaders(QNetworkRequest &req, const QVariantList &raw, const QVariantMap &vars,
                  bool &hasContentType)
{
    for (const QVariant &v : RequestLogic::substituteList(raw, vars)) {
        const QVariantMap h = v.toMap();
        if (!h.value(RS::kEnabled, true).toBool())
            continue;
        const QString name = h.value(RS::kName).toString();
        if (name.isEmpty())
            continue;
        if (!req.rawHeader(name.toUtf8()).isNull())
            continue;   // the collection doesn't override a header already set by the request
        if (RS::isContentType(name))
            hasContentType = true;
        req.setRawHeader(name.toUtf8(), h.value(RS::kValue).toString().toUtf8());
    }
}
} // namespace

BuiltRequest RequestBuilder::build(const QVariantMap &request, const QVariantMap &vars,
                                   const QVariantList &collectionHeaders,
                                   const QVariantMap &collectionAuth,
                                   int timeoutSec, bool ignoreSsl)
{
    BuiltRequest out;
    out.method = request.value(RS::kMethod).toString();
    out.bodyType = request.value(RS::kBodyType).toString();
    out.ignoreSsl = ignoreSsl;
    out.url = RequestLogic::buildUrl(
        RequestLogic::substitute(request.value(RS::kUrl).toString(), vars),
        RequestLogic::substituteList(request.value(RS::kParams).toList(), vars));
    if (!out.url.isValid() || out.url.host().isEmpty())
        return out;   // valid = false

    QNetworkRequest &req = out.req;
    req = QNetworkRequest(out.url);
    req.setTransferTimeout(timeoutSec * 1000);

    bool hasContentType = false;
    applyHeaders(req, request.value(RS::kHeaders).toList(), vars, hasContentType);
    applyHeaders(req, collectionHeaders, vars, hasContentType);

    QVariantList authList;
    authList.append(RequestLogic::effectiveAuth(request.value(RS::kAuth).toMap(), collectionAuth));
    const QVariantMap ah = RequestLogic::authHeader(RequestLogic::substituteList(authList, vars).value(0).toMap());
    if (!ah.isEmpty())
        req.setRawHeader(ah.value(RS::kName).toString().toUtf8(),
                         ah.value(RS::kValue).toString().toUtf8());

    out.fields = RequestLogic::substituteList(request.value(RS::kFields).toList(), vars);
    const QString ct = RequestLogic::defaultContentType(out.bodyType);
    if (!hasContentType && !ct.isEmpty())
        req.setRawHeader("Content-Type", ct.toUtf8());
    if (req.rawHeader("Accept").isEmpty())
        req.setRawHeader("Accept", "application/json");

    // snapshots for the network tab
    for (const QByteArray &name : req.rawHeaderList())
        out.sentHeaders.append(QVariantMap{{QStringLiteral("name"), QString::fromUtf8(name)},
                                           {QStringLiteral("value"), QString::fromUtf8(req.rawHeader(name))}});
    out.sentBody = (out.bodyType == RS::kMultipart) ? QStringLiteral("(multipart)")
                   : (out.bodyType == RS::kUrlencoded) ? RequestLogic::encodeForm(out.fields)
                   : (out.bodyType == RS::kNone) ? QString()
                   : RequestLogic::substitute(request.value(RS::kBody).toString(), vars);

    // body of the non-multipart types (multipart is built at send time, with QFile devices)
    if (out.bodyType == RS::kUrlencoded)
        out.payload = RequestLogic::encodeForm(out.fields).toUtf8();
    else if (out.bodyType != RS::kNone && out.bodyType != RS::kMultipart)
        out.payload = out.sentBody.toUtf8();   // same resolution as the snapshot (dynamic vars stay consistent)

    out.valid = true;
    return out;
}
