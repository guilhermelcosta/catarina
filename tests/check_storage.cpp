// Backend logic self-check (no network).
// Run with: ctest  (or ./build/bin/check_storage)
//
// Hermetic: uses a temporary directory for config/collections/secrets,
// so it doesn't touch the user's real data.
#include "backend.h"
#include "core/request_logic.h"
#include "net/request_builder.h"
#include "storage/secret_store.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QTemporaryDir>
#include <QUrlQuery>

#include <cstdio>
#include <cstdlib>

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            std::fprintf(stderr, "FAILED: %s (line %d)\n", #cond, __LINE__);  \
            std::fflush(stderr);                                               \
            std::abort();                                                      \
        }                                                                      \
    } while (0)

// helpers to build variable/param maps without polluting the test
static QVariantMap item(const QString &name, const QVariant &value,
                        bool enabled = true, bool secret = false)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("value"), value},
            {QStringLiteral("enabled"), enabled}, {QStringLiteral("secret"), secret}};
}

// effective map / missing list via variablesState (single resolution API)
static QVariantMap effective(Backend &b, const QString &collection, const QVariantList &requestVars)
{
    return b.variablesState({{QStringLiteral("vars"), requestVars}}, collection)
        .value(QStringLiteral("effective")).toMap();
}
static QStringList missing(Backend &b, const QVariantMap &request, const QString &collection)
{
    return b.variablesState(request, collection).value(QStringLiteral("missing")).toStringList();
}

int main(int argc, char **argv)
{
    QTemporaryDir tmp;
    CHECK(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", tmp.path().toUtf8());
    qputenv("CATARINA_SECRETS_BACKEND", "file");   // hermetic: doesn't touch the OS keychain

    QCoreApplication app(argc, argv);

    // point collections at temp and persist via the same QSettings as the app
    QSettings s(QSettings::IniFormat, QSettings::UserScope,
                QStringLiteral("catarina"), QStringLiteral("catarina"));
    s.setValue(QStringLiteral("storageDir"), tmp.path() + QStringLiteral("/collections"));
    s.sync();

    // ---------------------------------------------------------------- pure
    CHECK(RequestLogic::variableRefs(QStringLiteral("{{a}}/x/{{b}}/{{a}}"))
          == QStringList({QStringLiteral("a"), QStringLiteral("b")}));
    CHECK(RequestLogic::variableRefs(QStringLiteral("{{ a }} {{b}}"))
          == QStringList({QStringLiteral("a"), QStringLiteral("b")}));
    CHECK(RequestLogic::variableRefs(QStringLiteral("no variables")).isEmpty());

    CHECK(RequestLogic::substitute(QStringLiteral("{{base}}/u/{{id}}"),
                              {{QStringLiteral("base"), QStringLiteral("http://x")},
                               {QStringLiteral("id"), 7}})
          == QStringLiteral("http://x/u/7"));
    CHECK(RequestLogic::substitute(QStringLiteral("nada"), {}) == QStringLiteral("nada"));
    // accepts spaces inside {{ name }} (same pattern as variableRefs)
    CHECK(RequestLogic::substitute(QStringLiteral("{{ base }}/{{id}}"),
                              {{QStringLiteral("base"), QStringLiteral("http://x")},
                               {QStringLiteral("id"), 7}})
          == QStringLiteral("http://x/7"));
    // a name that doesn't exist stays literal, doesn't become empty
    CHECK(RequestLogic::substitute(QStringLiteral("{{missing}}"), {{QStringLiteral("x"), QStringLiteral("1")}})
          == QStringLiteral("{{missing}}"));

    // dynamic variables: all "$random"-prefixed, generated on each substitute
    CHECK(RequestLogic::isDynamicVariable(QStringLiteral("$randomUuid")));
    CHECK(RequestLogic::isDynamicVariable(QStringLiteral("$randomTimestamp")));
    CHECK(!RequestLogic::isDynamicVariable(QStringLiteral("$uuid")));   // no bare/alias names
    CHECK(!RequestLogic::isDynamicVariable(QStringLiteral("uuid")));
    CHECK(RequestLogic::dynamicValue(QStringLiteral("nope")).isEmpty());
    {
        const QString uuid = RequestLogic::substitute(QStringLiteral("{{$randomUuid}}"), {});
        CHECK(uuid.length() == 36 && uuid.count(QLatin1Char('-')) == 4);
        CHECK(uuid != RequestLogic::substitute(QStringLiteral("{{$randomUuid}}"), {}));   // fresh each time
        CHECK(RequestLogic::substitute(QStringLiteral("{{$randomTimestamp}}"), {}).toLongLong() > 0);
        CHECK(RequestLogic::substitute(QStringLiteral("{{$randomIsoTimestamp}}"), {}).contains(QLatin1Char('T')));
        const int ri = RequestLogic::substitute(QStringLiteral("{{$randomInt}}"), {}).toInt();
        CHECK(ri >= 0 && ri <= 1000);
        const QString rb = RequestLogic::substitute(QStringLiteral("{{$randomBoolean}}"), {});
        CHECK(rb == QStringLiteral("true") || rb == QStringLiteral("false"));
        const QString rd = RequestLogic::substitute(QStringLiteral("{{$randomDecimal}}"), {});
        CHECK(rd.contains(QLatin1Char('.')) && rd.section(QLatin1Char('.'), 1).length() == 2);
        CHECK(RequestLogic::substitute(QStringLiteral("{{$randomName}}"), {}).contains(QLatin1Char(' ')));
        // a user variable with the same name wins over the dynamic one
        CHECK(RequestLogic::substitute(QStringLiteral("{{$randomUuid}}"),
                                       {{QStringLiteral("$randomUuid"), QStringLiteral("fixed")}})
              == QStringLiteral("fixed"));
    }
    // the table is the single source: every name carries the "$random" prefix
    {
        const QVariantList dyn = RequestLogic::dynamicVariables();
        CHECK(!dyn.isEmpty());
        bool seenUuid = false;
        for (const QVariant &v : dyn) {
            const QVariantMap m = v.toMap();
            const QString n = m.value(QStringLiteral("name")).toString();
            CHECK(n.startsWith(QStringLiteral("$random")));
            CHECK(!m.value(QStringLiteral("value")).toString().isEmpty());
            CHECK(RequestLogic::isDynamicVariable(n));
            if (n == QStringLiteral("$randomUuid")) seenUuid = true;
        }
        CHECK(seenUuid);
    }

    CHECK(RequestLogic::defaultContentType(QStringLiteral("json")) == QStringLiteral("application/json"));
    CHECK(RequestLogic::defaultContentType(QStringLiteral("urlencoded"))
          == QStringLiteral("application/x-www-form-urlencoded"));
    CHECK(RequestLogic::defaultContentType(QStringLiteral("text")) == QStringLiteral("text/plain"));
    CHECK(RequestLogic::defaultContentType(QStringLiteral("multipart")).isEmpty());
    CHECK(RequestLogic::defaultContentType(QStringLiteral("none")).isEmpty());

    const QVariantMap bearer{{QStringLiteral("type"), QStringLiteral("bearer")},
                             {QStringLiteral("token"), QStringLiteral("abc")}};
    CHECK(RequestLogic::authHeader(bearer).value(QStringLiteral("value")) == QStringLiteral("Bearer abc"));

    const QVariantMap basic{{QStringLiteral("type"), QStringLiteral("basic")},
                            {QStringLiteral("user"), QStringLiteral("user")},
                            {QStringLiteral("pass"), QStringLiteral("pass")}};
    CHECK(RequestLogic::authHeader(basic).value(QStringLiteral("value")) == QStringLiteral("Basic dXNlcjpwYXNz"));

    const QVariantMap apikey{{QStringLiteral("type"), QStringLiteral("apikey")},
                             {QStringLiteral("key"), QStringLiteral("X-Key")},
                             {QStringLiteral("value"), QStringLiteral("v")}};
    CHECK(RequestLogic::authHeader(apikey).value(QStringLiteral("name")) == QStringLiteral("X-Key"));
    CHECK(RequestLogic::authHeader(apikey).value(QStringLiteral("value")) == QStringLiteral("v"));
    CHECK(RequestLogic::authHeader({{QStringLiteral("type"), QStringLiteral("none")}}).isEmpty());

    // substituteList: interpolates EVERY string field (the auth uses token/user/pass/key,
    // not just name/value) — regression of the header "Bearer {{token}}"
    {
        const QVariantList sub = RequestLogic::substituteList(
            {QVariantMap{{QStringLiteral("type"), QStringLiteral("bearer")},
                         {QStringLiteral("token"), QStringLiteral("{{tok}}")}}},
            {{QStringLiteral("tok"), QStringLiteral("s3cr3t")}});
        CHECK(sub.value(0).toMap().value(QStringLiteral("token")) == QStringLiteral("s3cr3t"));
        CHECK(RequestLogic::authHeader(sub.value(0).toMap()).value(QStringLiteral("value"))
              == QStringLiteral("Bearer s3cr3t"));
    }

    // effectiveAuth: "inherit" returns the collection auth; any other type, the request's
    {
        const QVariantMap col{{QStringLiteral("type"), QStringLiteral("bearer")},
                              {QStringLiteral("token"), QStringLiteral("col-tok")}};
        const QVariantMap mine{{QStringLiteral("type"), QStringLiteral("basic")},
                               {QStringLiteral("user"), QStringLiteral("u")},
                               {QStringLiteral("pass"), QStringLiteral("p")}};
        CHECK(RequestLogic::effectiveAuth({{QStringLiteral("type"), QStringLiteral("inherit")}}, col)
              == col);
        CHECK(RequestLogic::effectiveAuth(mine, col) == mine);
    }

    // buildUrl: assumes http:// when the scheme is missing, respects disabled params
    {
        const QUrl u = RequestLogic::buildUrl(QStringLiteral("example.com/api"),
                                         {item(QStringLiteral("page"), QStringLiteral("2"))});
        CHECK(u.scheme() == QStringLiteral("http"));
        CHECK(QUrlQuery(u).queryItemValue(QStringLiteral("page")) == QStringLiteral("2"));
    }
    {
        const QUrl u = RequestLogic::buildUrl(QStringLiteral("https://h/p?a=1"),
                                         {item(QStringLiteral("b"), QStringLiteral("2")),
                                          item(QStringLiteral("ignored"), QStringLiteral("x"), false)});
        CHECK(u.scheme() == QStringLiteral("https"));
        const QUrlQuery q(u);
        CHECK(q.queryItemValue(QStringLiteral("a")) == QStringLiteral("1"));
        CHECK(q.queryItemValue(QStringLiteral("b")) == QStringLiteral("2"));
        CHECK(!q.hasQueryItem(QStringLiteral("ignored")));
    }

    CHECK(RequestLogic::encodeForm({item(QStringLiteral("a"), QStringLiteral("1 2")),
                               item(QStringLiteral("b"), QStringLiteral("x"), false)})
          == QStringLiteral("a=1%202"));

    // ---------------------------------------------------------------- environment
    Backend b;
    CHECK(!b.storageDir().isEmpty());
    CHECK(b.storageDir().startsWith(tmp.path()));

    // requestParts: active headers + auth + default Content-Type + body according to type
    {
        const QVariantMap r{{QStringLiteral("method"), QStringLiteral("POST")},
                            {QStringLiteral("url"), QStringLiteral("http://x/y")},
                            {QStringLiteral("headers"), QVariantList{item(QStringLiteral("X-A"), QStringLiteral("1"))}},
                            {QStringLiteral("body"), QStringLiteral("{\"a\":1}")},
                            {QStringLiteral("bodyType"), QStringLiteral("json")},
                            {QStringLiteral("auth"), QVariantMap{{QStringLiteral("type"), QStringLiteral("bearer")},
                                                                 {QStringLiteral("token"), QStringLiteral("t")}}}};
        const QVariantMap parts = RequestLogic::requestParts(r);
        CHECK(parts.value(QStringLiteral("method")) == QStringLiteral("POST"));
        bool auth = false, ct = false, xa = false;
        for (const QVariant &v : parts.value(QStringLiteral("headers")).toList()) {
            const QVariantMap h = v.toMap();
            if (h.value(QStringLiteral("name")) == QStringLiteral("Authorization")
                && h.value(QStringLiteral("value")) == QStringLiteral("Bearer t")) auth = true;
            if (h.value(QStringLiteral("name")) == QStringLiteral("Content-Type")
                && h.value(QStringLiteral("value")) == QStringLiteral("application/json")) ct = true;
            if (h.value(QStringLiteral("name")) == QStringLiteral("X-A")) xa = true;
        }
        CHECK(auth && ct && xa);
        CHECK(parts.value(QStringLiteral("body")) == QStringLiteral("{\"a\":1}"));
    }

    // resolvedRequestParts: {{variables}} become real values (including secrets),
    // params go into the URL and auth (inherit) is applied — that's what the exported cURL shows
    {
        QVariantList vars;
        vars.append(item(QStringLiteral("base"), QStringLiteral("https://api.example.com")));
        vars.append(item(QStringLiteral("tok"), QStringLiteral("s3cr3t")));
        vars.append(item(QStringLiteral("term"), QStringLiteral("ana")));
        const QVariantMap r{
            {QStringLiteral("method"), QStringLiteral("GET")},
            {QStringLiteral("url"), QStringLiteral("{{base}}/users")},
            {QStringLiteral("params"), QVariantList{item(QStringLiteral("q"), QStringLiteral("{{term}}"))}},
            {QStringLiteral("headers"), QVariantList{item(QStringLiteral("X-T"), QStringLiteral("{{tok}}"))}},
            {QStringLiteral("fields"), QVariantList{}},
            {QStringLiteral("body"), QString()},
            {QStringLiteral("bodyType"), QStringLiteral("none")},
            {QStringLiteral("auth"), QVariantMap{{QStringLiteral("type"), QStringLiteral("bearer")},
                                                 {QStringLiteral("token"), QStringLiteral("{{tok}}")}}},
            {QStringLiteral("vars"), vars}};
        const QVariantMap parts = b.resolvedRequestParts(r, QString());
        CHECK(parts.value(QStringLiteral("url")).toString()
              == QStringLiteral("https://api.example.com/users?q=ana"));
        bool xt = false, authHeader = false;
        for (const QVariant &v : parts.value(QStringLiteral("headers")).toList()) {
            const QVariantMap h = v.toMap();
            if (h.value(QStringLiteral("name")) == QStringLiteral("X-T")
                && h.value(QStringLiteral("value")) == QStringLiteral("s3cr3t")) xt = true;
            if (h.value(QStringLiteral("name")) == QStringLiteral("Authorization")
                && h.value(QStringLiteral("value")) == QStringLiteral("Bearer s3cr3t")) authHeader = true;
        }
        CHECK(xt && authHeader);
        // requestParts (raw) does NOT resolve — behavior preserved
        CHECK(RequestLogic::requestParts(r).value(QStringLiteral("url")).toString()
              == QStringLiteral("{{base}}/users"));
    }

    b.deleteEnvironment(QStringLiteral("__e1__"));
    QVariantList ev;
    ev.append(QVariantMap{{QStringLiteral("name"), QStringLiteral("pub")},
                          {QStringLiteral("value"), QStringLiteral("1")},
                          {QStringLiteral("scope"), QStringLiteral("all")}});
    ev.append(QVariantMap{{QStringLiteral("name"), QStringLiteral("priv")},
                          {QStringLiteral("value"), QStringLiteral("2")},
                          {QStringLiteral("scope"), QStringLiteral("collections")},
                          {QStringLiteral("collections"), QStringList{QStringLiteral("colA")}}});
    ev.append(QVariantMap{{QStringLiteral("name"), QStringLiteral("tok")},
                          {QStringLiteral("value"), QStringLiteral("s3cr3t")},
                          {QStringLiteral("scope"), QStringLiteral("all")},
                          {QStringLiteral("secret"), true}});
    ev.append(QVariantMap{{QStringLiteral("name"), QStringLiteral("des")},
                          {QStringLiteral("value"), QStringLiteral("9")},
                          {QStringLiteral("scope"), QStringLiteral("all")},
                          {QStringLiteral("enabled"), false}});
    CHECK(b.saveEnvironment(QStringLiteral("__e1__"), ev));
    b.setActiveEnvironment(QStringLiteral("__e1__"));

    const QVariantMap a = effective(b, QStringLiteral("colA"), {});
    CHECK(a.contains(QStringLiteral("pub")) && a.contains(QStringLiteral("priv")));
    CHECK(a.value(QStringLiteral("tok")).toString() == QStringLiteral("s3cr3t")); // came from the keychain
    CHECK(!a.contains(QStringLiteral("des")));                                    // disabled doesn't resolve
    CHECK(b.variableNoteFor(QStringLiteral("des"), QStringLiteral("colA"))
              .value(QStringLiteral("code")) == QStringLiteral("disabled"));

    const QVariantMap c = effective(b, QStringLiteral("colB"), {});
    CHECK(!c.contains(QStringLiteral("priv")));                                  // scope respected
    CHECK(c.value(QStringLiteral("tok")).toString() == QStringLiteral("s3cr3t"));

    // the versioned file must NOT contain the secret value
    QFile ef(b.storageDir() + QStringLiteral("/.catarina/environments.json"));
    CHECK(ef.open(QIODevice::ReadOnly));
    CHECK(!QString::fromUtf8(ef.readAll()).contains(QStringLiteral("s3cr3t")));
    ef.close();

    // precedence: request > collection > global
    const QVariantMap over = effective(b, 
        QStringLiteral("colA"),
        {item(QStringLiteral("pub"), QStringLiteral("req"))});
    CHECK(over.value(QStringLiteral("pub")).toString() == QStringLiteral("req"));

    // disabled in the request doesn't override: falls back to the global
    const QVariantMap offReq = effective(b, 
        QStringLiteral("colA"),
        {item(QStringLiteral("pub"), QStringLiteral("req"), false)});
    CHECK(offReq.value(QStringLiteral("pub")).toString() == QStringLiteral("1"));
    {
        const QVariantList rv = b.resolvedVariables(
            QStringLiteral("colA"),
            {item(QStringLiteral("pub"), QStringLiteral("req"), false)});
        for (const QVariant &v : rv)
            if (v.toMap().value(QStringLiteral("name")) == QStringLiteral("pub")) {
                CHECK(v.toMap().value(QStringLiteral("enabled")).toBool() == true);
                CHECK(v.toMap().value(QStringLiteral("source")) == QStringLiteral("global"));
            }
    }

    // variable used but nonexistent => blocks
    const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{pub}}/x/{{nope}}")}};
    CHECK(missing(b, req, QStringLiteral("colA")) == QStringList{QStringLiteral("nope")});

    // scope note (used by the UI): codes, not text
    CHECK(b.variableNoteFor(QStringLiteral("pub"), QStringLiteral("colB"))
              .value(QStringLiteral("code")).toString().isEmpty());
    {
        const QVariantMap privNote = b.variableNoteFor(QStringLiteral("priv"), QStringLiteral("colB"));
        CHECK(privNote.value(QStringLiteral("code")) == QStringLiteral("restricted"));
        CHECK(privNote.value(QStringLiteral("collections")).toStringList()
              == QStringList{QStringLiteral("colA")});
    }
    CHECK(b.variableNoteFor(QStringLiteral("nope"), QStringLiteral("colA"))
              .value(QStringLiteral("code")) == QStringLiteral("undefined"));

    // resolvedVariables: origin of each variable
    {
        const QVariantList rv = b.resolvedVariables(QStringLiteral("colA"), {});
        bool seenPub = false, seenTok = false;
        for (const QVariant &v : rv) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("name")) == QStringLiteral("pub")) {
                seenPub = true;
                CHECK(m.value(QStringLiteral("source")) == QStringLiteral("global"));
                CHECK(m.value(QStringLiteral("secret")).toBool() == false);
            }
            if (m.value(QStringLiteral("name")) == QStringLiteral("tok")) {
                seenTok = true;
                CHECK(m.value(QStringLiteral("secret")).toBool() == true);
            }
            if (m.value(QStringLiteral("name")) == QStringLiteral("des"))
                CHECK(m.value(QStringLiteral("enabled")).toBool() == false);
        }
        CHECK(seenPub && seenTok);
    }

    // name and value can reference another variable: {{pub}} in the name becomes pub's VALUE
    {
        const QVariantMap interp = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("{{pub}}"), QStringLiteral("req2"))});
        CHECK(!interp.contains(QStringLiteral("{{pub}}")));                       // name resolved
        CHECK(interp.value(QStringLiteral("1")).toString() == QStringLiteral("req2"));
        CHECK(interp.value(QStringLiteral("pub")).toString() == QStringLiteral("1")); // global intact

        const QVariantMap valRef = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("alias"), QStringLiteral("{{pub}}!"))});
        CHECK(valRef.value(QStringLiteral("alias")).toString() == QStringLiteral("1!"));

        // chained: the name references a name that only comes to exist after another
        // resolution. variable-1=value 1; {{variable-1}}=value 2 (becomes "value 1");
        // {{value 1}}=value 3 (becomes "value 2").
        const QVariantMap chainRef = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variable-1"), QStringLiteral("value 1")),
             item(QStringLiteral("{{variable-1}}"), QStringLiteral("value 2")),
             item(QStringLiteral("{{value 1}}"), QStringLiteral("value 3"))});
        CHECK(chainRef.value(QStringLiteral("variable-1")).toString() == QStringLiteral("value 1"));
        CHECK(chainRef.value(QStringLiteral("value 1")).toString() == QStringLiteral("value 2"));
        CHECK(chainRef.value(QStringLiteral("value 2")).toString() == QStringLiteral("value 3"));
    }

    // long chain (5 levels), like the app's: each name references the already-resolved name
    // of the previous one
    {
        const QVariantMap c5 = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variable-1"), QStringLiteral("value 1")),
             item(QStringLiteral("{{variable-1}}"), QStringLiteral("value 2")),
             item(QStringLiteral("{{value 1}}"), QStringLiteral("new value")),
             item(QStringLiteral("{{value 2}}"), QStringLiteral("test")),
             item(QStringLiteral("{{new value}}"), QStringLiteral("tail"))});
        CHECK(c5.value(QStringLiteral("variable-1")).toString() == QStringLiteral("value 1"));
        CHECK(c5.value(QStringLiteral("value 1")).toString() == QStringLiteral("value 2"));
        CHECK(c5.value(QStringLiteral("value 2")).toString() == QStringLiteral("new value"));
        CHECK(c5.value(QStringLiteral("new value")).toString() == QStringLiteral("test"));
        CHECK(c5.value(QStringLiteral("test")).toString() == QStringLiteral("tail"));
        CHECK(!c5.contains(QStringLiteral("{{new value}}")));

        // same chain through the UI path (variablesState -> resolved)
        const QVariantMap req5{
            {QStringLiteral("vars"),
             QVariantList{item(QStringLiteral("variable-1"), QStringLiteral("value 1")),
                          item(QStringLiteral("{{variable-1}}"), QStringLiteral("value 2")),
                          item(QStringLiteral("{{value 1}}"), QStringLiteral("new value")),
                          item(QStringLiteral("{{value 2}}"), QStringLiteral("test")),
                          item(QStringLiteral("{{new value}}"), QStringLiteral("tail"))}}};
        bool seenTeste = false, seenRaw = false;
        for (const QVariant &v : b.variablesState(req5, QStringLiteral("colA"))
                                     .value(QStringLiteral("resolved")).toList()) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("name")) == QStringLiteral("test")) {
                seenTeste = true;
                CHECK(m.value(QStringLiteral("value")).toString() == QStringLiteral("tail"));
            }
            if (m.value(QStringLiteral("name")) == QStringLiteral("{{new value}}"))
                seenRaw = true;
        }
        CHECK(seenTeste && !seenRaw);
    }

    // reproduction of the app case: global "test" + simple vars + {{new value}} last
    {
        b.deleteEnvironment(QStringLiteral("__echain__"));
        CHECK(b.saveEnvironment(QStringLiteral("__echain__"),
            {QVariantMap{{QStringLiteral("name"), QStringLiteral("test")},
                         {QStringLiteral("value"), QStringLiteral("testevalor")}}}));
        b.setActiveEnvironment(QStringLiteral("__echain__"));
        const QVariantMap ce = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variable-1"), QStringLiteral("value 1")),
             item(QStringLiteral("{{variable-1}}"), QStringLiteral("value 2")),
             item(QStringLiteral("{{value 1}}"), QStringLiteral("new value")),
             item(QStringLiteral("{{value 2}}"), QStringLiteral("test")),
             item(QStringLiteral("test24"), QStringLiteral("123")),
             item(QStringLiteral("test343"), QStringLiteral("123")),
             item(QStringLiteral("test4534"), QStringLiteral("134")),
             item(QStringLiteral("fgdg"), QStringLiteral("2313")),
             item(QStringLiteral("fgd"), QStringLiteral("3232")),
             item(QStringLiteral("{{new value}}"), QStringLiteral("end"))});
        // "new value" (Row4) = "test" ⇒ {{new value}} becomes "test" (overrides the global)
        CHECK(!ce.contains(QStringLiteral("{{new value}}")));
        CHECK(ce.value(QStringLiteral("new value")).toString() == QStringLiteral("test"));
        CHECK(ce.value(QStringLiteral("test")).toString() == QStringLiteral("end"));
        b.deleteEnvironment(QStringLiteral("__echain__"));
    }

    // real data (app file): names with TABs at the edges/inside the braces must not
    // break the chain — the name has to be trimmed before becoming a key
    {
        const QVariantMap ct = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variable-1"), QStringLiteral("value 1")),
             item(QStringLiteral("{{variable-1}}"), QStringLiteral("value 2")),
             item(QStringLiteral("{{value 1}}"), QStringLiteral("new value")),
             item(QStringLiteral("{{value 2}}\t"), QStringLiteral("test")),
             item(QStringLiteral("{{new value\t}}\t"), QStringLiteral("end"))});
        CHECK(!ct.contains(QStringLiteral("{{new value\t}}\t")));
        CHECK(ct.value(QStringLiteral("value 2")).toString() == QStringLiteral("new value"));
        CHECK(ct.value(QStringLiteral("new value")).toString() == QStringLiteral("test"));
        CHECK(ct.value(QStringLiteral("test")).toString() == QStringLiteral("end"));
    }

    // missing scans url, body, headers, fields and auth
    {
        const QVariantMap r{{QStringLiteral("url"), QStringLiteral("{{pub}}")},
                            {QStringLiteral("body"), QStringLiteral("{{body_var}}")},
                            {QStringLiteral("headers"), QVariantList{item(QStringLiteral("X"), QStringLiteral("{{hdr}}"))}}};
        CHECK(missing(b, r, QStringLiteral("colA"))
              == QStringList({QStringLiteral("body_var"), QStringLiteral("hdr")}));
    }

    // dynamic variables resolve on send, so they're never in the "missing" list
    CHECK(missing(b, {{QStringLiteral("url"), QStringLiteral("{{$randomUuid}}/{{$randomTimestamp}}")}},
                  QStringLiteral("colA")).isEmpty());

    // variablesState: resolved + missing + effective in a single pass
    {
        const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{pub}}/{{nope}}")},
                              {QStringLiteral("vars"), QVariantList{}}};
        const QVariantMap st = b.variablesState(req, QStringLiteral("colA"));
        CHECK(st.value(QStringLiteral("missing")).toStringList() == QStringList{QStringLiteral("nope")});
        CHECK(st.value(QStringLiteral("effective")).toMap().value(QStringLiteral("pub")).toString()
              == QStringLiteral("1"));
        CHECK(!st.value(QStringLiteral("resolved")).toList().isEmpty());
    }

    // secrets: persistence across instances (cache + file)
    {
        b.saveSecret(QStringLiteral("__sid__"), QStringLiteral("sv"));
        Backend b3;
        CHECK(b3.secretValue(QStringLiteral("__sid__")) == QStringLiteral("sv"));
        CHECK(b3.removeSecret(QStringLiteral("__sid__")));
        CHECK(b3.secretValue(QStringLiteral("__sid__")).isEmpty());
    }

    // collectionTree: hasChildren computed in O(n)
    {
        b.deleteEntry(QStringLiteral("__tree__"));
        b.createFolder(QStringLiteral("__tree__/sub"));
        b.saveRequest(QStringLiteral("__tree__/r"), {{QStringLiteral("method"), QStringLiteral("POST")}});
        const QVariantList t = b.collectionTree();
        bool folderSeen = false, subSeen = false;
        for (const QVariant &v : t) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("relPath")) == QStringLiteral("__tree__")) {
                folderSeen = true;
                CHECK(m.value(QStringLiteral("hasChildren")).toBool() == true);
            }
            if (m.value(QStringLiteral("relPath")) == QStringLiteral("__tree__/sub"))
                subSeen = true;
        }
        CHECK(folderSeen && subSeen);
        b.deleteEntry(QStringLiteral("__tree__"));
    }

    // environments: rename/duplicate/persist
    CHECK(b.renameEnvironment(QStringLiteral("__e1__"), QStringLiteral("__e1b__")));
    CHECK(b.activeEnvironment() == QStringLiteral("__e1b__"));
    CHECK(!b.renameEnvironment(QStringLiteral("__e1b__"), QStringLiteral("__e1b__")));
    {
        Backend b2;   // reloads from the file
        bool found = false;
        const QVariantList envs = b2.environments();
        for (const QVariant &v : envs)
            if (v.toMap().value(QStringLiteral("name")) == QStringLiteral("__e1b__"))
                found = true;
        CHECK(found);
        b2.deleteEnvironment(QStringLiteral("__e1b__"));
        CHECK(b2.environments().isEmpty());
    }
    b.deleteEnvironment(QStringLiteral("__e1b__"));

    // ---------------------------------------------------------------- collection
    b.deleteEntry(QStringLiteral("__col__"));
    CHECK(b.saveCollectionVariables(QStringLiteral("__col__"),
                                    {item(QStringLiteral("cv"), QStringLiteral("7")),
                                     item(QStringLiteral("cvoff"), QStringLiteral("8"), false)}));
    CHECK(b.collectionVariables(QStringLiteral("__col__")).size() == 2);
    {
        const QVariantMap colEff = effective(b, QStringLiteral("__col__"), {});
        CHECK(colEff.value(QStringLiteral("cv")).toString() == QStringLiteral("7"));
        CHECK(!colEff.contains(QStringLiteral("cvoff")));   // disabled in the collection doesn't resolve
    }
    CHECK(b.variableNoteFor(QStringLiteral("cvoff"), QStringLiteral("__col__"))
              .value(QStringLiteral("code")) == QStringLiteral("disabled"));
    CHECK(missing(b, {{QStringLiteral("url"), QStringLiteral("{{cvoff}}")}},
                             QStringLiteral("__col__"))
          == QStringList{QStringLiteral("cvoff")});
    // overview: collection variable being edited keeps source "collection" (not "request")
    {
        bool seen = false;
        for (const QVariant &v : b.resolvedCollectionVariables(
                 QStringLiteral("__col__"), {item(QStringLiteral("cv"), QStringLiteral("7"))})) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("name")) == QStringLiteral("cv")) {
                seen = true;
                CHECK(m.value(QStringLiteral("source")) == QStringLiteral("collection"));
            }
        }
        CHECK(seen);
    }
    CHECK(b.saveCollectionHeaders(QStringLiteral("__col__"),
                                  {item(QStringLiteral("X-Test"), QStringLiteral("abc"))}));
    CHECK(b.collectionHeaders(QStringLiteral("__col__")).size() == 1);
    CHECK(b.collectionHeaders(QStringLiteral("__col__")).first().toMap()
              .value(QStringLiteral("value")) == QStringLiteral("abc"));
    // cache invalidated when saving again (vars and headers)
    CHECK(b.saveCollectionVariables(QStringLiteral("__col__"),
                                    {item(QStringLiteral("cv"), QStringLiteral("9"))}));
    CHECK(b.collectionVariables(QStringLiteral("__col__")).size() == 1);
    CHECK(b.saveCollectionHeaders(QStringLiteral("__col__"),
                                  {item(QStringLiteral("A"), QStringLiteral("1")),
                                   item(QStringLiteral("B"), QStringLiteral("2"))}));
    CHECK(b.collectionHeaders(QStringLiteral("__col__")).size() == 2);
    // collection auth: round-trip and cache invalidated when saving again
    CHECK(b.saveCollectionAuth(QStringLiteral("__col__"),
                               {{QStringLiteral("type"), QStringLiteral("bearer")},
                                {QStringLiteral("token"), QStringLiteral("t1")}}));
    CHECK(b.collectionAuth(QStringLiteral("__col__")).value(QStringLiteral("token"))
          == QStringLiteral("t1"));
    CHECK(b.saveCollectionAuth(QStringLiteral("__col__"),
                               {{QStringLiteral("type"), QStringLiteral("basic")}}));
    CHECK(b.collectionAuth(QStringLiteral("__col__")).value(QStringLiteral("type"))
          == QStringLiteral("basic"));
    b.deleteEntry(QStringLiteral("__col__"));

    // ---------------------------------------------------------------- duplicate names in the same scope
    {
        CHECK(b.duplicateVariableName({item(QStringLiteral("a"), QStringLiteral("1")),
                                       item(QStringLiteral("a"), QStringLiteral("2"))})
              == QStringLiteral("a"));
        CHECK(b.duplicateVariableName({item(QStringLiteral("a"), QStringLiteral("1")),
                                       item(QStringLiteral("b"), QStringLiteral("2"))}).isEmpty());
        // names are trimmed: "a " collides with "a"
        CHECK(b.duplicateVariableName({item(QStringLiteral("a"), QStringLiteral("1")),
                                       item(QStringLiteral("a "), QStringLiteral("2"))})
              == QStringLiteral("a"));
        // refuses to save with duplicates in the 3 scopes
        CHECK(!b.saveCollectionVariables(QStringLiteral("__dup__"),
                                         {item(QStringLiteral("x"), QStringLiteral("1")),
                                          item(QStringLiteral("x"), QStringLiteral("2"))}));
        CHECK(!b.saveEnvironment(QStringLiteral("__dup_env__"),
                                 {item(QStringLiteral("y"), QStringLiteral("1")),
                                  item(QStringLiteral("y"), QStringLiteral("2"))}));
        CHECK(!b.saveRequest(QStringLiteral("__dup__/r"),
                             {{QStringLiteral("method"), QStringLiteral("GET")},
                              {QStringLiteral("vars"), QVariantList{item(QStringLiteral("z"), QStringLiteral("1")),
                                                                    item(QStringLiteral("z"), QStringLiteral("2"))}}}));
        // same name in different scopes is allowed (they overlap)
        CHECK(b.saveCollectionVariables(QStringLiteral("__dup__"), {item(QStringLiteral("x"), QStringLiteral("1"))}));
        b.deleteEntry(QStringLiteral("__dup__"));
        b.deleteEnvironment(QStringLiteral("__dup_env__"));
    }

    // ---------------------------------------------------------------- requests
    const QString rel = QStringLiteral("__check__/req");
    b.deleteEntry(QStringLiteral("__check__"));
    CHECK(b.saveRequest(rel, {{QStringLiteral("method"), QStringLiteral("POST")},
                              {QStringLiteral("url"), QStringLiteral("http://x/y")}}));
    CHECK(b.loadRequest(rel).value(QStringLiteral("method")).toString() == QStringLiteral("POST"));
    CHECK(b.deleteEntry(QStringLiteral("__check__")));
    CHECK(b.loadRequest(rel).isEmpty());

    // request secret: value doesn't go to the file, secretId does
    {
        const QString sr = QStringLiteral("__secret__/r");
        b.deleteEntry(QStringLiteral("__secret__"));
        CHECK(b.saveRequest(sr, {{QStringLiteral("method"), QStringLiteral("GET")},
                                 {QStringLiteral("url"), QStringLiteral("http://x")},
                                 {QStringLiteral("vars"), QVariantList{item(QStringLiteral("v"),
                                                                           QStringLiteral("topsecret"),
                                                                           true, true)}}}));
        QFile f(b.storageDir() + QStringLiteral("/__secret__/r.json"));
        CHECK(f.open(QIODevice::ReadOnly));
        const QByteArray raw = f.readAll();
        f.close();
        CHECK(!raw.contains("topsecret"));

        const QVariantMap loaded = b.loadRequest(sr);
        const QVariantList vars = loaded.value(QStringLiteral("vars")).toList();
        CHECK(vars.size() == 1);
        const QString id = vars.first().toMap().value(QStringLiteral("secretId")).toString();
        CHECK(!id.isEmpty());
        CHECK(vars.first().toMap().value(QStringLiteral("value")).toString().isEmpty());
        CHECK(b.secretValue(id) == QStringLiteral("topsecret"));

        // loading brings the real value from the keychain (for the user to edit/view)
        const QVariantList resolved = b.withResolvedSecrets(vars);
        CHECK(resolved.first().toMap().value(QStringLiteral("value")).toString()
              == QStringLiteral("topsecret"));

        // re-saving with the resolved value does NOT erase the secret
        CHECK(b.saveRequest(sr, {{QStringLiteral("method"), QStringLiteral("GET")},
                                 {QStringLiteral("url"), QStringLiteral("http://x")},
                                 {QStringLiteral("vars"), resolved}}));
        CHECK(b.secretValue(id) == QStringLiteral("topsecret"));

        // unchecking "secret": writes in plain text and clears the keychain (no orphan secret)
        QVariantList plain = resolved;
        QVariantMap pm = plain.first().toMap();
        pm[QStringLiteral("secret")] = false;
        plain[0] = pm;
        CHECK(b.saveRequest(sr, {{QStringLiteral("method"), QStringLiteral("GET")},
                                 {QStringLiteral("url"), QStringLiteral("http://x")},
                                 {QStringLiteral("vars"), plain}}));
        CHECK(b.secretValue(id).isEmpty());
        {
            QFile f2(b.storageDir() + QStringLiteral("/__secret__/r.json"));
            CHECK(f2.open(QIODevice::ReadOnly));
            const QByteArray raw2 = f2.readAll();
            f2.close();
            CHECK(raw2.contains("topsecret"));   // now in plain text (the user unchecked secret)
        }
        b.deleteEntry(QStringLiteral("__secret__"));
    }

    // ---------------------------------------------------------------- move
    b.deleteEntry(QStringLiteral("__mv__"));
    b.deleteEntry(QStringLiteral("sub"));
    b.createFolder(QStringLiteral("__mv__/sub"));
    b.saveRequest(QStringLiteral("__mv__/sub/r"),
                  {{QStringLiteral("method"), QStringLiteral("GET")}});
    CHECK(b.moveEntry(QStringLiteral("__mv__/sub/r"), QStringLiteral("__mv__")));
    CHECK(b.loadRequest(QStringLiteral("__mv__/r")).value(QStringLiteral("method")).toString() == QStringLiteral("GET"));
    CHECK(b.loadRequest(QStringLiteral("__mv__/sub/r")).isEmpty());              // left the old place
    CHECK(b.moveEntry(QStringLiteral("__mv__/sub"), QString()));                 // folder to root
    CHECK(!b.moveEntry(QStringLiteral("__mv__"), QStringLiteral("__mv__/r")));   // doesn't move into itself
    b.deleteEntry(QStringLiteral("sub"));
    b.deleteEntry(QStringLiteral("__mv__"));

    // ---------------------------------------------------------------- rename/duplicate
    b.deleteEntry(QStringLiteral("__rn__"));
    b.createFolder(QStringLiteral("__rn__"));
    b.saveRequest(QStringLiteral("__rn__/a"), {{QStringLiteral("method"), QStringLiteral("GET")}});
    CHECK(b.renameEntry(QStringLiteral("__rn__/a"), QStringLiteral("b")));
    CHECK(b.loadRequest(QStringLiteral("__rn__/b")).value(QStringLiteral("method")).toString() == QStringLiteral("GET"));
    CHECK(b.loadRequest(QStringLiteral("__rn__/a")).isEmpty());
    CHECK(b.duplicateEntry(QStringLiteral("__rn__/b")));
    CHECK(!b.loadRequest(QStringLiteral("__rn__/b copy")).isEmpty());
    b.deleteEntry(QStringLiteral("__rn__"));

    // ---------------------------------------------------------------- scope when renaming a collection
    // renaming a collection (top-level folder) repoints the "collections" scope of the
    // environment variables that reference it (otherwise the scope becomes orphaned)
    {
        b.deleteEntry(QStringLiteral("__scopeOld__"));
        b.deleteEntry(QStringLiteral("__scopeNew__"));
        CHECK(b.createFolder(QStringLiteral("__scopeOld__")));
        b.deleteEnvironment(QStringLiteral("__e2__"));
        CHECK(b.saveEnvironment(QStringLiteral("__e2__"),
                                {QVariantMap{{QStringLiteral("name"), QStringLiteral("s")},
                                             {QStringLiteral("value"), QStringLiteral("1")},
                                             {QStringLiteral("scope"), QStringLiteral("collections")},
                                             {QStringLiteral("collections"), QStringList{QStringLiteral("__scopeOld__")}}}}));
        b.setActiveEnvironment(QStringLiteral("__e2__"));
        CHECK(effective(b, QStringLiteral("__scopeOld__"), {}).contains(QStringLiteral("s")));
        CHECK(!effective(b, QStringLiteral("__scopeNew__"), {}).contains(QStringLiteral("s")));

        CHECK(b.renameEntry(QStringLiteral("__scopeOld__"), QStringLiteral("__scopeNew__")));
        CHECK(!effective(b, QStringLiteral("__scopeOld__"), {}).contains(QStringLiteral("s")));
        CHECK(effective(b, QStringLiteral("__scopeNew__"), {}).contains(QStringLiteral("s")));

        Backend b4;   // persisted: another instance reads the already-updated scope
        CHECK(effective(b4, QStringLiteral("__scopeNew__"), {}).contains(QStringLiteral("s")));
        b4.deleteEnvironment(QStringLiteral("__e2__"));
        b.deleteEntry(QStringLiteral("__scopeNew__"));
    }

    // ---------------------------------------------------------------- storageDir
    // changing the collections directory persists and another instance sees it
    {
        const QString d2 = tmp.path() + QStringLiteral("/collections2");
        Backend b5;
        b5.setStorageDir(d2);
        CHECK(b5.storageDir() == d2);
        Backend b6;
        CHECK(b6.storageDir() == d2);                                    // persisted
        b6.setStorageDir(tmp.path() + QStringLiteral("/collections"));   // restores
    }

    // ---------------------------------------------------------------- duplicate folder
    {
        b.deleteEntry(QStringLiteral("__dupf__"));
        b.createFolder(QStringLiteral("__dupf__/sub"));
        b.saveRequest(QStringLiteral("__dupf__/sub/r"),
                      {{QStringLiteral("method"), QStringLiteral("POST")}});
        CHECK(b.duplicateEntry(QStringLiteral("__dupf__/sub")));
        CHECK(b.loadRequest(QStringLiteral("__dupf__/sub copy/r"))
                  .value(QStringLiteral("method")).toString() == QStringLiteral("POST"));
        b.deleteEntry(QStringLiteral("__dupf__"));
    }

    // ---------------------------------------------------------------- move (edge cases)
    {
        b.deleteEntry(QStringLiteral("__mv2__"));
        b.createFolder(QStringLiteral("__mv2__/a/b"));
        b.saveRequest(QStringLiteral("__mv2__/a/r"), {{QStringLiteral("method"), QStringLiteral("GET")}});
        CHECK(!b.moveEntry(QStringLiteral("__mv2__/a"), QStringLiteral("__mv2__/a/b"))); // into itself
        b.createFolder(QStringLiteral("__mv2__/c/a"));                                   // collision at destination
        CHECK(!b.moveEntry(QStringLiteral("__mv2__/a"), QStringLiteral("__mv2__/c")));
        b.deleteEntry(QStringLiteral("__mv2__"));
    }

    // ---------------------------------------------------------------- secret that references a variable
    {
        b.deleteEnvironment(QStringLiteral("__eref__"));
        CHECK(b.saveEnvironment(QStringLiteral("__eref__"),
            {QVariantMap{{QStringLiteral("name"), QStringLiteral("base")},
                         {QStringLiteral("value"), QStringLiteral("http://h")}},
             QVariantMap{{QStringLiteral("name"), QStringLiteral("tok")},
                         {QStringLiteral("value"), QStringLiteral("{{base}}/s3cr3t")},
                         {QStringLiteral("secret"), true}}}));
        b.setActiveEnvironment(QStringLiteral("__eref__"));
        const QVariantMap eff3 = effective(b, QStringLiteral("colA"), {});
        CHECK(eff3.value(QStringLiteral("tok")).toString() == QStringLiteral("http://h/s3cr3t"));
        QFile f3(b.storageDir() + QStringLiteral("/.catarina/environments.json"));
        CHECK(f3.open(QIODevice::ReadOnly));
        CHECK(!QString::fromUtf8(f3.readAll()).contains(QStringLiteral("s3cr3t")));   // secret doesn't leak
        f3.close();
        b.deleteEnvironment(QStringLiteral("__eref__"));
    }

    // ---------------------------------------------------------------- history
    b.clearHistory();
    CHECK(b.history().isEmpty());

    // ---------------------------------------------------------------- example collection (seed)
    // self-sufficient: the seed source is injected (a temp fixture), so the test
    // never depends on the project's bundled :/seed contents
    const QString fixture = tmp.path() + QStringLiteral("/seed-fixture");
    QDir().mkpath(fixture + QStringLiteral("/MyCol"));
    {
        const QString reqPath = fixture + QStringLiteral("/MyCol/Get thing.json");
        QFile f(reqPath);
        CHECK(f.open(QIODevice::WriteOnly));
        f.write(QByteArrayLiteral("{\"method\":\"PUT\",\"url\":\"{{base}}/thing\"}"));
        f.close();
        // mimic the read-only resource the real seed is copied from
        QFile::setPermissions(reqPath, QFile::ReadOwner);
    }
    QDir().mkpath(fixture + QStringLiteral("/.catarina"));
    {
        QFile f(fixture + QStringLiteral("/.catarina/environments.json"));
        CHECK(f.open(QIODevice::WriteOnly));
        f.write(QByteArrayLiteral(
            "{\"active\":\"Fake\",\"environments\":[{\"name\":\"Fake\",\"variables\":[]}]}"));
    }

    // created on first use of an empty storage and only once
    {
        const QString d3 = tmp.path() + QStringLiteral("/seed-vazio");
        Backend bSeed;
        bSeed.setStorageDir(d3);
        bSeed.setSeedSource(fixture);
        bSeed.seedDefaultCollection();

        bool hasCol = false, hasReq = false;
        int tops = 0;
        for (const QVariant &v : bSeed.collectionTree()) {
            const QVariantMap m = v.toMap();
            const QString rp = m.value(QStringLiteral("relPath")).toString();
            if (rp == QStringLiteral("MyCol")) hasCol = true;
            if (rp == QStringLiteral("MyCol/Get thing")) hasReq = true;
            if (m.value(QStringLiteral("depth")).toInt() == 0) tops++;
        }
        CHECK(hasCol);
        CHECK(hasReq);
        CHECK(tops == 1);
        // the fixture's request was copied verbatim
        CHECK(bSeed.loadRequest(QStringLiteral("MyCol/Get thing"))
                  .value(QStringLiteral("method")).toString() == QStringLiteral("PUT"));
        // the fixture's environment was loaded
        CHECK(bSeed.environments().size() == 1);
        CHECK(bSeed.activeEnvironment() == QStringLiteral("Fake"));
        // second call doesn't duplicate
        bSeed.seedDefaultCollection();
        int tops2 = 0;
        for (const QVariant &v : bSeed.collectionTree())
            if (v.toMap().value(QStringLiteral("depth")).toInt() == 0)
                tops2++;
        CHECK(tops2 == 1);
        // saving over a seeded request works even though the source was read-only
        CHECK(bSeed.saveRequest(QStringLiteral("MyCol/Get thing"),
                                {{QStringLiteral("method"), QStringLiteral("GET")},
                                 {QStringLiteral("url"), QStringLiteral("editado")}}));
        CHECK(bSeed.loadRequest(QStringLiteral("MyCol/Get thing"))
                  .value(QStringLiteral("url")).toString() == QStringLiteral("editado"));
    }
    // storage with a user collection does NOT receive the seed
    {
        const QString d4 = tmp.path() + QStringLiteral("/seed-existente");
        Backend bSeed2;
        bSeed2.setStorageDir(d4);
        bSeed2.setSeedSource(fixture);
        bSeed2.saveRequest(QStringLiteral("minha"),
                           {{QStringLiteral("method"), QStringLiteral("GET")}});
        bSeed2.seedDefaultCollection();
        CHECK(bSeed2.collectionTree().size() == 1);
    }

    // SecretStore as a DI seam: in-memory implementation, no keychain or file.
    {
        auto mem = SecretStore::createInMemory();
        CHECK(mem->value(QStringLiteral("x")).isEmpty());
        CHECK(mem->save(QStringLiteral("x"), QStringLiteral("s3cr3t")));
        CHECK(mem->value(QStringLiteral("x")) == QStringLiteral("s3cr3t"));
        CHECK(mem->remove(QStringLiteral("x")));
        CHECK(mem->value(QStringLiteral("x")).isEmpty());
        CHECK(!mem->remove(QStringLiteral("x")));   // no longer exists
    }
    {
        Backend bMem;
        bMem.setStorageDir(tmp.path() + QStringLiteral("/mem"));
        bMem.setSecretStore(SecretStore::createInMemory());
        CHECK(bMem.saveSecret(QStringLiteral("id1"), QStringLiteral("v1")));
        CHECK(bMem.secretValue(QStringLiteral("id1")) == QStringLiteral("v1"));
        CHECK(bMem.removeSecret(QStringLiteral("id1")));
        CHECK(bMem.secretValue(QStringLiteral("id1")).isEmpty());
    }

    // querySuffix (preview): same semantics as buildUrl, raw (no percent-encode)
    {
        const QVariantList p{item(QStringLiteral("a"), QStringLiteral("1"))};
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y"), p) == QStringLiteral("?a=1"));
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y?z=0"), p) == QStringLiteral("&a=1"));
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y?"), p) == QStringLiteral("a=1"));
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y"), {item(QStringLiteral("a"), QString())}) == QStringLiteral("?a="));
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y"), {item(QStringLiteral("a"), QStringLiteral("1"), false)}) == QString());
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y"), {item(QString(), QStringLiteral("1"))}) == QString());
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y"),
                                        {item(QStringLiteral("a"), QStringLiteral("1")),
                                         item(QStringLiteral("b"), QStringLiteral("2"))}) == QStringLiteral("?a=1&b=2"));
        CHECK(RequestLogic::querySuffix(QStringLiteral("https://x/y"), {}) == QString());
    }

    // RequestBuilder: same path as send, no network. Request+collection headers,
    // auth (request wins), default Content-Type, body and snapshots.
    {
        const QVariantMap req = {
            {QStringLiteral("method"), QStringLiteral("POST")},
            {QStringLiteral("url"), QStringLiteral("{{base}}/x")},
            {QStringLiteral("headers"), QVariantList{
                QVariantMap{{QStringLiteral("name"), QStringLiteral("X-A")},
                            {QStringLiteral("value"), QStringLiteral("1")},
                            {QStringLiteral("enabled"), true}}}},
            {QStringLiteral("params"), QVariantList{
                QVariantMap{{QStringLiteral("name"), QStringLiteral("q")},
                            {QStringLiteral("value"), QStringLiteral("{{id}}")},
                            {QStringLiteral("enabled"), true}}}},
            {QStringLiteral("body"), QStringLiteral("{\"k\":{{id}}}")},
            {QStringLiteral("bodyType"), QStringLiteral("json")},
            {QStringLiteral("auth"), QVariantMap{{QStringLiteral("type"), QStringLiteral("bearer")},
                                                 {QStringLiteral("token"), QStringLiteral("{{tok}}")}}},
            {QStringLiteral("fields"), QVariantList{}}};
        const QVariantMap vars{{QStringLiteral("base"), QStringLiteral("https://h")},
                               {QStringLiteral("id"), QStringLiteral("7")},
                               {QStringLiteral("tok"), QStringLiteral("Z")}};
        const QVariantList colHeaders{QVariantMap{{QStringLiteral("name"), QStringLiteral("X-Col")},
                                                  {QStringLiteral("value"), QStringLiteral("c")},
                                                  {QStringLiteral("enabled"), true}}};
        const QVariantMap colAuth{{QStringLiteral("type"), QStringLiteral("basic")},
                                  {QStringLiteral("user"), QStringLiteral("u")},
                                  {QStringLiteral("pass"), QStringLiteral("p")}};

        const BuiltRequest b = RequestBuilder::build(req, vars, colHeaders, colAuth, 30, false);
        CHECK(b.valid);
        CHECK(b.url.toString() == QStringLiteral("https://h/x?q=7"));
        CHECK(b.method == QStringLiteral("POST"));
        // request auth ("inherit"-like: here it's explicit bearer) wins over the collection's
        CHECK(QString::fromUtf8(b.req.rawHeader("Authorization")) == QStringLiteral("Bearer Z"));
        CHECK(QString::fromUtf8(b.req.rawHeader("X-A")) == QStringLiteral("1"));
        CHECK(QString::fromUtf8(b.req.rawHeader("X-Col")) == QStringLiteral("c"));
        CHECK(QString::fromUtf8(b.req.rawHeader("Content-Type")) == QStringLiteral("application/json"));
        CHECK(b.payload == QByteArray("{\"k\":7}"));
        CHECK(b.sentBody == QStringLiteral("{\"k\":7}"));
        // invalid URL → !valid (send becomes error "invalidUrl")
        CHECK(!RequestBuilder::build({{QStringLiteral("method"), QStringLiteral("GET")},
                                      {QStringLiteral("url"), QString()}},
                                     {}, {}, {}, 30, false).valid);
    }

    qWarning() << "check_storage: OK";
    return 0;
}
