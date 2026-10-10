#pragma once

#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// Pure request logic: {{variables}} substitution, URL building, auth,
// form-encode and the effective parts for export. No I/O, no network, no state —
// so it's testable in isolation (check_storage / gtest).
class RequestLogic
{
public:
    RequestLogic() = delete;

    // A single pass, accepting spaces in "{{ name }}". A name that doesn't resolve stays
    // literal (it neither disappears nor becomes empty).
    static QString substitute(const QString &text, const QVariantMap &vars);
    // Replaces EVERY string field (auth uses token/user/pass/key, fields use fileName).
    static QVariantList substituteList(const QVariantList &list, const QVariantMap &vars);
    // {{x}} names in a text, without repetition
    static QStringList variableRefs(const QString &text);
    // assumes http:// when the scheme is missing; skips disabled/unnamed params
    static QUrl buildUrl(const QString &url, const QVariantList &params);
    // query suffix that the active params append to the URL ("?a=1&b=" / "&x=2" / "").
    // Same semantics as buildUrl, but raw (without percent-encode) — it's the UI preview.
    static QString querySuffix(const QString &url, const QVariantList &params);
    // x-www-form-urlencoded of the enabled fields
    static QString encodeForm(const QVariantList &fields);
    // default Content-Type of the bodyType ("" if there's no body)
    static QString defaultContentType(const QString &bodyType);
    // auth header ({} if "none"/empty); "inherit" is NOT resolved here
    static QVariantMap authHeader(const QVariantMap &auth);
    // effective auth: "inherit" uses the collection's; any other type uses the request's
    static QVariantMap effectiveAuth(const QVariantMap &requestAuth, const QVariantMap &collectionAuth);
    // effective parts of a request (method/url/headers/body) for export: applies
    // auth and default Content-Type like on send, without resolving {{variables}}
    static QVariantMap requestParts(const QVariantMap &request);
};
