// Autochecagem da lógica do Backend (sem rede).
// Roda com: ./build/bin/check_storage
#include "backend.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
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

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    // ---- helpers puros ----
    CHECK(Backend::variableRefs(QStringLiteral("{{a}}/x/{{b}}/{{a}}"))
          == QStringList({QStringLiteral("a"), QStringLiteral("b")}));
    CHECK(Backend::substitute(QStringLiteral("{{base}}/u/{{id}}"),
                              {{QStringLiteral("base"), QStringLiteral("http://x")},
                               {QStringLiteral("id"), 7}})
          == QStringLiteral("http://x/u/7"));
    CHECK(Backend::encodeForm({QVariantMap{{QStringLiteral("name"), QStringLiteral("a")},
                                           {QStringLiteral("value"), QStringLiteral("1")},
                                           {QStringLiteral("enabled"), true}},
                               QVariantMap{{QStringLiteral("name"), QStringLiteral("b")},
                                           {QStringLiteral("value"), QStringLiteral("2")},
                                           {QStringLiteral("enabled"), false}}})
          == QStringLiteral("a=1"));
    CHECK(Backend::defaultContentType(QStringLiteral("urlencoded"))
          == QStringLiteral("application/x-www-form-urlencoded"));

    const QVariantMap bearer{{QStringLiteral("type"), QStringLiteral("bearer")},
                             {QStringLiteral("token"), QStringLiteral("abc")}};
    CHECK(Backend::authHeader(bearer).value(QStringLiteral("value")) == QStringLiteral("Bearer abc"));

    const QUrl u = Backend::buildUrl(QStringLiteral("exemplo.com/api"),
                                     {QVariantMap{{QStringLiteral("name"), QStringLiteral("page")},
                                                  {QStringLiteral("value"), QStringLiteral("2")},
                                                  {QStringLiteral("enabled"), true}}});
    CHECK(u.scheme() == QStringLiteral("http"));
    CHECK(QUrlQuery(u).queryItemValue(QStringLiteral("page")) == QStringLiteral("2"));

    // ---- ambientes com escopo + segredo ----
    Backend b;
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
    QFile ef(QDir::homePath() + QStringLiteral("/katarina-collections/.katarina/environments.json"));
    CHECK(ef.open(QIODevice::ReadOnly));
    CHECK(!QString::fromUtf8(ef.readAll()).contains(QStringLiteral("s3cr3t")));

    // precedência: request > global
    const QVariantMap over = b.effectiveVariables(
        QStringLiteral("colA"),
        {QVariantMap{{QStringLiteral("name"), QStringLiteral("pub")},
                     {QStringLiteral("value"), QStringLiteral("req")}}});
    CHECK(over.value(QStringLiteral("pub")).toString() == QStringLiteral("req"));

    // variável usada mas inexistente => bloqueia
    const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{pub}}/x/{{nope}}")}};
    CHECK(b.missingVariables(req, QStringLiteral("colA")) == QStringList{QStringLiteral("nope")});

    // ---- vars de coleção ----
    b.saveCollectionVariables(QStringLiteral("__col__"),
                              {QVariantMap{{QStringLiteral("name"), QStringLiteral("cv")},
                                           {QStringLiteral("value"), QStringLiteral("7")}}});
    CHECK(b.collectionVariables(QStringLiteral("__col__")).size() == 1);
    b.deleteEntry(QStringLiteral("__col__"));

    // ---- collections: round-trip ----
    const QString rel = QStringLiteral("__check__/req");
    b.deleteEntry(QStringLiteral("__check__"));
    CHECK(b.saveRequest(rel, {{QStringLiteral("method"), QStringLiteral("POST")},
                              {QStringLiteral("url"), QStringLiteral("http://x/y")}}));
    CHECK(b.loadRequest(rel).value(QStringLiteral("method")).toString() == QStringLiteral("POST"));
    b.deleteEntry(QStringLiteral("__check__"));

    // ---- mover (drag & drop) ----
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

    // ---- renomear / duplicar ----
    b.deleteEntry(QStringLiteral("__rn__"));
    b.createFolder(QStringLiteral("__rn__"));
    b.saveRequest(QStringLiteral("__rn__/a"), {{QStringLiteral("method"), QStringLiteral("GET")}});
    CHECK(b.renameEntry(QStringLiteral("__rn__/a"), QStringLiteral("b")));
    CHECK(b.loadRequest(QStringLiteral("__rn__/b")).value(QStringLiteral("method")).toString() == QStringLiteral("GET"));
    CHECK(b.loadRequest(QStringLiteral("__rn__/a")).isEmpty());
    CHECK(b.duplicateEntry(QStringLiteral("__rn__/b")));
    CHECK(!b.loadRequest(QStringLiteral("__rn__/b copy")).isEmpty());
    b.deleteEntry(QStringLiteral("__rn__"));

    b.deleteEnvironment(QStringLiteral("__e1__"));
    qWarning() << "check_storage: OK";
    return 0;
}
