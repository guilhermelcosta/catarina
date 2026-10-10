// Backend HTTP integration test, no internet: a local QTcpServer returns
// fixed responses and captures the received request. Covers the real send() path
// (QNetworkAccessManager): status, response headers/cookies, indented JSON,
// metadata, network error, cancellation, multipart and failure to open a file.
#include "backend.h"

#include <QtTest>
#include <QDir>
#include <QHostAddress>
#include <QNetworkProxy>
#include <QSettings>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>

namespace {

// Minimal loopback HTTP server: stores the request and returns a fixed response.
class Loopback : public QObject
{
    Q_OBJECT
public:
    explicit Loopback(QObject *parent = nullptr) : QObject(parent)
    {
        connect(&m_server, &QTcpServer::newConnection, this, &Loopback::onConnection);
        QVERIFY(m_server.listen(QHostAddress::LocalHost, 0));   // 0 = free port
    }
    QString url(const QString &path = QStringLiteral("/x")) const
    {
        return QStringLiteral("http://127.0.0.1:%1%2").arg(m_server.serverPort()).arg(path);
    }

    QByteArray requestHeaders;
    QByteArray requestBody;
    QByteArray statusLine = QByteArrayLiteral("HTTP/1.1 200 OK\r\n");
    QList<QByteArray> extraHeaders;
    QByteArray body;
    bool holdOpen = false;          // doesn't respond (to test cancellation)
    bool closeWithoutReply = false; // closes without replying (network error)

private:
    void onConnection()
    {
        QTcpSocket *c = m_server.nextPendingConnection();
        connect(c, &QTcpSocket::readyRead, this, [this, c] { onData(c); });
    }
    void onData(QTcpSocket *c)
    {
        m_buf += c->readAll();
        const int hdrEnd = m_buf.indexOf("\r\n\r\n");
        if (hdrEnd < 0)
            return;   // headers still missing
        if (requestHeaders.isEmpty())
            requestHeaders = m_buf.left(hdrEnd + 4);
        const QByteArray lower = requestHeaders.toLower();
        int cl = 0;
        const int pos = lower.indexOf("content-length:");
        if (pos >= 0) {
            const int eol = lower.indexOf("\r\n", pos);
            cl = lower.mid(pos + 15, eol - pos - 15).trimmed().toInt();
        }
        if (m_buf.size() < hdrEnd + 4 + cl)
            return;   // incomplete body
        requestBody = m_buf.mid(hdrEnd + 4, cl);
        disconnect(c, nullptr, this, nullptr);   // we already have everything
        if (closeWithoutReply) { c->close(); return; }
        if (holdOpen)
            return;
        QByteArray resp = statusLine;
        for (const QByteArray &h : extraHeaders)
            resp += h + "\r\n";
        resp += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
        resp += "Content-Type: application/json\r\n";
        resp += "Connection: close\r\n\r\n";
        resp += body;
        c->write(resp);
        c->flush();
        c->disconnectFromHost();
    }

    QTcpServer m_server;
    QByteArray m_buf;
};

QVariantMap baseRequest(const QString &url, const QString &method = QStringLiteral("GET"),
                        const QString &bodyType = QStringLiteral("none"))
{
    return {{QStringLiteral("method"), method},
            {QStringLiteral("url"), url},
            {QStringLiteral("params"), QVariantList{}},
            {QStringLiteral("headers"), QVariantList{}},
            {QStringLiteral("fields"), QVariantList{}},
            {QStringLiteral("body"), QString()},
            {QStringLiteral("bodyType"), bodyType},
            {QStringLiteral("auth"), QVariantMap{{QStringLiteral("type"), QStringLiteral("none")}}},
            {QStringLiteral("vars"), QVariantList{}}};
}

QVariantMap varItem(const QString &name, const QVariant &value, bool enabled = true)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("value"), value},
            {QStringLiteral("enabled"), enabled}};
}

} // namespace

class CheckHttp : public QObject
{
    Q_OBJECT
private slots:
    void initTestCase()
    {
        m_tmp = new QTemporaryDir;
        QVERIFY(m_tmp->isValid());
        qputenv("XDG_CONFIG_HOME", m_tmp->path().toUtf8());
        qputenv("XDG_DATA_HOME", m_tmp->path().toUtf8());
        qputenv("CATARINA_SECRETS_BACKEND", "file");   // hermetic
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);   // doesn't route localhost
        // point storageDir at the temp dir BEFORE constructing Backend: its ctor
        // mkpaths the storage dir, otherwise it would create the default
        // ~/Documents/catarina on the real home
        {
            QSettings s(QSettings::IniFormat, QSettings::UserScope,
                        QStringLiteral("catarina"), QStringLiteral("catarina"));
            s.setValue(QStringLiteral("storageDir"), m_tmp->path() + QStringLiteral("/collections"));
            s.sync();
        }
        m_backend = new Backend;
    }
    void cleanupTestCase()
    {
        delete m_backend;
        delete m_tmp;
    }

    void response_status_headers_metadata()
    {
        Loopback srv;
        srv.statusLine = QByteArrayLiteral("HTTP/1.1 201 Created\r\n");
        srv.extraHeaders << QByteArrayLiteral("X-Test: 1") << QByteArrayLiteral("Set-Cookie: a=b");
        srv.body = QByteArrayLiteral("{\"k\":1}");

        QSignalSpy ready(m_backend, &Backend::responseReady);
        QSignalSpy meta(m_backend, &Backend::responseMeta);
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(srv.url()), QString());
        QVERIFY2(ready.wait(3000), "no responseReady");
        QCOMPARE(err.count(), 0);

        const QVariantList a = ready.takeFirst();
        QCOMPARE(a.at(0).toInt(), 201);
        QCOMPARE(a.at(1).toString(), QStringLiteral("Created"));
        QVERIFY(a.at(2).toList().size() >= 3);                       // response headers
        QVERIFY(a.at(3).toString().contains(QStringLiteral("\"k\""))); // indented JSON body
        QVERIFY(a.at(5).toInt() > 0);                                 // sizeBytes

        QVERIFY(meta.count() >= 1);   // responseMeta is emitted right after responseReady
        const QVariantMap m = meta.takeFirst().at(0).toMap();
        QCOMPARE(m.value(QStringLiteral("method")).toString(), QStringLiteral("GET"));
        QVERIFY(m.value(QStringLiteral("url")).toString().startsWith(QStringLiteral("http://127.0.0.1")));
        QVERIFY(m.value(QStringLiteral("sizeBytes")).toInt() > 0);
    }

    void headers_and_query_params_sent()
    {
        Loopback srv;
        srv.body = QByteArrayLiteral("ok");
        QVariantMap r = baseRequest(srv.url(QStringLiteral("/y")));
        r[QStringLiteral("params")] = QVariantList{
            QVariantMap{{QStringLiteral("name"), QStringLiteral("q")},
                        {QStringLiteral("value"), QStringLiteral("1")},
                        {QStringLiteral("enabled"), true}}};
        r[QStringLiteral("headers")] = QVariantList{
            QVariantMap{{QStringLiteral("name"), QStringLiteral("X-Custom")},
                        {QStringLiteral("value"), QStringLiteral("42")},
                        {QStringLiteral("enabled"), true}}};
        QSignalSpy ready(m_backend, &Backend::responseReady);
        m_backend->send(r, QString());
        QVERIFY(ready.wait(3000));
        QVERIFY(srv.requestHeaders.contains("GET /y?q=1"));
        QVERIFY(srv.requestHeaders.contains("X-Custom: 42"));
    }

    // {{variables}} in url, params, headers and body are resolved before sending
    void variables_resolved_on_send()
    {
        Loopback srv;
        srv.body = QByteArrayLiteral("ok");
        QVariantMap r = baseRequest(srv.url(QStringLiteral("/{{path}}")), QStringLiteral("POST"),
                                    QStringLiteral("json"));
        r[QStringLiteral("params")] = QVariantList{varItem(QStringLiteral("q"), QStringLiteral("{{id}}"))};
        r[QStringLiteral("headers")] = QVariantList{varItem(QStringLiteral("X-V"), QStringLiteral("{{tok}}"))};
        r[QStringLiteral("body")] = QStringLiteral("{\"k\":\"{{id}}\"}");
        r[QStringLiteral("vars")] = QVariantList{varItem(QStringLiteral("path"), QStringLiteral("users")),
                                                 varItem(QStringLiteral("id"), QStringLiteral("7")),
                                                 varItem(QStringLiteral("tok"), QStringLiteral("abc"))};
        QSignalSpy ready(m_backend, &Backend::responseReady);
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(r, QString());
        QVERIFY2(ready.wait(3000), "no responseReady");
        QCOMPARE(err.count(), 0);
        QVERIFY(srv.requestHeaders.contains("POST /users?q=7"));
        QVERIFY(srv.requestHeaders.contains("X-V: abc"));
        QVERIFY(srv.requestBody.contains("\"k\":\"7\""));
    }

    // headers, auth (inherit) and variables defined on the collection reach the wire
    void collection_values_inherited_on_send()
    {
        Loopback srv;
        srv.body = QByteArrayLiteral("ok");
        const QString col = QStringLiteral("__inh__");
        QVERIFY(m_backend->saveCollectionHeaders(col, QVariantList{
            varItem(QStringLiteral("X-Col"), QStringLiteral("c1"))}));
        QVERIFY(m_backend->saveCollectionAuth(col, QVariantMap{
            {QStringLiteral("type"), QStringLiteral("bearer")},
            {QStringLiteral("token"), QStringLiteral("coltok")}}));
        QVERIFY(m_backend->saveCollectionVariables(col, QVariantList{
            varItem(QStringLiteral("seg"), QStringLiteral("from-col"))}));

        QVariantMap r = baseRequest(srv.url(QStringLiteral("/{{seg}}")));
        r[QStringLiteral("auth")] = QVariantMap{{QStringLiteral("type"), QStringLiteral("inherit")}};
        QSignalSpy ready(m_backend, &Backend::responseReady);
        m_backend->send(r, col);
        QVERIFY2(ready.wait(3000), "no responseReady");
        QVERIFY(srv.requestHeaders.contains("GET /from-col"));          // collection variable resolved
        QVERIFY(srv.requestHeaders.contains("X-Col: c1"));              // collection header
        QVERIFY(srv.requestHeaders.contains("Authorization: Bearer coltok"));   // inherited auth
        m_backend->deleteEntry(col);
    }

    // a request header with the same name as a collection header wins (collection doesn't override)
    void request_header_wins_over_collection()
    {
        Loopback srv;
        srv.body = QByteArrayLiteral("ok");
        const QString col = QStringLiteral("__dup__");
        QVERIFY(m_backend->saveCollectionHeaders(col, QVariantList{
            varItem(QStringLiteral("X-Dup"), QStringLiteral("from-col"))}));
        QVariantMap r = baseRequest(srv.url(QStringLiteral("/d")));
        r[QStringLiteral("headers")] = QVariantList{varItem(QStringLiteral("X-Dup"), QStringLiteral("from-req"))};
        QSignalSpy ready(m_backend, &Backend::responseReady);
        m_backend->send(r, col);
        QVERIFY2(ready.wait(3000), "no responseReady");
        QVERIFY(srv.requestHeaders.contains("X-Dup: from-req"));
        QVERIFY(!srv.requestHeaders.contains("from-col"));
        m_backend->deleteEntry(col);
    }

    // an unresolved variable blocks the send with error("unresolved"), without touching the network
    void unresolved_variable_blocks_send()
    {
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(QStringLiteral("http://127.0.0.1:1/{{missing}}")), QString());
        QCOMPARE(err.count(), 1);
        const QVariantList a = err.takeFirst();
        QCOMPARE(a.at(0).toString(), QStringLiteral("unresolved"));
        QCOMPARE(a.at(1).toList().value(0).toString(), QStringLiteral("missing"));
    }

    void network_error()
    {
        Loopback srv;
        srv.closeWithoutReply = true;
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(srv.url()), QString());
        QVERIFY2(err.wait(3000), "no error");
        QCOMPARE(err.takeFirst().at(0).toString(), QStringLiteral("network"));
    }

    void cancellation()
    {
        Loopback srv;
        srv.holdOpen = true;   // never responds
        QSignalSpy started(m_backend, &Backend::started);
        QSignalSpy canceled(m_backend, &Backend::canceled);
        m_backend->send(baseRequest(srv.url()), QString());
        QCOMPARE(started.count(), 1);   // started is emitted synchronously
        m_backend->cancel();
        QTRY_COMPARE(canceled.count(), 1);
    }

    void multipart_sends_fields()
    {
        Loopback srv;
        srv.body = QByteArrayLiteral("ok");
        QVariantMap r = baseRequest(srv.url(QStringLiteral("/up")), QStringLiteral("POST"),
                                    QStringLiteral("multipart"));
        r[QStringLiteral("fields")] = QVariantList{
            QVariantMap{{QStringLiteral("name"), QStringLiteral("field")},
                        {QStringLiteral("value"), QStringLiteral("value")},
                        {QStringLiteral("type"), QStringLiteral("text")},
                        {QStringLiteral("enabled"), true}}};
        QSignalSpy ready(m_backend, &Backend::responseReady);
        m_backend->send(r, QString());
        QVERIFY(ready.wait(3000));
        QVERIFY(srv.requestHeaders.contains("multipart/form-data"));
        QVERIFY(srv.requestBody.contains("name=\"field\""));
        QVERIFY(srv.requestBody.contains("value"));
    }

    void multipart_missing_file()
    {
        Loopback srv;
        QVariantMap r = baseRequest(srv.url(QStringLiteral("/up")), QStringLiteral("POST"),
                                    QStringLiteral("multipart"));
        r[QStringLiteral("fields")] = QVariantList{
            QVariantMap{{QStringLiteral("name"), QStringLiteral("f")},
                        {QStringLiteral("value"), QString()},
                        {QStringLiteral("type"), QStringLiteral("file")},
                        {QStringLiteral("fileName"), QStringLiteral("/no/such/file")},
                        {QStringLiteral("enabled"), true}}};
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(r, QString());
        QCOMPARE(err.count(), 1);   // fileOpen is synchronous
        QCOMPARE(err.takeFirst().at(0).toString(), QStringLiteral("fileOpen"));
    }

    void invalid_url()
    {
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(QString()), QString());
        QCOMPARE(err.count(), 1);   // invalidUrl is synchronous
        QCOMPARE(err.takeFirst().at(0).toString(), QStringLiteral("invalidUrl"));
    }

private:
    QTemporaryDir *m_tmp = nullptr;
    Backend *m_backend = nullptr;
};

QTEST_GUILESS_MAIN(CheckHttp)
#include "check_http.moc"
