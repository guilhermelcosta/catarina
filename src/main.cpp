#include "backend.h"
#include "highlighter.h"
#include "settings.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtLogging>

#include <cstdio>

// O estilo Breeze (org/kde/breeze/TextArea.qml) faz
//   MobileTextActionsToolBar { target: control }
// e a toolbar declara `property TextInput target`. Como `control` é um TextArea
// (QQuickTextEdit), a atribuição falha e o Qt loga "Unable to assign ... to
// QQuickTextInput" para CADA TextArea (bem repetitivo). É benigno — essa toolbar só
// é usada em tabletMode. Filtramos só essa mensagem; todo o resto passa normal.
static QtMessageHandler s_prevHandler = nullptr;
static void catarinaMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (type == QtWarningMsg
        && msg.contains(QLatin1String("Unable to assign"))
        && msg.contains(QLatin1String("QQuickTextInput")))
        return;
    if (s_prevHandler)
        s_prevHandler(type, ctx, msg);
    else {
        const char *lvl = type == QtWarningMsg  ? "warning: "
                        : type == QtCriticalMsg ? "critical: "
                        : type == QtFatalMsg    ? "fatal: "
                        : type == QtInfoMsg     ? "info: " : "debug: ";
        std::fprintf(stderr, "%s%s\n", lvl, qPrintable(msg));
    }
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    s_prevHandler = qInstallMessageHandler(catarinaMessageHandler);
    QCoreApplication::setApplicationName(QStringLiteral("catarina"));
    QCoreApplication::setOrganizationName(QStringLiteral("catarina"));

    Settings settings;

    Backend backend;
    backend.seedDefaultCollection();
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
