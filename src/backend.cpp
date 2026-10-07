#include "backend.h"

#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QHttpPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslError>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrlQuery>
#include <QUuid>

namespace {

// Teto de passadas ao resolver {{variavel}} em nome/valor (Backend::variableChain).
// Cada passada reconstrói o mapa nome→valor, então cadeias de referência encadeada
// ({{a}} → valor que referencia {{b}} → ...) se resolvem em ~1 passada por nível.
// Serve também de limite de segurança: referência cíclica ({{a}}↔{{b}}) não converge
// e para aqui em vez de girar para sempre. 10 cobre folgado os níveis usados na UI.
constexpr int kMaxVariableResolvePasses = 10;

const QStringList collectTexts(const QVariantMap &request)
{
    QStringList texts;
    texts << request.value(QStringLiteral("url")).toString();
    texts << request.value(QStringLiteral("body")).toString();
    const QVariantList params = request.value(QStringLiteral("params")).toList();
    for (const QVariant &v : params) {
        const QVariantMap m = v.toMap();
        texts << m.value(QStringLiteral("name")).toString();
        texts << m.value(QStringLiteral("value")).toString();
    }
    const QVariantList headers = request.value(QStringLiteral("headers")).toList();
    for (const QVariant &v : headers) {
        const QVariantMap m = v.toMap();
        texts << m.value(QStringLiteral("name")).toString();
        texts << m.value(QStringLiteral("value")).toString();
    }
    const QVariantList fields = request.value(QStringLiteral("fields")).toList();
    for (const QVariant &v : fields) {
        const QVariantMap m = v.toMap();
        texts << m.value(QStringLiteral("name")).toString();
        texts << m.value(QStringLiteral("value")).toString();
    }
    const QVariantMap auth = request.value(QStringLiteral("auth")).toMap();
    for (const QVariant &v : auth)
        texts << v.toString();
    return texts;
}

} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    m_dir = m_settings.storageDir();
    m_envFile = m_dir + QStringLiteral("/.katarina/environments.json");
    m_appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    m_secretsFile = m_appData + QStringLiteral("/secrets.json");
    QDir().mkpath(m_dir);
    QDir().mkpath(QFileInfo(m_envFile).absolutePath());
    QDir().mkpath(m_appData);
    // pasta de segredos só para o dono (o arquivo já é 0600)
    QFile::setPermissions(m_appData, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    loadEnvironments();
}

QString Backend::storageDir() const { return m_dir; }

void Backend::setStorageDir(const QString &dir)
{
    if (dir.isEmpty() || dir == m_dir)
        return;
    m_settings.setStorageDir(dir);
    m_dir = dir;
    m_envFile = m_dir + QStringLiteral("/.katarina/environments.json");
    m_methodCache.clear();
    m_colVarsCache.clear();
    m_colHeadersCache.clear();
    QDir().mkpath(m_dir);
    QDir().mkpath(QFileInfo(m_envFile).absolutePath());
    loadEnvironments();
    emit collectionsChanged();
    emit environmentsChanged();
}
QString Backend::activeEnvironment() const { return m_activeEnv; }

// ---------------------------------------------------------------- lógica pura

QString Backend::substitute(const QString &text, const QVariantMap &vars)
{
    // Um passe só, aceitando espaços em "{{ nome }}" (mesmo padrão de variableRefs).
    // Nome que não resolve fica literal (não some nem vira vazio).
    static const QRegularExpression re(QStringLiteral("\\{\\{\\s*([^{}]+?)\\s*\\}\\}"));
    QString out;
    out.reserve(text.size());
    int last = 0;
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        out += text.mid(last, m.capturedStart() - last);
        const QString name = m.captured(1);
        out += vars.contains(name) ? vars.value(name).toString() : m.captured(0);
        last = m.capturedEnd();
    }
    out += text.mid(last);
    return out;
}

QVariantList Backend::substituteList(const QVariantList &list, const QVariantMap &vars)
{
    QVariantList out;
    out.reserve(list.size());
    for (const QVariant &v : list) {
        QVariantMap m = v.toMap();
        m[QStringLiteral("name")] = substitute(m.value(QStringLiteral("name")).toString(), vars);
        m[QStringLiteral("value")] = substitute(m.value(QStringLiteral("value")).toString(), vars);
        out.append(m);
    }
    return out;
}

QUrl Backend::buildUrl(const QString &url, const QVariantList &params)
{
    QUrl u(url);
    if (u.scheme().isEmpty())
        u = QUrl(QStringLiteral("http://") + url);
    QUrlQuery query(u);
    for (const QVariant &v : params) {
        const QVariantMap m = v.toMap();
        if (!m.value(QStringLiteral("enabled"), true).toBool())
            continue;
        const QString name = m.value(QStringLiteral("name")).toString();
        if (!name.isEmpty())
            query.addQueryItem(name, m.value(QStringLiteral("value")).toString());
    }
    if (!query.isEmpty())
        u.setQuery(query);
    return u;
}

QVariantMap Backend::authHeader(const QVariantMap &auth)
{
    const QString type = auth.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("bearer") && !auth.value(QStringLiteral("token")).toString().isEmpty())
        return {{QStringLiteral("name"), QStringLiteral("Authorization")},
                {QStringLiteral("value"), QStringLiteral("Bearer ") + auth.value(QStringLiteral("token")).toString()}};
    if (type == QLatin1String("basic")) {
        const QByteArray raw = (auth.value(QStringLiteral("user")).toString() + QLatin1Char(':')
                                + auth.value(QStringLiteral("pass")).toString()).toUtf8();
        return {{QStringLiteral("name"), QStringLiteral("Authorization")},
                {QStringLiteral("value"), QStringLiteral("Basic ") + QString::fromLatin1(raw.toBase64())}};
    }
    if (type == QLatin1String("apikey") && !auth.value(QStringLiteral("key")).toString().isEmpty())
        return {{QStringLiteral("name"), auth.value(QStringLiteral("key")).toString()},
                {QStringLiteral("value"), auth.value(QStringLiteral("value")).toString()}};
    return {};
}

QString Backend::defaultContentType(const QString &bodyType)
{
    if (bodyType == QLatin1String("json"))
        return QStringLiteral("application/json");
    if (bodyType == QLatin1String("urlencoded"))
        return QStringLiteral("application/x-www-form-urlencoded");
    if (bodyType == QLatin1String("text"))
        return QStringLiteral("text/plain");
    return {};
}

QStringList Backend::variableRefs(const QString &text)
{
    static const QRegularExpression re(QStringLiteral("\\{\\{\\s*([^{}]+?)\\s*\\}\\}"));
    QStringList names;
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        const QString n = it.next().captured(1);
        if (!names.contains(n))
            names.append(n);
    }
    return names;
}

QString Backend::encodeForm(const QVariantList &fields)
{
    QUrlQuery q;
    for (const QVariant &v : fields) {
        const QVariantMap m = v.toMap();
        if (!m.value(QStringLiteral("enabled"), true).toBool())
            continue;
        const QString name = m.value(QStringLiteral("name")).toString();
        if (!name.isEmpty())
            q.addQueryItem(name, m.value(QStringLiteral("value")).toString());
    }
    return q.toString(QUrl::FullyEncoded);
}

// ---------------------------------------------------------------- segredos

// secrets.json é lido uma única vez e mantido em memória; save/remove mantêm o cache.
void Backend::ensureSecrets() const
{
    if (m_secretsLoaded)
        return;
    m_secretsLoaded = true;
    QFile f(m_secretsFile);
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it)
        m_secretsCache.insert(it.key(), it.value().toString());
}

bool Backend::writeSecrets() const
{
    QJsonObject obj;
    for (auto it = m_secretsCache.constBegin(); it != m_secretsCache.constEnd(); ++it)
        obj.insert(it.key(), it.value());
    QSaveFile f(m_secretsFile);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument(obj).toJson());
    const bool ok = f.commit();
    QFile::setPermissions(m_secretsFile,
                          QFile::ReadOwner | QFile::WriteOwner);   // 0600
    return ok;
}

QString Backend::secretValue(const QString &id) const
{
    if (id.isEmpty())
        return {};
    ensureSecrets();
    return m_secretsCache.value(id);
}

bool Backend::saveSecret(const QString &id, const QString &value)
{
    if (id.isEmpty())
        return false;
    ensureSecrets();
    m_secretsCache.insert(id, value);
    return writeSecrets();
}

bool Backend::removeSecret(const QString &id)
{
    if (id.isEmpty())
        return false;
    ensureSecrets();
    if (!m_secretsCache.contains(id))
        return false;
    m_secretsCache.remove(id);
    return writeSecrets();
}

QVariantList Backend::withResolvedSecrets(const QVariantList &vars) const
{
    QVariantList out = vars;
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("secret")).toBool()) {
            const QString id = m.value(QStringLiteral("secretId")).toString();
            if (!id.isEmpty())                 // sem id = segredo novo, mantém o que foi digitado
                m[QStringLiteral("value")] = secretValue(id);
        }
        v = m;
    }
    return out;
}

QVariantList Backend::sanitizeSecrets(const QVariantList &vars)
{
    QVariantList out = vars;
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("secret")).toBool()) {
            QString id = m.value(QStringLiteral("secretId")).toString();
            if (id.isEmpty()) {
                id = QUuid::createUuid().toString(QUuid::WithoutBraces);
                m[QStringLiteral("secretId")] = id;
            }
            saveSecret(id, m.value(QStringLiteral("value")).toString());
            m[QStringLiteral("value")] = QString();       // nunca vai pro arquivo
        } else {
            const QString oldId = m.value(QStringLiteral("secretId")).toString();
            if (!oldId.isEmpty()) {
                removeSecret(oldId);                       // deixou de ser segredo: limpa o cofre
                m[QStringLiteral("secretId")] = QString();
            }
        }
        v = m;
    }
    return out;
}

// ---------------------------------------------------------------- histórico

QString Backend::historyPath() const { return m_appData + QStringLiteral("/history.json"); }

QVariantList Backend::history() const
{
    QFile f(historyPath());
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().value(QStringLiteral("entries")).toArray().toVariantList();
}

void Backend::clearHistory()
{
    QSaveFile f(historyPath());
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(QJsonObject{{QStringLiteral("entries"), QJsonArray{}}}).toJson());
    if (f.commit())
        emit historyChanged();
}

void Backend::addHistory(const QVariantMap &entry)
{
    QJsonArray arr;
    QFile rf(historyPath());
    if (rf.open(QIODevice::ReadOnly))
        arr = QJsonDocument::fromJson(rf.readAll()).object().value(QStringLiteral("entries")).toArray();

    QJsonArray out;
    out.append(QJsonObject::fromVariantMap(entry));
    for (const QJsonValue &v : arr) {
        if (out.size() >= 200)
            break;
        out.append(v);
    }

    QSaveFile f(historyPath());
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(QJsonObject{{QStringLiteral("entries"), out}}).toJson());
    if (f.commit())
        emit historyChanged();
}

// ---------------------------------------------------------------- variáveis

// Cadeia única de variáveis (global → coleção → request), já resolvida:
// escopo por variável, segredos e flag enabled. Fonte da verdade para
// variablesState e resolvedVariables.
QList<Backend::ResolvedVar> Backend::variableChain(const QString &collection,
                                                   const QVariantList &requestVars) const
{
    QList<ResolvedVar> chain;
    auto add = [&](const QVariantList &vars, const QString &source, bool global) {
        for (const QVariant &v : vars) {
            const QVariantMap m = v.toMap();
            // nome sempre "aparado": espaços/tabs nas pontas quebram a referência
            // {{nome}} (o substitute captura o nome já sem espaços). Ver check_storage.
            const QString name = m.value(QStringLiteral("name")).toString().trimmed();
            if (name.isEmpty())
                continue;
            if (global) {
                const QString scope = m.value(QStringLiteral("scope"), QStringLiteral("all")).toString();
                if (scope == QLatin1String("collections")) {
                    const QStringList list = m.value(QStringLiteral("collections")).toStringList();
                    if (!collection.isEmpty() && !list.contains(collection))
                        continue;
                }
            }
            const bool secret = m.value(QStringLiteral("secret")).toBool();
            chain.append({name,
                          secret ? secretValue(m.value(QStringLiteral("secretId")).toString())
                                 : m.value(QStringLiteral("value")).toString(),
                          source, secret,
                          m.value(QStringLiteral("enabled"), true).toBool()});
        }
    };

    for (const Env &e : m_envs)
        if (e.name == m_activeEnv)
            add(e.variables, QStringLiteral("global"), true);
    add(collectionVariables(collection), QStringLiteral("coleção"), false);
    add(requestVars, QStringLiteral("request"), false);

    // Uma variável pode ter {{outra}} no nome e/ou no valor, e a referência pode
    // encadear (nome "{{a}}" cujo valor referencia "{{b}}"). Por isso itera até
    // estabilizar: a cada passada o mapa nome→valor é reconstruído com os nomes já
    // resolvidos, então um nome que só existe depois de outra resolução passa a valer.
    // O teto de passadas é kMaxVariableResolvePasses (ver definição).
    QVariantMap vals;
    for (int pass = 0; pass < kMaxVariableResolvePasses; ++pass) {
        vals.clear();
        for (const ResolvedVar &r : chain)
            if (r.enabled)
                vals.insert(r.name, r.value);          // precedência: o último vence
        bool changed = false;
        for (ResolvedVar &r : chain) {
            if (!r.enabled)
                continue;
            const QString nn = substitute(r.name, vals).trimmed();
            const QString nv = substitute(r.value, vals);
            if (nn != r.name) { r.name = nn; changed = true; }
            if (nv != r.value) { r.value = nv; changed = true; }
        }
        if (!changed)
            break;
    }

    return chain;
}

QVariantMap Backend::variablesState(const QVariantMap &request, const QString &collection) const
{
    // uma única passada pela cadeia: resolve a lista, o mapa efetivo e o que falta
    const QList<ResolvedVar> chain =
        variableChain(collection, request.value(QStringLiteral("vars")).toList());

    QMap<QString, QVariantMap> byName;   // melhor precedência por nome
    QVariantMap effective;               // só habilitadas (é o que substitui {{...}})
    for (const ResolvedVar &r : chain) {
        if (r.enabled)
            effective.insert(r.name, r.value);
        if (byName.contains(r.name) && !r.enabled)
            continue;                    // desabilitada não sobrescreve o que já resolve
        byName.insert(r.name, {{QStringLiteral("name"), r.name},
                               {QStringLiteral("value"), r.value},
                               {QStringLiteral("secret"), r.secret},
                               {QStringLiteral("source"), r.source},
                               {QStringLiteral("enabled"), r.enabled}});
    }
    QVariantList resolved;
    for (auto it = byName.constBegin(); it != byName.constEnd(); ++it)
        resolved.append(it.value());

    QStringList missing;
    for (const QString &text : collectTexts(request)) {
        for (const QString &name : variableRefs(text)) {
            if (!effective.contains(name) && !missing.contains(name))
                missing.append(name);
        }
    }

    return {{QStringLiteral("resolved"), resolved},
            {QStringLiteral("missing"), missing},
            {QStringLiteral("effective"), effective}};
}

QVariantList Backend::resolvedVariables(const QString &collection, const QVariantList &requestVars) const
{
    return variablesState({{QStringLiteral("vars"), requestVars}}, collection)
        .value(QStringLiteral("resolved"))
        .toList();
}

QString Backend::variableNoteFor(const QString &name, const QString &collection) const
{
    // Explica por que "name" não resolve: desabilitada, fora de escopo ou inexistente.
    auto note = [&](const QVariantList &vars, bool global, QString *out) {
        for (const QVariant &v : vars) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("name")).toString() != name)
                continue;
            if (!m.value(QStringLiteral("enabled"), true).toBool()) {
                *out = QStringLiteral("desabilitada");
            } else if (global) {
                const QString scope = m.value(QStringLiteral("scope"), QStringLiteral("all")).toString();
                if (scope == QLatin1String("collections")) {
                    const QStringList list = m.value(QStringLiteral("collections")).toStringList();
                    if (!collection.isEmpty() && !list.contains(collection))
                        *out = QStringLiteral("restrita a: ") + list.join(QStringLiteral(", "));
                    else
                        *out = QString();
                } else {
                    *out = QString();
                }
            } else {
                *out = QString();
            }
            return true;
        }
        return false;
    };

    QString out;
    for (const Env &e : m_envs) {
        if (e.name != m_activeEnv)
            continue;
        if (note(e.variables, true, &out))
            return out;
    }
    if (note(collectionVariables(collection), false, &out))
        return out;
    return QStringLiteral("não definida");
}

// ---------------------------------------------------------------- requisição

void Backend::send(const QVariantMap &request, const QString &collection)
{
    const QVariantMap state = variablesState(request, collection);
    const QStringList missing = state.value(QStringLiteral("missing")).toStringList();
    if (!missing.isEmpty()) {
        emit error(QStringLiteral("Variável não resolvida: ") +
                   missing.join(QStringLiteral(", ")));
        return;
    }

    const QVariantMap vars = state.value(QStringLiteral("effective")).toMap();
    const QString method = request.value(QStringLiteral("method")).toString();
    const QString bodyType = request.value(QStringLiteral("bodyType")).toString();
    const QUrl u = buildUrl(substitute(request.value(QStringLiteral("url")).toString(), vars),
                            substituteList(request.value(QStringLiteral("params")).toList(), vars));
    if (!u.isValid() || u.host().isEmpty()) {
        emit error(QStringLiteral("URL inválida"));
        return;
    }

    const bool ignoreSsl = m_settings.ignoreSsl();

    QNetworkRequest req(u);
    req.setTransferTimeout(m_settings.timeoutSec() * 1000);

    bool hasContentType = false;
    for (const QVariant &v : substituteList(request.value(QStringLiteral("headers")).toList(), vars)) {
        const QVariantMap h = v.toMap();
        if (!h.value(QStringLiteral("enabled"), true).toBool())
            continue;
        const QString name = h.value(QStringLiteral("name")).toString();
        if (name.isEmpty())
            continue;
        if (name.compare(QLatin1String("Content-Type"), Qt::CaseInsensitive) == 0)
            hasContentType = true;
        req.setRawHeader(name.toUtf8(), h.value(QStringLiteral("value")).toString().toUtf8());
    }

    // cabeçalhos da coleção: valem para todos os requests dela; o request tem prioridade
    for (const QVariant &v : substituteList(collectionHeaders(collection), vars)) {
        const QVariantMap h = v.toMap();
        if (!h.value(QStringLiteral("enabled"), true).toBool())
            continue;
        const QString name = h.value(QStringLiteral("name")).toString();
        if (name.isEmpty() || !req.rawHeader(name.toUtf8()).isNull())
            continue;
        if (name.compare(QLatin1String("Content-Type"), Qt::CaseInsensitive) == 0)
            hasContentType = true;
        req.setRawHeader(name.toUtf8(), h.value(QStringLiteral("value")).toString().toUtf8());
    }

    QVariantList authList;
    authList.append(request.value(QStringLiteral("auth")).toMap());
    const QVariantMap ah = authHeader(substituteList(authList, vars).value(0).toMap());
    if (!ah.isEmpty())
        req.setRawHeader(ah.value(QStringLiteral("name")).toString().toUtf8(),
                         ah.value(QStringLiteral("value")).toString().toUtf8());

    const QVariantList fields = substituteList(request.value(QStringLiteral("fields")).toList(), vars);
    const QString ct = defaultContentType(bodyType);
    if (!hasContentType && !ct.isEmpty())
        req.setRawHeader("Content-Type", ct.toUtf8());
    if (req.rawHeader("Accept").isEmpty())
        req.setRawHeader("Accept", "application/json");

    QElapsedTimer timer;
    timer.start();
    QNetworkReply *reply = nullptr;

    // snapshot do que foi realmente enviado (para a aba de rede)
    QVariantList sentHeaders;
    for (const QByteArray &name : req.rawHeaderList())
        sentHeaders.append(QVariantMap{{QStringLiteral("name"), QString::fromUtf8(name)},
                                       {QStringLiteral("value"), QString::fromUtf8(req.rawHeader(name))}});
    const QString sentBody = (bodyType == QLatin1String("multipart")) ? QStringLiteral("(multipart)")
                            : (bodyType == QLatin1String("urlencoded")) ? encodeForm(fields)
                            : (bodyType == QLatin1String("none")) ? QString()
                            : substitute(request.value(QStringLiteral("body")).toString(), vars);

    auto attachReply = [this, timer, method, u, ignoreSsl, sentHeaders, sentBody](QNetworkReply *r) {
        if (ignoreSsl)
            connect(r, &QNetworkReply::sslErrors, r,
                    [r](const QList<QSslError> &) { r->ignoreSslErrors(); });
        connect(r, &QNetworkReply::finished, this, [this, r, timer, method, u, sentHeaders, sentBody]() {
            if (r == m_currentReply)
                m_currentReply = nullptr;
            r->deleteLater();
            if (r->error() == QNetworkReply::OperationCanceledError) {
                emit canceled();
                return;
            }
            if (r->attribute(QNetworkRequest::HttpStatusCodeAttribute).isNull()) {
                emit error(r->errorString());
                return;
            }
            const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QString statusText = r->attribute(QNetworkRequest::HttpReasonPhraseAttribute).toString();
            QVariantList respHeaders;
            for (const auto &pair : r->rawHeaderPairs())
                respHeaders.append(QVariantMap{{QStringLiteral("name"), QString::fromUtf8(pair.first)},
                                               {QStringLiteral("value"), QString::fromUtf8(pair.second)}});
            const QByteArray bytes = r->readAll();
            const QJsonDocument doc = QJsonDocument::fromJson(bytes);
            const QString text = doc.isNull() ? QString::fromUtf8(bytes)
                                              : QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
            emit responseReady(status, statusText, respHeaders, text, int(timer.elapsed()), bytes.size());

            // metadados de rede para a aba correspondente
            const bool encrypted = r->attribute(QNetworkRequest::ConnectionEncryptedAttribute).toBool();
            const bool http2 = r->attribute(QNetworkRequest::Http2WasUsedAttribute).toBool();
            emit responseMeta({
                {QStringLiteral("method"), method},
                {QStringLiteral("url"), u.toString()},
                {QStringLiteral("host"), u.host()},
                {QStringLiteral("port"), u.port(u.scheme() == QLatin1String("https") ? 443 : 80)},
                {QStringLiteral("elapsedMs"), int(timer.elapsed())},
                {QStringLiteral("sizeBytes"), bytes.size()},
                {QStringLiteral("encrypted"), encrypted},
                {QStringLiteral("http2"), http2},
                {QStringLiteral("requestHeaders"), sentHeaders},
                {QStringLiteral("requestBody"), sentBody}
            });
            addHistory({{QStringLiteral("method"), method},
                        {QStringLiteral("url"), u.toString()},
                        {QStringLiteral("status"), status},
                        {QStringLiteral("time"), int(timer.elapsed())},
                        {QStringLiteral("ts"), QDateTime::currentSecsSinceEpoch()}});
        });
    };

    if (bodyType == QLatin1String("multipart")) {
        auto *multi = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        for (const QVariant &v : fields) {
            const QVariantMap m = v.toMap();
            if (!m.value(QStringLiteral("enabled"), true).toBool())
                continue;
            const QString name = m.value(QStringLiteral("name")).toString();
            if (name.isEmpty())
                continue;
            QHttpPart part;
            if (m.value(QStringLiteral("type")).toString() == QLatin1String("file")) {
                const QString path = m.value(QStringLiteral("fileName")).toString();
                auto *file = new QFile(path, multi);
                if (!file->open(QIODevice::ReadOnly)) {
                    emit error(QStringLiteral("Não consegui abrir o arquivo: ") + path);
                    multi->deleteLater();
                    return;
                }
                part.setHeader(QNetworkRequest::ContentDispositionHeader,
                               QStringLiteral("form-data; name=\"%1\"; filename=\"%2\"")
                                   .arg(name, QFileInfo(path).fileName()));
                part.setBodyDevice(file);
            } else {
                part.setHeader(QNetworkRequest::ContentDispositionHeader,
                               QStringLiteral("form-data; name=\"%1\"").arg(name));
                part.setBody(m.value(QStringLiteral("value")).toString().toUtf8());
            }
            multi->append(part);
        }
        reply = (method == QLatin1String("PUT")) ? m_nam.put(req, multi) : m_nam.post(req, multi);
        multi->setParent(reply);
    } else {
        QString payload;
        if (bodyType == QLatin1String("urlencoded"))
            payload = encodeForm(fields);
        else if (bodyType != QLatin1String("none"))   // "nenhum" = sem corpo
            payload = substitute(request.value(QStringLiteral("body")).toString(), vars);
        reply = m_nam.sendCustomRequest(req, method.toUtf8(), payload.toUtf8());
    }

    m_currentReply = reply;
    emit started();
    attachReply(reply);
}

void Backend::cancel()
{
    if (m_currentReply)
        m_currentReply->abort();
}

// ---------------------------------------------------------------- coleções

QString Backend::requestPath(const QString &relPath) const
{
    QString safe = relPath;
    safe.replace(QLatin1String(".."), QString());
    while (safe.startsWith(QLatin1Char('/')))
        safe.remove(0, 1);
    return m_dir + QLatin1Char('/') + safe + QStringLiteral(".json");
}

void Backend::walkCollection(const QString &rel, int depth, QVariantList &out) const
{
    const QString abs = m_dir + (rel.isEmpty() ? QString() : QLatin1Char('/') + rel);
    QDir dir(abs);
    for (const QString &sub : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (sub.startsWith(QLatin1Char('.')))   // .katarina e afins ficam fora da árvore
            continue;
        const QString childRel = rel.isEmpty() ? sub : rel + QLatin1Char('/') + sub;
        out.append(QVariantMap{{QStringLiteral("name"), sub},
                               {QStringLiteral("relPath"), childRel},
                               {QStringLiteral("isFolder"), true},
                               {QStringLiteral("depth"), depth}});
        walkCollection(childRel, depth + 1, out);
    }
    for (const QString &file : dir.entryList({QStringLiteral("*.json")}, QDir::Files, QDir::Name)) {
        if (file.startsWith(QLatin1Char('.')))
            continue;
        QString base = file;
        base.chop(5);
        const QString childRel = rel.isEmpty() ? base : rel + QLatin1Char('/') + base;
        // method com cache (mtime): evita reabrir/parsear cada request a cada reload
        const QString absFile = m_dir + QLatin1Char('/') + childRel + QStringLiteral(".json");
        const qint64 mt = QFileInfo(absFile).lastModified().toMSecsSinceEpoch();
        QString method;
        auto it = m_methodCache.constFind(childRel);
        if (it != m_methodCache.constEnd() && it->first == mt) {
            method = it->second;
        } else {
            method = QStringLiteral("GET");
            QFile f(absFile);
            if (f.open(QIODevice::ReadOnly))
                method = QJsonDocument::fromJson(f.readAll()).object().value(QStringLiteral("method")).toString(method);
            m_methodCache.insert(childRel, {mt, method});
        }
        out.append(QVariantMap{{QStringLiteral("name"), base},
                               {QStringLiteral("relPath"), childRel},
                               {QStringLiteral("isFolder"), false},
                               {QStringLiteral("method"), method},
                               {QStringLiteral("depth"), depth}});
    }
}

QVariantList Backend::collectionTree() const
{
    QVariantList out;
    walkCollection(QString(), 0, out);
    // hasChildren em O(n): marca os ancestrais de cada entrada
    QSet<QString> parents;
    for (const QVariant &v : out) {
        QString rp = v.toMap().value(QStringLiteral("relPath")).toString();
        for (int idx = rp.lastIndexOf(QLatin1Char('/')); idx > 0; idx = rp.lastIndexOf(QLatin1Char('/'))) {
            rp.truncate(idx);
            parents.insert(rp);
        }
    }
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("isFolder")).toBool())
            m[QStringLiteral("hasChildren")] = parents.contains(m.value(QStringLiteral("relPath")).toString());
        v = m;
    }
    return out;
}

QVariantMap Backend::loadRequest(const QString &relPath) const
{
    QFile f(requestPath(relPath));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}

bool Backend::isCollection(const QString &relPath) const
{
    if (relPath.isEmpty())
        return false;
    return QFileInfo(m_dir + QLatin1Char('/') + relPath).isDir();
}

bool Backend::saveRequest(const QString &relPath, const QVariantMap &data)
{
    const QString path = requestPath(relPath);
    QDir().mkpath(QFileInfo(path).absolutePath());
    QJsonObject obj = QJsonObject::fromVariantMap(data);
    // segredos das variáveis do request nunca vão pro arquivo
    if (obj.contains(QStringLiteral("vars"))) {
        const QVariantList vars = sanitizeSecrets(obj.value(QStringLiteral("vars")).toArray().toVariantList());
        obj.insert(QStringLiteral("vars"), QJsonArray::fromVariantList(vars));
    }
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    if (!f.commit())
        return false;
    emit collectionsChanged();
    return true;
}

bool Backend::deleteEntry(const QString &relPath)
{
    const QString abs = m_dir + QLatin1Char('/') + relPath;
    QFileInfo info(abs);
    bool ok = false;
    if (info.isDir())
        ok = QDir(abs).removeRecursively();
    else
        ok = QFile::remove(abs) || QFile::remove(abs + QStringLiteral(".json"));
    if (ok)
        emit collectionsChanged();
    return ok;
}

bool Backend::createFolder(const QString &relPath)
{
    const bool ok = QDir().mkpath(m_dir + QLatin1Char('/') + relPath);
    if (ok)
        emit collectionsChanged();
    return ok;
}

static bool copyDirRecursive(const QString &src, const QString &dst)
{
    QDir srcDir(src);
    if (!QDir().mkpath(dst))
        return false;
    for (const QString &f : srcDir.entryList(QDir::Files)) {
        if (!QFile::copy(src + QLatin1Char('/') + f, dst + QLatin1Char('/') + f))
            return false;
    }
    for (const QString &d : srcDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (!copyDirRecursive(src + QLatin1Char('/') + d, dst + QLatin1Char('/') + d))
            return false;
    }
    return true;
}

bool Backend::renameEntry(const QString &relPath, const QString &newName)
{
    if (relPath.isEmpty() || newName.isEmpty())
        return false;
    if (newName.contains(QLatin1Char('/')) || newName.contains(QLatin1Char('\\')))
        return false;
    const QString parent = relPath.section(QLatin1Char('/'), 0, -2);
    const QString to = parent.isEmpty() ? newName : parent + QLatin1Char('/') + newName;
    if (to == relPath)
        return false;

    const QString srcAbs = m_dir + QLatin1Char('/') + relPath;
    const QString dstAbs = m_dir + QLatin1Char('/') + to;
    const bool isDir = QFileInfo(srcAbs).isDir();
    if (QFileInfo::exists(dstAbs) || QFileInfo::exists(dstAbs + QStringLiteral(".json")))
        return false;
    QDir().mkpath(QFileInfo(isDir ? dstAbs : dstAbs + QStringLiteral(".json")).absolutePath());

    const bool ok = isDir ? QDir().rename(srcAbs, dstAbs)
                          : QFile::rename(srcAbs + QStringLiteral(".json"), dstAbs + QStringLiteral(".json"));
    if (ok) {
        // renomear uma coleção (pasta de topo) precisa reapontar o escopo das
        // variáveis de ambiente que a referenciam pelo nome
        if (isDir && !relPath.contains(QLatin1Char('/')))
            renameCollectionScope(relPath, newName);
        emit collectionsChanged();
    }
    return ok;
}

// Troca oldName por newName na lista "collections" das variáveis de ambiente com
// escopo "collections", para o escopo sobreviver ao rename da coleção.
bool Backend::renameCollectionScope(const QString &oldName, const QString &newName)
{
    bool changed = false;
    for (Env &e : m_envs) {
        for (QVariant &v : e.variables) {
            QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("scope")).toString() != QLatin1String("collections"))
                continue;
            QStringList list = m.value(QStringLiteral("collections")).toStringList();
            if (!list.contains(oldName))
                continue;
            for (QString &s : list)
                if (s == oldName)
                    s = newName;
            m.insert(QStringLiteral("collections"), list);
            v = m;
            changed = true;
        }
    }
    if (changed) {
        saveEnvironments();
        emit environmentsChanged();
    }
    return changed;
}

bool Backend::duplicateEntry(const QString &relPath)
{
    if (relPath.isEmpty())
        return false;
    const QString parent = relPath.section(QLatin1Char('/'), 0, -2);
    const QString base = relPath.section(QLatin1Char('/'), -1);
    const QString srcAbs = m_dir + QLatin1Char('/') + relPath;
    const QString parentAbs = parent.isEmpty() ? m_dir : m_dir + QLatin1Char('/') + parent;
    const bool isDir = QFileInfo(srcAbs).isDir();

    QString name = base + QStringLiteral(" copy");
    int n = 2;
    while (QFileInfo::exists(parentAbs + QLatin1Char('/') + name + (isDir ? QString() : QStringLiteral(".json"))))
        name = base + QStringLiteral(" copy ") + QString::number(n++);

    const QString dstAbs = parentAbs + QLatin1Char('/') + name;
    const bool ok = isDir ? copyDirRecursive(srcAbs, dstAbs)
                          : QFile::copy(srcAbs + QStringLiteral(".json"), dstAbs + QStringLiteral(".json"));
    if (ok)
        emit collectionsChanged();
    return ok;
}

bool Backend::moveEntry(const QString &from, const QString &toFolder)
{
    if (from.isEmpty())
        return false;
    if (toFolder == from || toFolder.startsWith(from + QLatin1Char('/')))
        return false;   // não pode mover para dentro de si mesmo

    const QString base = from.section(QLatin1Char('/'), -1);
    const QString dest = (toFolder.isEmpty() ? QString() : toFolder + QLatin1Char('/')) + base;
    if (dest == from)
        return false;

    const QString srcAbs = m_dir + QLatin1Char('/') + from;
    const QString dstAbs = m_dir + QLatin1Char('/') + dest;
    const bool isDir = QFileInfo(srcAbs).isDir();
    if (QFileInfo::exists(dstAbs) || QFileInfo::exists(dstAbs + QStringLiteral(".json")))
        return false;   // já existe no destino

    // cria só o diretório PAI do destino (o destino em si não pode existir)
    QDir().mkpath(QFileInfo(isDir ? dstAbs : dstAbs + QStringLiteral(".json")).absolutePath());

    bool ok = false;
    if (isDir)
        ok = QDir().rename(srcAbs, dstAbs);
    else
        ok = QFile::rename(srcAbs + QStringLiteral(".json"), dstAbs + QStringLiteral(".json"));

    if (ok)
        emit collectionsChanged();
    return ok;
}

// ---------------------------------------------------------------- vars de coleção

// lê um .json (com cache validado por mtime); escrever o arquivo invalida sozinho
QVariantList Backend::cachedJsonList(const QString &path, const QString &key, CachedList &slot) const
{
    const qint64 mt = QFileInfo(path).lastModified().toMSecsSinceEpoch();
    if (slot.mtime == mt)
        return slot.list;
    QVariantList list;
    QFile f(path);
    if (f.open(QIODevice::ReadOnly))
        list = QJsonDocument::fromJson(f.readAll()).object().value(key).toArray().toVariantList();
    slot.mtime = mt;
    slot.list = list;
    return list;
}

QVariantList Backend::collectionVariables(const QString &collection) const
{
    if (collection.isEmpty())
        return {};
    const QString path = m_dir + QLatin1Char('/') + collection + QStringLiteral("/.variables.json");
    return cachedJsonList(path, QStringLiteral("vars"), m_colVarsCache[collection]);
}

bool Backend::saveCollectionVariables(const QString &collection, const QVariantList &vars)
{
    if (collection.isEmpty())
        return false;
    const QString dir = m_dir + QLatin1Char('/') + collection;
    QDir().mkpath(dir);
    const QVariantList sanitized = sanitizeSecrets(vars);
    QSaveFile f(dir + QStringLiteral("/.variables.json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    const QJsonObject obj{{QStringLiteral("vars"), QJsonArray::fromVariantList(sanitized)}};
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    const bool ok = f.commit();
    if (ok) {
        m_colVarsCache[collection].mtime = -1;   // força releitura (mtime pode ter granularidade grossa)
        emit collectionsChanged();
    }
    return ok;
}

QVariantList Backend::collectionHeaders(const QString &collection) const
{
    if (collection.isEmpty())
        return {};
    const QString path = m_dir + QLatin1Char('/') + collection + QStringLiteral("/.headers.json");
    return cachedJsonList(path, QStringLiteral("headers"), m_colHeadersCache[collection]);
}

bool Backend::saveCollectionHeaders(const QString &collection, const QVariantList &headers)
{
    if (collection.isEmpty())
        return false;
    const QString dir = m_dir + QLatin1Char('/') + collection;
    QDir().mkpath(dir);
    QSaveFile f(dir + QStringLiteral("/.headers.json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    const QJsonObject obj{{QStringLiteral("headers"), QJsonArray::fromVariantList(headers)}};
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    const bool ok = f.commit();
    if (ok) {
        m_colHeadersCache[collection].mtime = -1;
        emit collectionsChanged();
    }
    return ok;
}

void Backend::loadEnvironments()
{
    m_envs.clear();
    m_activeEnv.clear();
    QFile f(m_envFile);
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    m_activeEnv = root.value(QStringLiteral("active")).toString();
    for (const QJsonValue &v : root.value(QStringLiteral("environments")).toArray()) {
        const QJsonObject o = v.toObject();
        m_envs.append({o.value(QStringLiteral("name")).toString(),
                       o.value(QStringLiteral("variables")).toArray().toVariantList()});
    }
}

void Backend::saveEnvironments() const
{
    QJsonArray arr;
    for (const Env &e : m_envs)
        arr.append(QJsonObject{{QStringLiteral("name"), e.name},
                               {QStringLiteral("variables"), QJsonArray::fromVariantList(e.variables)}});
    const QJsonObject root{{QStringLiteral("active"), m_activeEnv},
                           {QStringLiteral("environments"), arr}};

    QSaveFile f(m_envFile);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.commit();
}

QVariantList Backend::environments() const
{
    QVariantList out;
    for (const Env &e : m_envs) {
        int count = 0;
        for (const QVariant &v : e.variables)
            if (!v.toMap().value(QStringLiteral("name")).toString().isEmpty())
                ++count;
        out.append(QVariantMap{{QStringLiteral("name"), e.name}, {QStringLiteral("count"), count}});
    }
    return out;
}

QVariantList Backend::environmentVariables(const QString &name) const
{
    for (const Env &e : m_envs)
        if (e.name == name)
            return e.variables;
    return {};
}

bool Backend::saveEnvironment(const QString &name, const QVariantList &variables)
{
    if (name.isEmpty())
        return false;
    const QVariantList sanitized = sanitizeSecrets(variables);
    for (Env &e : m_envs) {
        if (e.name == name) {
            e.variables = sanitized;
            saveEnvironments();
            emit environmentsChanged();
            return true;
        }
    }
    m_envs.append({name, sanitized});
    if (m_activeEnv.isEmpty())
        m_activeEnv = name;
    saveEnvironments();
    emit environmentsChanged();
    return true;
}

bool Backend::deleteEnvironment(const QString &name)
{
    for (int i = 0; i < m_envs.size(); ++i) {
        if (m_envs[i].name == name) {
            m_envs.removeAt(i);
            if (m_activeEnv == name)
                m_activeEnv = m_envs.isEmpty() ? QString() : m_envs.first().name;
            saveEnvironments();
            emit environmentsChanged();
            return true;
        }
    }
    return false;
}

bool Backend::renameEnvironment(const QString &oldName, const QString &newName)
{
    if (oldName.isEmpty() || newName.isEmpty() || oldName == newName)
        return false;
    for (const Env &o : m_envs)
        if (o.name == newName)
            return false;   // já existe
    for (Env &e : m_envs) {
        if (e.name == oldName) {
            e.name = newName;
            if (m_activeEnv == oldName)
                m_activeEnv = newName;
            saveEnvironments();
            emit environmentsChanged();
            return true;
        }
    }
    return false;
}

void Backend::setActiveEnvironment(const QString &name)
{
    // sem early-return: sempre persiste e notifica (a UI pode estar dessincronizada)
    m_activeEnv = name;
    saveEnvironments();
    emit environmentsChanged();
}
