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

// mapa efetivo / lista de faltantes via variablesState (API única de resolução)
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
    qputenv("KATARINA_SECRETS_BACKEND", "file");   // hermético: não toca no cofre do SO

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
    // aceita espaços dentro de {{ nome }} (mesmo padrão de variableRefs)
    CHECK(Backend::substitute(QStringLiteral("{{ base }}/{{id}}"),
                              {{QStringLiteral("base"), QStringLiteral("http://x")},
                               {QStringLiteral("id"), 7}})
          == QStringLiteral("http://x/7"));
    // nome que não existe fica literal, não vira vazio
    CHECK(Backend::substitute(QStringLiteral("{{nao}}"), {{QStringLiteral("x"), QStringLiteral("1")}})
          == QStringLiteral("{{nao}}"));

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

    // substituteList: interpola TODO campo string (o auth usa token/user/pass/key,
    // não só name/value) — regressão do header "Bearer {{token}}"
    {
        const QVariantList sub = Backend::substituteList(
            {QVariantMap{{QStringLiteral("type"), QStringLiteral("bearer")},
                         {QStringLiteral("token"), QStringLiteral("{{tok}}")}}},
            {{QStringLiteral("tok"), QStringLiteral("s3cr3t")}});
        CHECK(sub.value(0).toMap().value(QStringLiteral("token")) == QStringLiteral("s3cr3t"));
        CHECK(Backend::authHeader(sub.value(0).toMap()).value(QStringLiteral("value"))
              == QStringLiteral("Bearer s3cr3t"));
    }

    // effectiveAuth: "inherit" devolve a auth da coleção; qualquer outro tipo, a do request
    {
        const QVariantMap col{{QStringLiteral("type"), QStringLiteral("bearer")},
                              {QStringLiteral("token"), QStringLiteral("col-tok")}};
        const QVariantMap mine{{QStringLiteral("type"), QStringLiteral("basic")},
                               {QStringLiteral("user"), QStringLiteral("u")},
                               {QStringLiteral("pass"), QStringLiteral("p")}};
        CHECK(Backend::effectiveAuth({{QStringLiteral("type"), QStringLiteral("inherit")}}, col)
              == col);
        CHECK(Backend::effectiveAuth(mine, col) == mine);
    }

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

    // requestParts: headers ativos + auth + Content-Type padrão + corpo conforme o tipo
    {
        const QVariantMap r{{QStringLiteral("method"), QStringLiteral("POST")},
                            {QStringLiteral("url"), QStringLiteral("http://x/y")},
                            {QStringLiteral("headers"), QVariantList{item(QStringLiteral("X-A"), QStringLiteral("1"))}},
                            {QStringLiteral("body"), QStringLiteral("{\"a\":1}")},
                            {QStringLiteral("bodyType"), QStringLiteral("json")},
                            {QStringLiteral("auth"), QVariantMap{{QStringLiteral("type"), QStringLiteral("bearer")},
                                                                 {QStringLiteral("token"), QStringLiteral("t")}}}};
        const QVariantMap parts = b.requestParts(r);
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
    CHECK(a.value(QStringLiteral("tok")).toString() == QStringLiteral("s3cr3t")); // veio do cofre
    CHECK(!a.contains(QStringLiteral("des")));                                    // desabilitada não resolve
    CHECK(b.variableNoteFor(QStringLiteral("des"), QStringLiteral("colA"))
              .value(QStringLiteral("code")) == QStringLiteral("disabled"));

    const QVariantMap c = effective(b, QStringLiteral("colB"), {});
    CHECK(!c.contains(QStringLiteral("priv")));                                  // escopo respeitado
    CHECK(c.value(QStringLiteral("tok")).toString() == QStringLiteral("s3cr3t"));

    // o arquivo versionado NÃO pode conter o valor do segredo
    QFile ef(b.storageDir() + QStringLiteral("/.katarina/environments.json"));
    CHECK(ef.open(QIODevice::ReadOnly));
    CHECK(!QString::fromUtf8(ef.readAll()).contains(QStringLiteral("s3cr3t")));
    ef.close();

    // precedência: request > coleção > global
    const QVariantMap over = effective(b, 
        QStringLiteral("colA"),
        {item(QStringLiteral("pub"), QStringLiteral("req"))});
    CHECK(over.value(QStringLiteral("pub")).toString() == QStringLiteral("req"));

    // desabilitada no request não sobrescreve: cai para a global
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

    // variável usada mas inexistente => bloqueia
    const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{pub}}/x/{{nope}}")}};
    CHECK(missing(b, req, QStringLiteral("colA")) == QStringList{QStringLiteral("nope")});

    // nota de escopo (usada pela UI): códigos, não texto
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
            if (m.value(QStringLiteral("name")) == QStringLiteral("des"))
                CHECK(m.value(QStringLiteral("enabled")).toBool() == false);
        }
        CHECK(seenPub && seenTok);
    }

    // nome e valor podem referenciar outra variável: {{pub}} no nome vira o VALOR de pub
    {
        const QVariantMap interp = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("{{pub}}"), QStringLiteral("req2"))});
        CHECK(!interp.contains(QStringLiteral("{{pub}}")));                       // nome resolvido
        CHECK(interp.value(QStringLiteral("1")).toString() == QStringLiteral("req2"));
        CHECK(interp.value(QStringLiteral("pub")).toString() == QStringLiteral("1")); // global intacta

        const QVariantMap valRef = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("alias"), QStringLiteral("{{pub}}!"))});
        CHECK(valRef.value(QStringLiteral("alias")).toString() == QStringLiteral("1!"));

        // encadeado: o nome referencia um nome que só passa a existir após outra
        // resolução. variavel-1=valor 1; {{variavel-1}}=valor 2 (vira "valor 1");
        // {{valor 1}}=valor 3 (vira "valor 2").
        const QVariantMap chainRef = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variavel-1"), QStringLiteral("valor 1")),
             item(QStringLiteral("{{variavel-1}}"), QStringLiteral("valor 2")),
             item(QStringLiteral("{{valor 1}}"), QStringLiteral("valor 3"))});
        CHECK(chainRef.value(QStringLiteral("variavel-1")).toString() == QStringLiteral("valor 1"));
        CHECK(chainRef.value(QStringLiteral("valor 1")).toString() == QStringLiteral("valor 2"));
        CHECK(chainRef.value(QStringLiteral("valor 2")).toString() == QStringLiteral("valor 3"));
    }

    // cadeia longa (5 níveis), como a do app: cada nome referencia o nome já resolvido
    // da anterior
    {
        const QVariantMap c5 = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variavel-1"), QStringLiteral("valor 1")),
             item(QStringLiteral("{{variavel-1}}"), QStringLiteral("valor 2")),
             item(QStringLiteral("{{valor 1}}"), QStringLiteral("novo valor")),
             item(QStringLiteral("{{valor 2}}"), QStringLiteral("teste")),
             item(QStringLiteral("{{novo valor}}"), QStringLiteral("piriri"))});
        CHECK(c5.value(QStringLiteral("variavel-1")).toString() == QStringLiteral("valor 1"));
        CHECK(c5.value(QStringLiteral("valor 1")).toString() == QStringLiteral("valor 2"));
        CHECK(c5.value(QStringLiteral("valor 2")).toString() == QStringLiteral("novo valor"));
        CHECK(c5.value(QStringLiteral("novo valor")).toString() == QStringLiteral("teste"));
        CHECK(c5.value(QStringLiteral("teste")).toString() == QStringLiteral("piriri"));
        CHECK(!c5.contains(QStringLiteral("{{novo valor}}")));

        // mesma cadeia pelo caminho da UI (variablesState -> resolved)
        const QVariantMap req5{
            {QStringLiteral("vars"),
             QVariantList{item(QStringLiteral("variavel-1"), QStringLiteral("valor 1")),
                          item(QStringLiteral("{{variavel-1}}"), QStringLiteral("valor 2")),
                          item(QStringLiteral("{{valor 1}}"), QStringLiteral("novo valor")),
                          item(QStringLiteral("{{valor 2}}"), QStringLiteral("teste")),
                          item(QStringLiteral("{{novo valor}}"), QStringLiteral("piriri"))}}};
        bool seenTeste = false, seenRaw = false;
        for (const QVariant &v : b.variablesState(req5, QStringLiteral("colA"))
                                     .value(QStringLiteral("resolved")).toList()) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("name")) == QStringLiteral("teste")) {
                seenTeste = true;
                CHECK(m.value(QStringLiteral("value")).toString() == QStringLiteral("piriri"));
            }
            if (m.value(QStringLiteral("name")) == QStringLiteral("{{novo valor}}"))
                seenRaw = true;
        }
        CHECK(seenTeste && !seenRaw);
    }

    // reprodução do caso do app: global "teste" + vars simples + {{novo valor}} por último
    {
        b.deleteEnvironment(QStringLiteral("__echain__"));
        CHECK(b.saveEnvironment(QStringLiteral("__echain__"),
            {QVariantMap{{QStringLiteral("name"), QStringLiteral("teste")},
                         {QStringLiteral("value"), QStringLiteral("testevalor")}}}));
        b.setActiveEnvironment(QStringLiteral("__echain__"));
        const QVariantMap ce = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variavel-1"), QStringLiteral("valor 1")),
             item(QStringLiteral("{{variavel-1}}"), QStringLiteral("valor 2")),
             item(QStringLiteral("{{valor 1}}"), QStringLiteral("novo valor")),
             item(QStringLiteral("{{valor 2}}"), QStringLiteral("teste")),
             item(QStringLiteral("teste24"), QStringLiteral("123")),
             item(QStringLiteral("teste343"), QStringLiteral("123")),
             item(QStringLiteral("teste4534"), QStringLiteral("134")),
             item(QStringLiteral("fgdg"), QStringLiteral("2313")),
             item(QStringLiteral("fgd"), QStringLiteral("3232")),
             item(QStringLiteral("{{novo valor}}"), QStringLiteral("apirito"))});
        // "novo valor" (Row4) = "teste" ⇒ {{novo valor}} vira "teste" (sobrepõe a global)
        CHECK(!ce.contains(QStringLiteral("{{novo valor}}")));
        CHECK(ce.value(QStringLiteral("novo valor")).toString() == QStringLiteral("teste"));
        CHECK(ce.value(QStringLiteral("teste")).toString() == QStringLiteral("apirito"));
        b.deleteEnvironment(QStringLiteral("__echain__"));
    }

    // dados reais (arquivo do app): nomes com TAB nas pontas/dentro das chaves não
    // podem quebrar a cadeia — o nome tem que ser aparado antes de virar chave
    {
        const QVariantMap ct = effective(b, 
            QStringLiteral("colA"),
            {item(QStringLiteral("variavel-1"), QStringLiteral("valor 1")),
             item(QStringLiteral("{{variavel-1}}"), QStringLiteral("valor 2")),
             item(QStringLiteral("{{valor 1}}"), QStringLiteral("novo valor")),
             item(QStringLiteral("{{valor 2}}\t"), QStringLiteral("teste")),
             item(QStringLiteral("{{novo valor\t}}\t"), QStringLiteral("apirito"))});
        CHECK(!ct.contains(QStringLiteral("{{novo valor\t}}\t")));
        CHECK(ct.value(QStringLiteral("valor 2")).toString() == QStringLiteral("novo valor"));
        CHECK(ct.value(QStringLiteral("novo valor")).toString() == QStringLiteral("teste"));
        CHECK(ct.value(QStringLiteral("teste")).toString() == QStringLiteral("apirito"));
    }

    // missing varre url, body, headers, fields e auth
    {
        const QVariantMap r{{QStringLiteral("url"), QStringLiteral("{{pub}}")},
                            {QStringLiteral("body"), QStringLiteral("{{body_var}}")},
                            {QStringLiteral("headers"), QVariantList{item(QStringLiteral("X"), QStringLiteral("{{hdr}}"))}}};
        CHECK(missing(b, r, QStringLiteral("colA"))
              == QStringList({QStringLiteral("body_var"), QStringLiteral("hdr")}));
    }

    // variablesState: resolved + missing + effective numa única passada
    {
        const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{pub}}/{{nope}}")},
                              {QStringLiteral("vars"), QVariantList{}}};
        const QVariantMap st = b.variablesState(req, QStringLiteral("colA"));
        CHECK(st.value(QStringLiteral("missing")).toStringList() == QStringList{QStringLiteral("nope")});
        CHECK(st.value(QStringLiteral("effective")).toMap().value(QStringLiteral("pub")).toString()
              == QStringLiteral("1"));
        CHECK(!st.value(QStringLiteral("resolved")).toList().isEmpty());
    }

    // segredos: persistência entre instâncias (cache + arquivo)
    {
        b.saveSecret(QStringLiteral("__sid__"), QStringLiteral("sv"));
        Backend b3;
        CHECK(b3.secretValue(QStringLiteral("__sid__")) == QStringLiteral("sv"));
        CHECK(b3.removeSecret(QStringLiteral("__sid__")));
        CHECK(b3.secretValue(QStringLiteral("__sid__")).isEmpty());
    }

    // collectionTree: hasChildren calculado em O(n)
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
                                    {item(QStringLiteral("cv"), QStringLiteral("7")),
                                     item(QStringLiteral("cvoff"), QStringLiteral("8"), false)}));
    CHECK(b.collectionVariables(QStringLiteral("__col__")).size() == 2);
    {
        const QVariantMap colEff = effective(b, QStringLiteral("__col__"), {});
        CHECK(colEff.value(QStringLiteral("cv")).toString() == QStringLiteral("7"));
        CHECK(!colEff.contains(QStringLiteral("cvoff")));   // desabilitada na coleção não resolve
    }
    CHECK(b.variableNoteFor(QStringLiteral("cvoff"), QStringLiteral("__col__"))
              .value(QStringLiteral("code")) == QStringLiteral("disabled"));
    CHECK(missing(b, {{QStringLiteral("url"), QStringLiteral("{{cvoff}}")}},
                             QStringLiteral("__col__"))
          == QStringList{QStringLiteral("cvoff")});
    // visão geral: variável da coleção em edição mantém origem "collection" (não "request")
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
    // cache invalidado ao salvar de novo (vars e headers)
    CHECK(b.saveCollectionVariables(QStringLiteral("__col__"),
                                    {item(QStringLiteral("cv"), QStringLiteral("9"))}));
    CHECK(b.collectionVariables(QStringLiteral("__col__")).size() == 1);
    CHECK(b.saveCollectionHeaders(QStringLiteral("__col__"),
                                  {item(QStringLiteral("A"), QStringLiteral("1")),
                                   item(QStringLiteral("B"), QStringLiteral("2"))}));
    CHECK(b.collectionHeaders(QStringLiteral("__col__")).size() == 2);
    // auth da coleção: round-trip e cache invalidado ao salvar de novo
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

    // ---------------------------------------------------------------- nomes repetidos no mesmo escopo
    {
        CHECK(b.duplicateVariableName({item(QStringLiteral("a"), QStringLiteral("1")),
                                       item(QStringLiteral("a"), QStringLiteral("2"))})
              == QStringLiteral("a"));
        CHECK(b.duplicateVariableName({item(QStringLiteral("a"), QStringLiteral("1")),
                                       item(QStringLiteral("b"), QStringLiteral("2"))}).isEmpty());
        // nomes são aparados: "a " colide com "a"
        CHECK(b.duplicateVariableName({item(QStringLiteral("a"), QStringLiteral("1")),
                                       item(QStringLiteral("a "), QStringLiteral("2"))})
              == QStringLiteral("a"));
        // recusa salvar com duplicados nos 3 escopos
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
        // mesmo nome em escopos diferentes é permitido (eles se sobrepõem)
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

        // carregar traz o valor real do cofre (para o usuário editar/ver)
        const QVariantList resolved = b.withResolvedSecrets(vars);
        CHECK(resolved.first().toMap().value(QStringLiteral("value")).toString()
              == QStringLiteral("topsecret"));

        // re-salvar com o valor resolvido NÃO apaga o segredo
        CHECK(b.saveRequest(sr, {{QStringLiteral("method"), QStringLiteral("GET")},
                                 {QStringLiteral("url"), QStringLiteral("http://x")},
                                 {QStringLiteral("vars"), resolved}}));
        CHECK(b.secretValue(id) == QStringLiteral("topsecret"));

        // desmarcar "segredo": grava em claro e limpa o cofre (sem segredo órfão)
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
            CHECK(raw2.contains("topsecret"));   // agora em claro (o usuário desmarcou segredo)
        }
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

    // ---------------------------------------------------------------- escopo ao renomear coleção
    // renomear uma coleção (pasta de topo) reaponta o escopo "collections" das
    // variáveis de ambiente que a referenciam (senão o escopo fica órfão)
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

        Backend b4;   // persistiu: outra instância lê o escopo já atualizado
        CHECK(effective(b4, QStringLiteral("__scopeNew__"), {}).contains(QStringLiteral("s")));
        b4.deleteEnvironment(QStringLiteral("__e2__"));
        b.deleteEntry(QStringLiteral("__scopeNew__"));
    }

    // ---------------------------------------------------------------- storageDir
    // trocar o diretório de coleções persiste e outra instância enxerga
    {
        const QString d2 = tmp.path() + QStringLiteral("/collections2");
        Backend b5;
        b5.setStorageDir(d2);
        CHECK(b5.storageDir() == d2);
        Backend b6;
        CHECK(b6.storageDir() == d2);                                    // persistiu
        b6.setStorageDir(tmp.path() + QStringLiteral("/collections"));   // restaura
    }

    // ---------------------------------------------------------------- duplicar pasta
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

    // ---------------------------------------------------------------- mover (casos-limite)
    {
        b.deleteEntry(QStringLiteral("__mv2__"));
        b.createFolder(QStringLiteral("__mv2__/a/b"));
        b.saveRequest(QStringLiteral("__mv2__/a/r"), {{QStringLiteral("method"), QStringLiteral("GET")}});
        CHECK(!b.moveEntry(QStringLiteral("__mv2__/a"), QStringLiteral("__mv2__/a/b"))); // p/ dentro de si
        b.createFolder(QStringLiteral("__mv2__/c/a"));                                   // colisão no destino
        CHECK(!b.moveEntry(QStringLiteral("__mv2__/a"), QStringLiteral("__mv2__/c")));
        b.deleteEntry(QStringLiteral("__mv2__"));
    }

    // ---------------------------------------------------------------- segredo que referencia variável
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
        QFile f3(b.storageDir() + QStringLiteral("/.katarina/environments.json"));
        CHECK(f3.open(QIODevice::ReadOnly));
        CHECK(!QString::fromUtf8(f3.readAll()).contains(QStringLiteral("s3cr3t")));   // segredo não vaza
        f3.close();
        b.deleteEnvironment(QStringLiteral("__eref__"));
    }

    // ---------------------------------------------------------------- histórico
    b.clearHistory();
    CHECK(b.history().isEmpty());

    // ---------------------------------------------------------------- coleção de exemplo (seed)
    // criada no primeiro uso de um storage vazio e só uma vez
    {
        const QString d3 = tmp.path() + QStringLiteral("/seed-vazio");
        Backend bSeed;
        bSeed.setStorageDir(d3);
        bSeed.seedDefaultCollection();
        bool hasDummy = false;
        int tops = 0;
        for (const QVariant &v : bSeed.collectionTree()) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("relPath")).toString() == QStringLiteral("DummyJSON"))
                hasDummy = true;
            if (m.value(QStringLiteral("depth")).toInt() == 0)
                tops++;
        }
        CHECK(hasDummy);
        CHECK(tops == 1);
        // o request semeado veio com URL e método
        const QVariantMap login = bSeed.loadRequest(QStringLiteral("DummyJSON/Login"));
        CHECK(login.value(QStringLiteral("method")).toString() == QStringLiteral("POST"));
        CHECK(login.value(QStringLiteral("url")).toString() == QStringLiteral("{{baseUrl}}/auth/login"));
        // a senha (secret) resolve a partir do cofre semeado
        CHECK(effective(bSeed, QStringLiteral("DummyJSON"),
                        login.value(QStringLiteral("vars")).toList())
                  .value(QStringLiteral("password")).toString() == QStringLiteral("emilyspass"));
        // segunda chamada não duplica
        bSeed.seedDefaultCollection();
        int tops2 = 0;
        for (const QVariant &v : bSeed.collectionTree())
            if (v.toMap().value(QStringLiteral("depth")).toInt() == 0)
                tops2++;
        CHECK(tops2 == 1);
        // salvar por cima de um request semeado (arquivo veio do qrc) deve funcionar
        CHECK(bSeed.saveRequest(QStringLiteral("DummyJSON/List users"),
                                {{QStringLiteral("method"), QStringLiteral("GET")},
                                 {QStringLiteral("url"), QStringLiteral("editado")}}));
        CHECK(bSeed.loadRequest(QStringLiteral("DummyJSON/List users"))
                  .value(QStringLiteral("url")).toString() == QStringLiteral("editado"));
    }
    // storage com coleção do usuário NÃO recebe o seed
    {
        const QString d4 = tmp.path() + QStringLiteral("/seed-existente");
        Backend bSeed2;
        bSeed2.setStorageDir(d4);
        bSeed2.saveRequest(QStringLiteral("minha"),
                           {{QStringLiteral("method"), QStringLiteral("GET")}});
        bSeed2.seedDefaultCollection();
        CHECK(bSeed2.collectionTree().size() == 1);
    }

    qWarning() << "check_storage: OK";
    return 0;
}
