#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Histórico de requests enviados, persistido num arquivo JSON (mais novos primeiro,
// cap de 200). Só persiste — não conhece rede nem variáveis.
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
