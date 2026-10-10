#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// History of sent requests, persisted in a JSON file (newest first,
// cap of 200). It only persists — it knows neither network nor variables.
class HistoryStore : public QObject
{
    Q_OBJECT
public:
    explicit HistoryStore(QObject *parent = nullptr);

    void setFile(const QString &path);
    QVariantList list() const;
    void clear();
    void add(const QVariantMap &entry);

signals:
    void changed();

private:
    QString m_file;
};
