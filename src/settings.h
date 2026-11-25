#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// App preferences, persisted in ~/.config/catarina/catarina.ini
class Settings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString storageDir READ storageDir WRITE setStorageDir NOTIFY storageDirChanged)
    // legacy editor zoom key (read-only; new writes go to editorFontSize)
    Q_PROPERTY(int fontSize READ fontSize NOTIFY settingsChanged)
    Q_PROPERTY(qreal uiScale READ uiScale WRITE setUiScale NOTIFY settingsChanged)
    Q_PROPERTY(QString density READ density WRITE setDensity NOTIFY settingsChanged)
    Q_PROPERTY(QString accentColor READ accentColor WRITE setAccentColor NOTIFY settingsChanged)
    Q_PROPERTY(QString editorFontFamily READ editorFontFamily WRITE setEditorFontFamily NOTIFY settingsChanged)
    Q_PROPERTY(int editorFontSize READ editorFontSize WRITE setEditorFontSize NOTIFY settingsChanged)
    Q_PROPERTY(int editorFontSizeResolved READ editorFontSizeResolved NOTIFY settingsChanged)
    Q_PROPERTY(QString editorFontResolved READ editorFontResolved NOTIFY settingsChanged)
    Q_PROPERTY(bool editorLineNumbers READ editorLineNumbers WRITE setEditorLineNumbers NOTIFY settingsChanged)
    Q_PROPERTY(bool editorWrap READ editorWrap WRITE setEditorWrap NOTIFY settingsChanged)
    Q_PROPERTY(int editorIndent READ editorIndent WRITE setEditorIndent NOTIFY settingsChanged)
    Q_PROPERTY(bool editorBrackets READ editorBrackets WRITE setEditorBrackets NOTIFY settingsChanged)
    // pane layout: 0 means "not set" (internal marker, never shown)
    Q_PROPERTY(qreal sidebarWidth READ sidebarWidth WRITE setSidebarWidth NOTIFY settingsChanged)
    Q_PROPERTY(qreal splitPosition READ splitPosition WRITE setSplitPosition NOTIFY settingsChanged)
    Q_PROPERTY(QString colorScheme READ colorScheme WRITE setScheme NOTIFY colorSchemeChanged)
    Q_PROPERTY(bool confirmDelete READ confirmDelete WRITE setConfirmDelete NOTIFY settingsChanged)
    Q_PROPERTY(bool autoSaveOnSend READ autoSaveOnSend WRITE setAutoSaveOnSend NOTIFY settingsChanged)
    Q_PROPERTY(int timeoutSec READ timeoutSec WRITE setTimeoutSec NOTIFY settingsChanged)
    Q_PROPERTY(bool ignoreSsl READ ignoreSsl WRITE setIgnoreSsl NOTIFY settingsChanged)
    Q_PROPERTY(QVariantMap shortcuts READ shortcuts NOTIFY shortcutsChanged)
    // capture order (newest last): resolves which side of a duplicate owns the key
    Q_PROPERTY(QStringList shortcutsOrder READ shortcutsOrder NOTIFY shortcutsChanged)
    Q_PROPERTY(QStringList openTabs READ openTabs NOTIFY settingsChanged)
    Q_PROPERTY(int openTabIndex READ openTabIndex NOTIFY settingsChanged)

public:
    explicit Settings(QObject *parent = nullptr);

    QString storageDir() const;
    void setStorageDir(const QString &dir);

    int fontSize() const;
    qreal uiScale() const;
    void setUiScale(qreal v);
    QString density() const;
    void setDensity(const QString &density);
    QString accentColor() const;
    void setAccentColor(const QString &color);
    QString editorFontFamily() const;
    void setEditorFontFamily(const QString &family);
    int editorFontSize() const;
    void setEditorFontSize(int v);
    int editorFontSizeResolved() const;
    QString editorFontResolved() const;
    bool editorLineNumbers() const;
    void setEditorLineNumbers(bool v);
    bool editorWrap() const;
    void setEditorWrap(bool v);
    int editorIndent() const;
    void setEditorIndent(int v);
    bool editorBrackets() const;
    void setEditorBrackets(bool v);
    qreal sidebarWidth() const;
    void setSidebarWidth(qreal v);
    qreal splitPosition() const;
    void setSplitPosition(qreal v);
    // "system" (default) | "light" | "dark": hidden key, written by the status-bar toggle
    QString colorScheme() const;
    void setScheme(const QString &scheme);
    bool confirmDelete() const;
    void setConfirmDelete(bool v);
    bool autoSaveOnSend() const;
    void setAutoSaveOnSend(bool v);
    int timeoutSec() const;
    void setTimeoutSec(int v);
    bool ignoreSsl() const;
    void setIgnoreSsl(bool v);

    // session: open tabs (restored on next startup)
    QStringList openTabs() const;
    int openTabIndex() const;
    Q_INVOKABLE void saveSession(const QStringList &paths, int current);

    // shortcuts: only remapped ones are kept (id -> sequence)
    QVariantMap shortcuts() const;
    QStringList shortcutsOrder() const;
    Q_INVOKABLE void setShortcut(const QString &id, const QString &sequence);
    Q_INVOKABLE void resetShortcut(const QString &id);
    Q_INVOKABLE QString keySequence(int key, int modifiers) const;   // for key capture

    static QString defaultStorageDir();

signals:
    void storageDirChanged();
    void settingsChanged();
    void shortcutsChanged();
    void colorSchemeChanged();

private:
    mutable QSettings m_s;
};
