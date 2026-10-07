// Autochecagem da lógica do Backend (sem rede).
// Roda com: ctest  (ou ./build/bin/check_storage)
//
// Hermético: usa um diretório temporário para config/coleções/segredos,
// então não toca nos dados reais do usuário.
#include "backend.h"

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
            std::fprintf(stderr, "FALHOU: %s (linha %d)\n", #cond, __LINE__);  \
            std::fflush(stderr);                                               \
            std::abort();                                                      \
        }                                                                      \
    } while (0)

// helpers para montar mapas de variável/param sem poluir o teste
static QVariantMap item(const QString &name, const QVariant &value,
                        bool enabled = true, bool secret = false)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("value"), value},
            {QStringLiteral("enabled"), enabled}, {QStringLiteral("secret"), secret}};
}

int main(int argc, char **argv)
{
    QTemporaryDir tmp;
    CHECK(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", tmp.path().toUtf8());

    QCoreApplication app(argc, argv);

    // aponta as coleções para o temp e persiste via a mesma QSettings do app
    QSettings s(QSettings::IniFormat, QSettings::UserScope,
                QStringLiteral("katarina"), QStringLiteral("katarina"));
    s.setValue(QStringLiteral("storageDir"), tmp.path() + QStringLiteral("/collections"));
    s.sync();

    // ---------------------------------------------------------------- puros
    CHECK(Backend::variableRefs(QStringLiteral("{{a}}/x/{{b}}/{{a}}"))
          == QStringList({QStringLiteral("a"), QStringLiteral("b")}));
    CHECK(Backend::variableRefs(QStringLiteral("{{ a }} {{b}}"))
          == QStringList({QStringLiteral("a"), QStringLiteral("b")}));
    CHECK(Backend::variableRefs(QStringLiteral("sem variaveis")).isEmpty());

    CHECK(Backend::substitute(QStringLiteral("{{base}}/u/{{id}}"),
                              {{QStringLiteral("base"), QStringLiteral("http://x")},
                               {QStringLiteral("id"), 7}})
          == QStringLiteral("http://x/u/7"));
    CHECK(Backend::substitute(QStringLiteral("nada"), {}) == QStringLiteral("nada"));

    CHECK(Backend::defaultContentType(QStringLiteral("json")) == QStringLiteral("application/json"));
    CHECK(Backend::defaultContentType(QStringLiteral("urlencoded"))
          == QStringLiteral("application/x-www-form-urlencoded"));
    CHECK(Backend::defaultContentType(QStringLiteral("text")) == QStringLiteral("text/plain"));
    CHECK(Backend::defaultContentType(QStringLiteral("multipart")).isEmpty());
    CHECK(Backend::defaultContentType(QStringLiteral("none")).isEmpty());

    const QVariantMap bearer{{QStringLiteral("type"), QStringLiteral("bearer")},
                             {QStringLiteral("token"), QStringLiteral("abc")}};
    CHECK(Backend::authHeader(bearer).value(QStringLiteral("value")) == QStringLiteral("Bearer abc"));

    const QVariantMap basic{{QStringLiteral("type"), QStringLiteral("basic")},
                            {QStringLiteral("user"), QStringLiteral("user")},
                            {QStringLiteral("pass"), QStringLiteral("pass")}};
    CHECK(Backend::authHeader(basic).value(QStringLiteral("value")) == QStringLiteral("Basic dXNlcjpwYXNz"));

    const QVariantMap apikey{{QStringLiteral("type"), QStringLiteral("apikey")},
                             {QStringLiteral("key"), QStringLiteral("X-Key")},
                             {QStringLiteral("value"), QStringLiteral("v")}};
    CHECK(Backend::authHeader(apikey).value(QStringLiteral("name")) == QStringLiteral("X-Key"));
    CHECK(Backend::authHeader(apikey).value(QStringLiteral("value")) == QStringLiteral("v"));
    CHECK(Backend::authHeader({{QStringLiteral("type"), QStringLiteral("none")}}).isEmpty());

    // buildUrl: assume http:// quando falta esquema, respeita params desabilitados
    {
        const QUrl u = Backend::buildUrl(QStringLiteral("exemplo.com/api"),
                                         {item(QStringLiteral("page"), QStringLiteral("2"))});
        CHECK(u.scheme() == QStringLiteral("http"));
        CHECK(QUrlQuery(u).queryItemValue(QStringLiteral("page")) == QStringLiteral("2"));
    }
    {
        const QUrl u = Backend::buildUrl(QStringLiteral("https://h/p?a=1"),
                                         {item(QStringLiteral("b"), QStringLiteral("2")),
                                          item(QStringLiteral("ignorado"), QStringLiteral("x"), false)});
        CHECK(u.scheme() == QStringLiteral("https"));
        const QUrlQuery q(u);
        CHECK(q.queryItemValue(QStringLiteral("a")) == QStringLiteral("1"));
        CHECK(q.queryItemValue(QStringLiteral("b")) == QStringLiteral("2"));
        CHECK(!q.hasQueryItem(QStringLiteral("ignorado")));
    }

    CHECK(Backend::encodeForm({item(QStringLiteral("a"), QStringLiteral("1 2")),
                               item(QStringLiteral("b"), QStringLiteral("x"), false)})
          == QStringLiteral("a=1%202"));

    // ---------------------------------------------------------------- ambiente
    Backend b;
    CHECK(!b.storageDir().isEmpty());
    CHECK(b.storageDir().startsWith(tmp.path()));

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
    CHECK(b.saveEnvironment(QStringLiteral("__e1__"), ev));
    b.setActiveEnvironment(QStringLiteral("__e1__"));

    const QVariantMap a = b.effectiveVariables(QStringLiteral("colA"), {});
    CHECK(a.contains(QStringLiteral("pub")) && a.contains(QStringLiteral("priv")));
    CHECK(a.value(QStringLiteral("tok")).toString() == QStringLiteral("s3cr3t")); // veio do cofre

    const QVariantMap c = b.effectiveVariables(QStringLiteral("colB"), {});
    CHECK(!c.contains(QStringLiteral("priv")));                                  // escopo respeitado
    CHECK(c.value(QStringLiteral("tok")).toString() == QStringLiteral("s3cr3t"));

    // o arquivo versionado NÃO pode conter o valor do segredo
    QFile ef(b.storageDir() + QStringLiteral("/.katarina/environments.json"));
    CHECK(ef.open(QIODevice::ReadOnly));
    CHECK(!QString::fromUtf8(ef.readAll()).contains(QStringLiteral("s3cr3t")));
    ef.close();

    // precedência: request > coleção > global
    const QVariantMap over = b.effectiveVariables(
        QStringLiteral("colA"),
        {item(QStringLiteral("pub"), QStringLiteral("req"))});
    CHECK(over.value(QStringLiteral("pub")).toString() == QStringLiteral("req"));

    // variável usada mas inexistente => bloqueia
    const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{pub}}/x/{{nope}}")}};
    CHECK(b.missingVariables(req, QStringLiteral("colA")) == QStringList{QStringLiteral("nope")});

    // nota de escopo (usada pela UI)
    CHECK(b.variableNoteFor(QStringLiteral("pub"), QStringLiteral("colB")).isEmpty());
    CHECK(b.variableNoteFor(QStringLiteral("priv"), QStringLiteral("colB"))
          == QStringLiteral("restrita a: colA"));
    CHECK(b.variableNoteFor(QStringLiteral("nope"), QStringLiteral("colA"))
          == QStringLiteral("não definida"));

    // resolvedVariables: origem de cada variável
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
        }
        CHECK(seenPub && seenTok);
    }

    // missingVariables varre url, body, headers, fields e auth
    {
        const QVariantMap r{{QStringLiteral("url"), QStringLiteral("{{pub}}")},
                            {QStringLiteral("body"), QStringLiteral("{{body_var}}")},
                            {QStringLiteral("headers"), QVariantList{item(QStringLiteral("X"), QStringLiteral("{{hdr}}"))}}};
        CHECK(b.missingVariables(r, QStringLiteral("colA"))
              == QStringList({QStringLiteral("body_var"), QStringLiteral("hdr")}));
    }

    // ambientes: renomear/duplicar/persistir
    CHECK(b.renameEnvironment(QStringLiteral("__e1__"), QStringLiteral("__e1b__")));
    CHECK(b.activeEnvironment() == QStringLiteral("__e1b__"));
    CHECK(!b.renameEnvironment(QStringLiteral("__e1b__"), QStringLiteral("__e1b__")));
    {
        Backend b2;   // recarrega do arquivo
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

    // ---------------------------------------------------------------- coleção
    b.deleteEntry(QStringLiteral("__col__"));
    CHECK(b.saveCollectionVariables(QStringLiteral("__col__"),
                                    {item(QStringLiteral("cv"), QStringLiteral("7"))}));
    CHECK(b.collectionVariables(QStringLiteral("__col__")).size() == 1);
    CHECK(b.saveCollectionHeaders(QStringLiteral("__col__"),
                                  {item(QStringLiteral("X-Test"), QStringLiteral("abc"))}));
    CHECK(b.collectionHeaders(QStringLiteral("__col__")).size() == 1);
    CHECK(b.collectionHeaders(QStringLiteral("__col__")).first().toMap()
              .value(QStringLiteral("value")) == QStringLiteral("abc"));
    b.deleteEntry(QStringLiteral("__col__"));

    // ---------------------------------------------------------------- requests
    const QString rel = QStringLiteral("__check__/req");
    b.deleteEntry(QStringLiteral("__check__"));
    CHECK(b.saveRequest(rel, {{QStringLiteral("method"), QStringLiteral("POST")},
                              {QStringLiteral("url"), QStringLiteral("http://x/y")}}));
    CHECK(b.loadRequest(rel).value(QStringLiteral("method")).toString() == QStringLiteral("POST"));
    CHECK(b.deleteEntry(QStringLiteral("__check__")));
    CHECK(b.loadRequest(rel).isEmpty());

    // segredo do request: valor não vai para o arquivo, secretId sim
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
        CHECK(b.removeSecret(id));
        CHECK(b.secretValue(id).isEmpty());
        b.deleteEntry(QStringLiteral("__secret__"));
    }

    // ---------------------------------------------------------------- mover
    b.deleteEntry(QStringLiteral("__mv__"));
    b.deleteEntry(QStringLiteral("sub"));
    b.createFolder(QStringLiteral("__mv__/sub"));
    b.saveRequest(QStringLiteral("__mv__/sub/r"),
                  {{QStringLiteral("method"), QStringLiteral("GET")}});
    CHECK(b.moveEntry(QStringLiteral("__mv__/sub/r"), QStringLiteral("__mv__")));
    CHECK(b.loadRequest(QStringLiteral("__mv__/r")).value(QStringLiteral("method")).toString() == QStringLiteral("GET"));
    CHECK(b.loadRequest(QStringLiteral("__mv__/sub/r")).isEmpty());              // saiu do lugar antigo
    CHECK(b.moveEntry(QStringLiteral("__mv__/sub"), QString()));                 // pasta pra raiz
    CHECK(!b.moveEntry(QStringLiteral("__mv__"), QStringLiteral("__mv__/r")));   // não move pra dentro de si
    b.deleteEntry(QStringLiteral("sub"));
    b.deleteEntry(QStringLiteral("__mv__"));

    // ---------------------------------------------------------------- renomear/duplicar
    b.deleteEntry(QStringLiteral("__rn__"));
    b.createFolder(QStringLiteral("__rn__"));
    b.saveRequest(QStringLiteral("__rn__/a"), {{QStringLiteral("method"), QStringLiteral("GET")}});
    CHECK(b.renameEntry(QStringLiteral("__rn__/a"), QStringLiteral("b")));
    CHECK(b.loadRequest(QStringLiteral("__rn__/b")).value(QStringLiteral("method")).toString() == QStringLiteral("GET"));
    CHECK(b.loadRequest(QStringLiteral("__rn__/a")).isEmpty());
    CHECK(b.duplicateEntry(QStringLiteral("__rn__/b")));
    CHECK(!b.loadRequest(QStringLiteral("__rn__/b copy")).isEmpty());
    b.deleteEntry(QStringLiteral("__rn__"));

    // ---------------------------------------------------------------- histórico
    b.clearHistory();
    CHECK(b.history().isEmpty());

    qWarning() << "check_storage: OK";
    return 0;
}
