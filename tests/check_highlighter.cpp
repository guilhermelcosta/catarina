#include "highlighter.h"

#include <QColor>
#include <QTextBlock>
#include <QTextDocument>
#include <QTextLayout>
#include <QtTest>

// Autochecagem hermética do realce JSON: chave e valor-string precisam sair com cores
// diferentes (antes a chave caía na cor de string e o JSON formatado ficava uniforme).
class CheckHighlighter : public QObject
{
    Q_OBJECT
private:
    static QColor colorAt(const QTextBlock &block, int pos)
    {
        const QList<QTextLayout::FormatRange> ranges = block.layout()->formats();
        for (const QTextLayout::FormatRange &r : ranges)
            if (pos >= r.start && pos < r.start + r.length)
                return r.format.foreground().color();
        return QColor();
    }

private slots:
    void key_differs_from_string_value()
    {
        QTextDocument doc;
        const QColor key("#0000ff"), str("#00ff00"), num("#ffaa00"), kw("#ffaa00");
        VarHighlighter h(&doc, QColor("#ff0000"), true, true, str, num, kw, key);
        doc.setPlainText(QStringLiteral("\"name\": \"value\""));
        h.rehighlight();

        const QTextBlock block = doc.firstBlock();
        QCOMPARE(colorAt(block, 0), key);   // "name" (com aspas) = chave
        QCOMPARE(colorAt(block, 9), str);   // "value" = string
        QVERIFY(colorAt(block, 0) != str);  // a chave não pode ficar com a cor de string
    }

    void number_and_keyword_keep_their_colors()
    {
        QTextDocument doc;
        const QColor key("#0000ff"), str("#00ff00"), num("#ffaa00"), kw("#ff00ff");
        VarHighlighter h(&doc, QColor("#ff0000"), true, true, str, num, kw, key);
        doc.setPlainText(QStringLiteral("\"n\": 12, \"ok\": true"));
        h.rehighlight();

        const QTextBlock block = doc.firstBlock();
        QCOMPARE(colorAt(block, 0), key);    // "n"
        QCOMPARE(colorAt(block, 5), num);    // 12
        QCOMPARE(colorAt(block, 9), key);    // "ok"
        QCOMPARE(colorAt(block, 15), kw);    // true
    }
};

QTEST_MAIN(CheckHighlighter)
#include "check_highlighter.moc"
