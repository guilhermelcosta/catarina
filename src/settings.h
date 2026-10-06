#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// Preferências do app, persistidas em ~/.config/katarina/katarina.ini
class Settings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString storageDir READ storageDir WRITE setStorageDir NOTIFY storageDirChanged)
    Q_PROPERTY(int fontSize READ fontSize WRITE setFontSize NOTIFY settingsChanged)
    Q_PROPERTY(bool confirmDelete READ confirmDelete WRITE setConfirmDelete NOTIFY settingsChanged)
    Q_PROPERTY(bool autoSaveOnSend READ autoSaveOnSend WRITE setAutoSaveOnSend NOTIFY settingsChanged)
    Q_PROPERTY(QString exportFormat READ exportFormat WRITE setExportFormat NOTIFY settingsChanged)
    Q_PROPERTY(int timeoutSec READ timeoutSec WRITE setTimeoutSec NOTIFY settingsChanged)
    Q_PROPERTY(bool ignoreSsl READ ignoreSsl WRITE setIgnoreSsl NOTIFY settingsChanged)
    Q_PROPERTY(QVariantMap shortcuts READ shortcuts NOTIFY shortcutsChanged)
    Q_PROPERTY(QStringList openTabs READ openTabs NOTIFY settingsChanged)
    Q_PROPERTY(int openTabIndex READ openTabIndex NOTIFY settingsChanged)

public:
    explicit Settings(QObject *parent = nullptr);

    QString storageDir() const;
    void setStorageDir(const QString &dir);

    int fontSize() const;
    void setFontSize(int v);
    bool confirmDelete() const;
    void setConfirmDelete(bool v);
    bool autoSaveOnSend() const;
    void setAutoSaveOnSend(bool v);
    QString exportFormat() const;
    void setExportFormat(const QString &v);
    int timeoutSec() const;
    void setTimeoutSec(int v);
    bool ignoreSsl() const;
    void setIgnoreSsl(bool v);

    // sessão: abas abertas (restauradas no próximo startup)
    QStringList openTabs() const;
    int openTabIndex() const;
    Q_INVOKABLE void saveSession(const QStringList &paths, int current);

    // atalhos: só os que foram remapeados ficam guardados (id -> sequência)
    QVariantMap shortcuts() const;
    Q_INVOKABLE void setShortcut(const QString &id, const QString &sequence);
    Q_INVOKABLE void resetShortcut(const QString &id);
    Q_INVOKABLE QString keySequence(int key, int modifiers) const;   // p/ captura de tecla

    static QString defaultStorageDir();

signals:
    void storageDirChanged();
    void settingsChanged();
    void shortcutsChanged();

private:
    void migrateLegacyConfig();
    mutable QSettings m_s;
};
