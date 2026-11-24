#include "settings.h"

#include <QDir>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QKeySequence>
#include <QRegularExpression>
#include <QStandardPaths>

Settings::Settings(QObject *parent)
    : QObject(parent)
    , m_s(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("catarina"), QStringLiteral("catarina"))
{
}

QString Settings::defaultStorageDir()
{
    QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (documents.isEmpty())
        documents = QDir::homePath() + QStringLiteral("/Documents");
    return documents + QStringLiteral("/catarina");
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

qreal Settings::uiScale() const
{
    const qreal v = m_s.value(QStringLiteral("uiScale"), 1.0).toReal();
    return qBound(1.0, v, 1.5);
}
void Settings::setUiScale(qreal v)
{
    if (v < 1.0) v = 1.0;
    if (v > 1.5) v = 1.5;
    if (qFuzzyCompare(v, uiScale()))
        return;
    m_s.setValue(QStringLiteral("uiScale"), v);
    emit settingsChanged();
}

QString Settings::density() const
{
    const QString d = m_s.value(QStringLiteral("density"), QStringLiteral("comfortable")).toString();
    return d == QStringLiteral("compact") ? d : QStringLiteral("comfortable");
}
void Settings::setDensity(const QString &density)
{
    const QString d = density == QStringLiteral("compact") ? density : QStringLiteral("comfortable");
    if (d == this->density())
        return;
    m_s.setValue(QStringLiteral("density"), d);
    emit settingsChanged();
}

QString Settings::accentColor() const
{
    // strict #rrggbb; anything else means "follow system" (never a partial write)
    static const QRegularExpression re(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    const QString c = m_s.value(QStringLiteral("accentColor"), QString()).toString();
    return re.match(c).hasMatch() ? c.toLower() : QString();
}
void Settings::setAccentColor(const QString &color)
{
    static const QRegularExpression re(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    const QString c = re.match(color).hasMatch() ? color.toLower() : QString();
    if (c == accentColor())
        return;
    m_s.setValue(QStringLiteral("accentColor"), c);
    emit settingsChanged();
}

QString Settings::editorFontFamily() const
{
    return m_s.value(QStringLiteral("editorFontFamily"), QString()).toString();
}
void Settings::setEditorFontFamily(const QString &family)
{
    if (family == editorFontFamily())
        return;
    m_s.setValue(QStringLiteral("editorFontFamily"), family);
    emit settingsChanged();
}

int Settings::editorFontSize() const
{
    return m_s.value(QStringLiteral("editorFontSize"), 0).toInt();
}
void Settings::setEditorFontSize(int v)
{
    if (v != 0 && (v < 6 || v > 28))
        return;
    if (v == editorFontSize())
        return;
    m_s.setValue(QStringLiteral("editorFontSize"), v);
    emit settingsChanged();
}

int Settings::editorFontSizeResolved() const
{
    int size = editorFontSize();
    if (size <= 0)
        size = fontSize();          // legacy key, read-only migration
    if (size <= 0)
        size = QGuiApplication::font().pointSize();
    return qBound(6, size, 28);
}

QString Settings::editorFontResolved() const
{
    const QString family = editorFontFamily();
    if (!family.isEmpty() && QFontDatabase::isFixedPitch(family))
        return family;
    return QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
}

bool Settings::editorLineNumbers() const { return m_s.value(QStringLiteral("editorLineNumbers"), false).toBool(); }
void Settings::setEditorLineNumbers(bool v)
{
    if (v == editorLineNumbers()) return;
    m_s.setValue(QStringLiteral("editorLineNumbers"), v);
    emit settingsChanged();
}
bool Settings::editorWrap() const { return m_s.value(QStringLiteral("editorWrap"), true).toBool(); }
void Settings::setEditorWrap(bool v)
{
    if (v == editorWrap()) return;
    m_s.setValue(QStringLiteral("editorWrap"), v);
    emit settingsChanged();
}
int Settings::editorIndent() const
{
    return m_s.value(QStringLiteral("editorIndent"), 2).toInt() == 4 ? 4 : 2;
}
void Settings::setEditorIndent(int v)
{
    if (v != 2 && v != 4) return;
    if (v == editorIndent()) return;
    m_s.setValue(QStringLiteral("editorIndent"), v);
    emit settingsChanged();
}
bool Settings::editorBrackets() const { return m_s.value(QStringLiteral("editorBrackets"), true).toBool(); }
void Settings::setEditorBrackets(bool v)
{
    if (v == editorBrackets()) return;
    m_s.setValue(QStringLiteral("editorBrackets"), v);
    emit settingsChanged();
}
QString Settings::colorScheme() const
{
    const QString s = m_s.value(QStringLiteral("colorScheme"), QStringLiteral("system")).toString();
    return s == QStringLiteral("light") || s == QStringLiteral("dark") ? s : QStringLiteral("system");
}
void Settings::setScheme(const QString &scheme)
{
    const QString s = (scheme == QStringLiteral("light") || scheme == QStringLiteral("dark"))
                          ? scheme : QStringLiteral("system");
    if (s == colorScheme())
        return;
    m_s.setValue(QStringLiteral("colorScheme"), s);
    emit colorSchemeChanged();
}
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
