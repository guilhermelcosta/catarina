#pragma once

#include <QLatin1String>
#include <QString>

// Single owner of the request/collection schema keys and values that cross C++↔QML.
// Previously scattered as loose strings; using the constants avoids a silent typo
// (e.g. "bodyType" vs "bodytype") that only showed up at runtime.
namespace RequestSchema {

// common keys (variables, headers, params, fields, auth)
inline constexpr QLatin1String kName("name");
inline constexpr QLatin1String kValue("value");
inline constexpr QLatin1String kEnabled("enabled");
inline constexpr QLatin1String kType("type");
inline constexpr QLatin1String kToken("token");
inline constexpr QLatin1String kUser("user");
inline constexpr QLatin1String kPass("pass");
inline constexpr QLatin1String kKey("key");

// request
inline constexpr QLatin1String kMethod("method");
inline constexpr QLatin1String kUrl("url");
inline constexpr QLatin1String kParams("params");
inline constexpr QLatin1String kHeaders("headers");
inline constexpr QLatin1String kBody("body");
inline constexpr QLatin1String kBodyType("bodyType");
inline constexpr QLatin1String kFields("fields");
inline constexpr QLatin1String kAuth("auth");

// bodyType values
inline constexpr QLatin1String kJson("json");
inline constexpr QLatin1String kText("text");
inline constexpr QLatin1String kUrlencoded("urlencoded");
inline constexpr QLatin1String kMultipart("multipart");
inline constexpr QLatin1String kNone("none");

// auth.type values
inline constexpr QLatin1String kInherit("inherit");
inline constexpr QLatin1String kBearer("bearer");
inline constexpr QLatin1String kBasic("basic");
inline constexpr QLatin1String kApiKey("apikey");

// variables: scope, flags and origin
inline constexpr QLatin1String kVars("vars");
inline constexpr QLatin1String kScope("scope");
inline constexpr QLatin1String kCollections("collections");
inline constexpr QLatin1String kSecret("secret");
inline constexpr QLatin1String kSecretId("secretId");
inline constexpr QLatin1String kAll("all");
inline constexpr QLatin1String kSourceGlobal("global");
inline constexpr QLatin1String kSourceCollection("collection");
inline constexpr QLatin1String kSourceRequest("request");

inline constexpr QLatin1String kContentType("Content-Type");

// case-insensitive comparison of the header name
inline bool isContentType(const QString &name)
{
    return name.compare(kContentType, Qt::CaseInsensitive) == 0;
}

} // namespace RequestSchema
