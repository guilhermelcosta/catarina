#include "backend.h"
#include "highlighter.h"
#include "settings.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

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

    return app.exec();
}
