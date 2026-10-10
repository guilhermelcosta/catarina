// tst_app setup: brings up the real backend/settings in temporary directories
// (hermetic) and injects them as context properties, like main.cpp does.
#include <QtQuickTest>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSettings>
#include <QTemporaryDir>

#include "backend.h"
#include "highlighter.h"
#include "settings.h"

class AppSetup : public QObject
{
    Q_OBJECT
public:
    AppSetup()
    {
        m_tmp = new QTemporaryDir;
        qputenv("XDG_CONFIG_HOME", m_tmp->path().toUtf8());
        qputenv("XDG_DATA_HOME", m_tmp->path().toUtf8());
        qputenv("CATARINA_SECRETS_BACKEND", "file");
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
        m_settings = new Settings;
        m_varSupport = new VarSupport;
    }

public slots:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->rootContext()->setContextProperty(QStringLiteral("backend"), m_backend);
        engine->rootContext()->setContextProperty(QStringLiteral("settings"), m_settings);
        engine->rootContext()->setContextProperty(QStringLiteral("varSupport"), m_varSupport);
    }

private:
    QTemporaryDir *m_tmp = nullptr;
    Backend *m_backend = nullptr;
    Settings *m_settings = nullptr;
    VarSupport *m_varSupport = nullptr;
};

QUICK_TEST_MAIN_WITH_SETUP(tst_app, AppSetup)
#include "tst_app.moc"
