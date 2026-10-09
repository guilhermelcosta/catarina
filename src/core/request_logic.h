#pragma once

#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// Lógica de request pura: substituição de {{variáveis}}, montagem de URL, auth,
// form-encode e as partes efetivas para exportação. Sem I/O, sem rede, sem estado —
// por isso é testável isoladamente (check_storage / gtest).
class RequestLogic
{
public:
    RequestLogic() = delete;

    // Um passe só, aceitando espaços em "{{ nome }}". Nome que não resolve fica
    // literal (não some nem vira vazio).
    static QString substitute(const QString &text, const QVariantMap &vars);
    // Substitui TODO campo string (auth usa token/user/pass/key, fields usam fileName).
    static QVariantList substituteList(const QVariantList &list, const QVariantMap &vars);
    // nomes {{x}} num texto, sem repetição
    static QStringList variableRefs(const QString &text);
    // assume http:// quando falta esquema; pula params desabilitados/sem nome
    static QUrl buildUrl(const QString &url, const QVariantList &params);
    // x-www-form-urlencoded dos fields habilitados
    static QString encodeForm(const QVariantList &fields);
    // Content-Type padrão do bodyType ("" se não houver corpo)
    static QString defaultContentType(const QString &bodyType);
    // header de auth ({} se "none"/vazio); "inherit" NÃO é resolvido aqui
    static QVariantMap authHeader(const QVariantMap &auth);
    // auth efetiva: "inherit" usa a da coleção; qualquer outro tipo usa a do request
    static QVariantMap effectiveAuth(const QVariantMap &requestAuth, const QVariantMap &collectionAuth);
    // partes efetivas de um request (method/url/headers/body) para exportação: aplica
    // auth e Content-Type padrão como no send, sem resolver {{variáveis}}
    static QVariantMap requestParts(const QVariantMap &request);
};
