#include "backend.h"
#include "highlighter.h"
#include "settings.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtLogging>

#include <cstdio>

// The Breeze style (org/kde/breeze/TextArea.qml) does
//   MobileTextActionsToolBar { target: control }
// and the toolbar declares `property TextInput target`. Since `control` is a TextArea
// (QQuickTextEdit), the assignment fails and Qt logs "Unable to assign ... to
// QQuickTextInput" for EVERY TextArea (very noisy). It's benign — that toolbar is only
// used in tabletMode. We filter only that message; everything else passes normally.
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
    // Window/taskbar icon (the placeholder lives in the qrc "appicon").
    // setDesktopFileName makes Wayland match the window to org.catarina.Catarina.desktop.
    app.setDesktopFileName(QStringLiteral("org.catarina.Catarina"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/catarina.svg")));

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
