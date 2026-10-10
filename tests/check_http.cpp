// Teste de integração HTTP do Backend, sem internet: um QTcpServer local devolve
// respostas fixas e captura o request recebido. Cobre o caminho real do send()
// (QNetworkAccessManager): status, headers/cookies de resposta, JSON indentado,
// metadados, erro de rede, cancelamento, multipart e falha ao abrir arquivo.
#include "backend.h"

#include <QtTest>
#include <QDir>
#include <QHostAddress>
#include <QNetworkProxy>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>

namespace {

// Servidor HTTP mínimo de loopback: guarda o request e devolve uma resposta fixa.
class Loopback : public QObject
{
    Q_OBJECT
public:
    explicit Loopback(QObject *parent = nullptr) : QObject(parent)
    {
        connect(&m_server, &QTcpServer::newConnection, this, &Loopback::onConnection);
        QVERIFY(m_server.listen(QHostAddress::LocalHost, 0));   // 0 = porta livre
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
    bool holdOpen = false;          // não responde (para testar cancelamento)
    bool closeWithoutReply = false; // fecha sem responder (erro de rede)

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
            return;   // ainda faltam headers
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
            return;   // corpo incompleto
        requestBody = m_buf.mid(hdrEnd + 4, cl);
        disconnect(c, nullptr, this, nullptr);   // já temos tudo
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
        qputenv("CATARINA_SECRETS_BACKEND", "file");   // hermético
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);   // não roteia localhost
        m_backend = new Backend;
        m_backend->setStorageDir(m_tmp->path() + QStringLiteral("/collections"));
    }
    void cleanupTestCase()
    {
        delete m_backend;
        delete m_tmp;
    }

    void resposta_status_headers_metadados()
    {
        Loopback srv;
        srv.statusLine = QByteArrayLiteral("HTTP/1.1 201 Created\r\n");
        srv.extraHeaders << QByteArrayLiteral("X-Test: 1") << QByteArrayLiteral("Set-Cookie: a=b");
        srv.body = QByteArrayLiteral("{\"k\":1}");

        QSignalSpy ready(m_backend, &Backend::responseReady);
        QSignalSpy meta(m_backend, &Backend::responseMeta);
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(srv.url()), QString());
        QVERIFY2(ready.wait(3000), "sem responseReady");
        QCOMPARE(err.count(), 0);

        const QVariantList a = ready.takeFirst();
        QCOMPARE(a.at(0).toInt(), 201);
        QCOMPARE(a.at(1).toString(), QStringLiteral("Created"));
        QVERIFY(a.at(2).toList().size() >= 3);                       // headers de resposta
        QVERIFY(a.at(3).toString().contains(QStringLiteral("\"k\""))); // corpo JSON indentado
        QVERIFY(a.at(5).toInt() > 0);                                 // sizeBytes

        QVERIFY(meta.count() >= 1);   // responseMeta é emitido logo após o responseReady
        const QVariantMap m = meta.takeFirst().at(0).toMap();
        QCOMPARE(m.value(QStringLiteral("method")).toString(), QStringLiteral("GET"));
        QVERIFY(m.value(QStringLiteral("url")).toString().startsWith(QStringLiteral("http://127.0.0.1")));
        QVERIFY(m.value(QStringLiteral("sizeBytes")).toInt() > 0);
    }

    void headers_e_query_params_enviados()
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

    void erro_de_rede()
    {
        Loopback srv;
        srv.closeWithoutReply = true;
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(srv.url()), QString());
        QVERIFY2(err.wait(3000), "sem error");
        QCOMPARE(err.takeFirst().at(0).toString(), QStringLiteral("network"));
    }

    void cancelamento()
    {
        Loopback srv;
        srv.holdOpen = true;   // nunca responde
        QSignalSpy started(m_backend, &Backend::started);
        QSignalSpy canceled(m_backend, &Backend::canceled);
        m_backend->send(baseRequest(srv.url()), QString());
        QCOMPARE(started.count(), 1);   // started é emitido de forma síncrona
        m_backend->cancel();
        QTRY_COMPARE(canceled.count(), 1);
    }

    void multipart_envia_fields()
    {
        Loopback srv;
        srv.body = QByteArrayLiteral("ok");
        QVariantMap r = baseRequest(srv.url(QStringLiteral("/up")), QStringLiteral("POST"),
                                    QStringLiteral("multipart"));
        r[QStringLiteral("fields")] = QVariantList{
            QVariantMap{{QStringLiteral("name"), QStringLiteral("campo")},
                        {QStringLiteral("value"), QStringLiteral("valor")},
                        {QStringLiteral("type"), QStringLiteral("text")},
                        {QStringLiteral("enabled"), true}}};
        QSignalSpy ready(m_backend, &Backend::responseReady);
        m_backend->send(r, QString());
        QVERIFY(ready.wait(3000));
        QVERIFY(srv.requestHeaders.contains("multipart/form-data"));
        QVERIFY(srv.requestBody.contains("name=\"campo\""));
        QVERIFY(srv.requestBody.contains("valor"));
    }

    void multipart_arquivo_inexistente()
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
        QCOMPARE(err.count(), 1);   // fileOpen é síncrono
        QCOMPARE(err.takeFirst().at(0).toString(), QStringLiteral("fileOpen"));
    }

    void url_invalida()
    {
        QSignalSpy err(m_backend, &Backend::error);
        m_backend->send(baseRequest(QString()), QString());
        QCOMPARE(err.count(), 1);   // invalidUrl é síncrono
        QCOMPARE(err.takeFirst().at(0).toString(), QStringLiteral("invalidUrl"));
    }

private:
    QTemporaryDir *m_tmp = nullptr;
    Backend *m_backend = nullptr;
};

QTEST_GUILESS_MAIN(CheckHttp)
#include "check_http.moc"
