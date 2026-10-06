#include "backend.h"
#include "highlighter.h"
#include "settings.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("katarina"));
    QCoreApplication::setOrganizationName(QStringLiteral("katarina"));

    Settings settings;

    Backend backend;
    VarSupport varSupport;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("varSupport"), &varSupport);
    engine.rootContext()->setContextProperty(QStringLiteral("settings"), &settings);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    // Hook de verificação: KREQ_SHOT=/caminho.png salva um screenshot e sai.
    if (qEnvironmentVariableIsSet("KREQ_SHOT")) {
        if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0))) {
            const QString path = qEnvironmentVariable("KREQ_SHOT");
            if (qEnvironmentVariableIsSet("KREQ_SIZE")) {
                const QStringList wh = qEnvironmentVariable("KREQ_SIZE").split(QLatin1Char('x'));
                if (wh.size() == 2)
                    w->resize(wh[0].toInt(), wh[1].toInt());
            }
            if (qEnvironmentVariableIsSet("KREQ_OPEN")) {
                const QStringList paths =
                    qEnvironmentVariable("KREQ_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
                for (const QString &p : paths)
                    QMetaObject::invokeMethod(w, "openPath", Q_ARG(QVariant, p));
            }
            if (qEnvironmentVariableIsSet("KREQ_DIRTY"))
                QMetaObject::invokeMethod(w, "markDirty");
            QTimer::singleShot(1500, [w, path] {
                w->grabWindow().save(path);
                w->setProperty("forceQuit", true);
                QCoreApplication::quit();
            });
        }
    }

    return app.exec();
}
