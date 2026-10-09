#include "settings.h"

#include <QDir>
#include <QKeySequence>

Settings::Settings(QObject *parent)
    : QObject(parent)
    , m_s(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("katarina"), QStringLiteral("katarina"))
{
}

QString Settings::defaultStorageDir()
{
    return QDir::homePath() + QStringLiteral("/katarina-collections");
}

QString Settings::storageDir() const
{
    return m_s.value(QStringLiteral("storageDir"), defaultStorageDir()).toString();
}

void Settings::setStorageDir(const QString &dir)
{
    if (dir.isEmpty() || dir == storageDir())
        return;
    m_s.setValue(QStringLiteral("storageDir"), dir);
    emit storageDirChanged();
}

int Settings::fontSize() const { return m_s.value(QStringLiteral("fontSize"), 0).toInt(); }
void Settings::setFontSize(int v) { m_s.setValue(QStringLiteral("fontSize"), v); emit settingsChanged(); }
bool Settings::confirmDelete() const { return m_s.value(QStringLiteral("confirmDelete"), true).toBool(); }
void Settings::setConfirmDelete(bool v) { m_s.setValue(QStringLiteral("confirmDelete"), v); emit settingsChanged(); }
bool Settings::autoSaveOnSend() const { return m_s.value(QStringLiteral("autoSaveOnSend"), false).toBool(); }
void Settings::setAutoSaveOnSend(bool v) { m_s.setValue(QStringLiteral("autoSaveOnSend"), v); emit settingsChanged(); }
int Settings::timeoutSec() const { return m_s.value(QStringLiteral("timeoutSec"), 30).toInt(); }
void Settings::setTimeoutSec(int v) { m_s.setValue(QStringLiteral("timeoutSec"), v); emit settingsChanged(); }
bool Settings::ignoreSsl() const { return m_s.value(QStringLiteral("ignoreSsl"), false).toBool(); }
void Settings::setIgnoreSsl(bool v) { m_s.setValue(QStringLiteral("ignoreSsl"), v); emit settingsChanged(); }

QStringList Settings::openTabs() const
{
    return m_s.value(QStringLiteral("openTabs")).toStringList();
}
int Settings::openTabIndex() const
{
    return m_s.value(QStringLiteral("openTabIndex"), 0).toInt();
}
void Settings::saveSession(const QStringList &paths, int current)
{
    m_s.setValue(QStringLiteral("openTabs"), paths);
    m_s.setValue(QStringLiteral("openTabIndex"), current);
}

QVariantMap Settings::shortcuts() const
{
    return m_s.value(QStringLiteral("shortcuts")).toMap();
}
void Settings::setShortcut(const QString &id, const QString &sequence)
{
    QVariantMap m = shortcuts();
    m.insert(id, sequence);
    m_s.setValue(QStringLiteral("shortcuts"), m);
    emit shortcutsChanged();
}
void Settings::resetShortcut(const QString &id)
{
    QVariantMap m = shortcuts();
    m.remove(id);
    m_s.setValue(QStringLiteral("shortcuts"), m);
    emit shortcutsChanged();
}
QString Settings::keySequence(int key, int modifiers) const
{
    return QKeySequence(key | modifiers).toString(QKeySequence::NativeText);
}
