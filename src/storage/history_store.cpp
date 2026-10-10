#include "history_store.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace {
constexpr int kMaxEntries = 200;
constexpr auto kEntriesKey = "entries";
} // namespace

HistoryStore::HistoryStore(QObject *parent)
    : QObject(parent)
{
}

void HistoryStore::setFile(const QString &path)
{
    m_file = path;
}

QVariantList HistoryStore::list() const
{
    QFile f(m_file);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().value(QLatin1String(kEntriesKey))
        .toArray().toVariantList();
}

void HistoryStore::clear()
{
    QSaveFile f(m_file);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(QJsonObject{{QLatin1String(kEntriesKey), QJsonArray{}}}).toJson());
    if (f.commit())
        emit changed();
}

void HistoryStore::add(const QVariantMap &entry)
{
    QJsonArray arr;
    QFile rf(m_file);
    if (rf.open(QIODevice::ReadOnly))
        arr = QJsonDocument::fromJson(rf.readAll()).object().value(QLatin1String(kEntriesKey)).toArray();

    QJsonArray out;
    out.append(QJsonObject::fromVariantMap(entry));
    for (const QJsonValue &v : arr) {
        if (out.size() >= kMaxEntries)
            break;
        out.append(v);
    }

    QSaveFile f(m_file);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(QJsonObject{{QLatin1String(kEntriesKey), out}}).toJson());
    if (f.commit())
        emit changed();
}
