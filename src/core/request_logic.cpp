#include "request_logic.h"
#include "request_schema.h"

#include <QDateTime>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QUuid>
#include <QVector>

namespace {
namespace RS = RequestSchema;

// same pattern in substitute and variableRefs: accepts spaces in "{{ name }}"
const QRegularExpression &varRefRegex()
{
    static const QRegularExpression re(QStringLiteral("\\{\\{\\s*([^{}]+?)\\s*\\}\\}"));
    return re;
}

// --- dynamic variables: SINGLE source of truth ---------------------------------
// A dynamic variable's name is always "$random" + suffix, built by `dynamicName()`
// so the prefix can't be forgotten when a new one is added. To add one, append a
// line to `dynamicTable()` (suffix, generator).
QString dynamicName(const char *suffix)
{
    QString s = QString::fromLatin1(suffix);
    while (s.startsWith(QLatin1Char('$')))            // tolerate a hand-typed "$"
        s.remove(0, 1);
    if (s.left(6).compare(QLatin1String("random"), Qt::CaseInsensitive) == 0)
        s.remove(0, 6);                               // ...or a hand-typed "random"
    return QStringLiteral("$random") + s;
}

template <typename T, int N>
const T &pickRandom(const T (&arr)[N])
{
    return arr[QRandomGenerator::global()->bounded(N)];
}

QString genUuid() { return QUuid::createUuid().toString(QUuid::WithoutBraces); }
QString genTimestamp() { return QString::number(QDateTime::currentSecsSinceEpoch()); }
QString genIsoTimestamp() { return QDateTime::currentDateTimeUtc().toString(Qt::ISODate); }
// ponytail: 0..1000 range; widen if a collection needs another bound
QString genRandomInt() { return QString::number(QRandomGenerator::global()->bounded(1001)); }
QString genRandomBoolean() { return QRandomGenerator::global()->bounded(2) ? QStringLiteral("true")
                                                                            : QStringLiteral("false"); }
QString genRandomDecimal() { return QString::number(QRandomGenerator::global()->generateDouble() * 1000.0, 'f', 2); }
QString genRandomName()
{
    // ponytail: a small built-in pool; swap for a faker lib if realistic names matter
    static const char *first[] = {"Alice", "Bruno", "Carla", "Diego", "Emma", "Felipe", "Gina",
                                  "Hugo", "Iris", "Jonas", "Karina", "Liam", "Maya", "Nina",
                                  "Oscar", "Paula", "Rita", "Sam", "Tina", "Vera"};
    static const char *last[] = {"Almeida", "Bianchi", "Costa", "Dias", "Esteves", "Ferreira",
                                 "Gomes", "Herrera", "Ibarra", "Jensen", "Klein", "Lima",
                                 "Moraes", "Nakamura", "Oliveira", "Pereira", "Rocha", "Silva",
                                 "Torres", "Vargas"};
    return QString::fromLatin1(pickRandom(first)) + QLatin1Char(' ') + QString::fromLatin1(pickRandom(last));
}

struct DynamicVar {
    const char *suffix;
    QString (*gen)();
};
const QVector<DynamicVar> &dynamicTable()
{
    static const QVector<DynamicVar> table{
        {"Uuid", &genUuid},
        {"Timestamp", &genTimestamp},
        {"IsoTimestamp", &genIsoTimestamp},
        {"Int", &genRandomInt},
        {"Boolean", &genRandomBoolean},
        {"Decimal", &genRandomDecimal},
        {"Name", &genRandomName},
    };
    return table;
}
} // namespace

QString RequestLogic::substitute(const QString &text, const QVariantMap &vars)
{
    QString out;
    out.reserve(text.size());
    int last = 0;
    auto it = varRefRegex().globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        out += text.mid(last, m.capturedStart() - last);
        const QString name = m.captured(1);
        if (vars.contains(name))
            out += vars.value(name).toString();
        else if (isDynamicVariable(name))
            out += dynamicValue(name);
        else
            out += m.captured(0);   // an unknown name stays literal
        last = m.capturedEnd();
    }
    out += text.mid(last);
    return out;
}

bool RequestLogic::isDynamicVariable(const QString &name)
{
    for (const DynamicVar &d : dynamicTable())
        if (name == dynamicName(d.suffix))
            return true;
    return false;
}

QString RequestLogic::dynamicValue(const QString &name)
{
    for (const DynamicVar &d : dynamicTable())
        if (name == dynamicName(d.suffix))
            return d.gen();
    return {};
}

QVariantList RequestLogic::dynamicVariables()
{
    QVariantList out;
    for (const DynamicVar &d : dynamicTable())
        out.append(QVariantMap{{QStringLiteral("name"), dynamicName(d.suffix)},
                               {QStringLiteral("value"), d.gen()}});
    return out;
}

QVariantList RequestLogic::substituteList(const QVariantList &list, const QVariantMap &vars)
{
    QVariantList out;
    out.reserve(list.size());
    for (const QVariant &v : list) {
        QVariantMap m = v.toMap();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (it.value().typeId() == QMetaType::QString)
                it.value() = substitute(it.value().toString(), vars);
        }
        out.append(m);
    }
    return out;
}

QStringList RequestLogic::variableRefs(const QString &text)
{
    QStringList names;
    auto it = varRefRegex().globalMatch(text);
    while (it.hasNext()) {
        const QString n = it.next().captured(1);
        if (!names.contains(n))
            names.append(n);
    }
    return names;
}

QUrl RequestLogic::buildUrl(const QString &url, const QVariantList &params)
{
    QUrl u(url);
    if (u.scheme().isEmpty())
        u = QUrl(QStringLiteral("http://") + url);
    QUrlQuery query(u);
    for (const QVariant &v : params) {
        const QVariantMap m = v.toMap();
        if (!m.value(RS::kEnabled, true).toBool())
            continue;
        const QString name = m.value(RS::kName).toString();
        if (!name.isEmpty())
            query.addQueryItem(name, m.value(RS::kValue).toString());
    }
    if (!query.isEmpty())
        u.setQuery(query);
    return u;
}

QString RequestLogic::querySuffix(const QString &url, const QVariantList &params)
{
    QStringList parts;
    for (const QVariant &v : params) {
        const QVariantMap p = v.toMap();
        if (!p.value(RS::kEnabled, true).toBool())
            continue;
        const QString name = p.value(RS::kName).toString();
        if (name.isEmpty())
            continue;
        parts << name + QLatin1Char('=') + p.value(RS::kValue).toString();
    }
    if (parts.isEmpty())
        return {};
    const bool hasQuery = url.contains(QLatin1Char('?'));
    const QChar last = url.isEmpty() ? QChar() : url.at(url.length() - 1);
    const bool alreadyOpen = (last == QLatin1Char('?') || last == QLatin1Char('&'));
    const QString sep = hasQuery ? (alreadyOpen ? QString() : QStringLiteral("&"))
                                 : QStringLiteral("?");
    return sep + parts.join(QLatin1Char('&'));
}

QString RequestLogic::encodeForm(const QVariantList &fields)
{
    QUrlQuery q;
    for (const QVariant &v : fields) {
        const QVariantMap m = v.toMap();
        if (!m.value(RS::kEnabled, true).toBool())
            continue;
        const QString name = m.value(RS::kName).toString();
        if (!name.isEmpty())
            q.addQueryItem(name, m.value(RS::kValue).toString());
    }
    return q.toString(QUrl::FullyEncoded);
}

QString RequestLogic::defaultContentType(const QString &bodyType)
{
    if (bodyType == RS::kJson)
        return QStringLiteral("application/json");
    if (bodyType == RS::kUrlencoded)
        return QStringLiteral("application/x-www-form-urlencoded");
    if (bodyType == RS::kText)
        return QStringLiteral("text/plain");
    return {};
}

QVariantMap RequestLogic::authHeader(const QVariantMap &auth)
{
    const QString type = auth.value(RS::kType).toString();
    if (type == RS::kBearer && !auth.value(RS::kToken).toString().isEmpty())
        return {{RS::kName, QStringLiteral("Authorization")},
                {RS::kValue, QStringLiteral("Bearer ") + auth.value(RS::kToken).toString()}};
    if (type == RS::kBasic) {
        const QByteArray raw = (auth.value(RS::kUser).toString() + QLatin1Char(':')
                                + auth.value(RS::kPass).toString()).toUtf8();
        return {{RS::kName, QStringLiteral("Authorization")},
                {RS::kValue, QStringLiteral("Basic ") + QString::fromLatin1(raw.toBase64())}};
    }
    if (type == RS::kApiKey && !auth.value(RS::kKey).toString().isEmpty())
        return {{RS::kName, auth.value(RS::kKey).toString()},
                {RS::kValue, auth.value(RS::kValue).toString()}};
    return {};
}

QVariantMap RequestLogic::effectiveAuth(const QVariantMap &requestAuth, const QVariantMap &collectionAuth)
{
    return requestAuth.value(RS::kType).toString() == RS::kInherit
               ? collectionAuth : requestAuth;
}

QVariantMap RequestLogic::requestParts(const QVariantMap &request)
{
    QVariantList headers;
    for (const QVariant &v : request.value(RS::kHeaders).toList()) {
        const QVariantMap h = v.toMap();
        const QString name = h.value(RS::kName).toString();
        if (name.isEmpty() || !h.value(RS::kEnabled, true).toBool())
            continue;
        headers.append(QVariantMap{{RS::kName, name}, {RS::kValue, h.value(RS::kValue).toString()}});
    }
    auto hasContentType = [&headers]() {
        for (const QVariant &v : headers)
            if (RS::isContentType(v.toMap().value(RS::kName).toString()))
                return true;
        return false;
    };

    const QVariantMap ah = authHeader(request.value(RS::kAuth).toMap());
    if (!ah.isEmpty())
        headers.append(ah);

    const QString bodyType = request.value(RS::kBodyType).toString();
    QString body;
    if (bodyType == RS::kUrlencoded)
        body = encodeForm(request.value(RS::kFields).toList());
    else if (bodyType == RS::kJson || bodyType == RS::kText)
        body = request.value(RS::kBody).toString();

    const QString ct = defaultContentType(bodyType);
    if (!body.isEmpty() && !ct.isEmpty() && !hasContentType())
        headers.append(QVariantMap{{RS::kName, RS::kContentType}, {RS::kValue, ct}});

    const bool hasBody = (bodyType == RS::kJson || bodyType == RS::kText
                          || bodyType == RS::kUrlencoded) && !body.isEmpty();
    return {{RS::kMethod, request.value(RS::kMethod)},
            {RS::kUrl, request.value(RS::kUrl)},
            {RS::kHeaders, headers},
            {RS::kBody, hasBody ? body : QString()}};
}
