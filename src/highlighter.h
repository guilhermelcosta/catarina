#pragma once

#include <QColor>
#include <QObject>
#include <QRegularExpression>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>

// Colore {{variavel}} (e, opcionalmente, tokens JSON) num editor.
class VarHighlighter : public QSyntaxHighlighter
{
    Q_OBJECT
public:
    VarHighlighter(QTextDocument *doc, const QColor &varColor, bool bold, bool json,
                   const QColor &strColor = QColor(), const QColor &numColor = QColor(),
                   const QColor &kwColor = QColor());

protected:
    void highlightBlock(const QString &text) override;

private:
    QRegularExpression m_var, m_str, m_num, m_kw;
    QTextCharFormat m_varFmt, m_strFmt, m_numFmt, m_kwFmt;
    bool m_json;
};

class VarSupport : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;

    // anexa um highlighter ao QQuickTextDocument de um editor (TextArea);
    // as cores de string/número/palavra-chave do JSON vêm do tema (opcionais)
    Q_INVOKABLE void attach(QObject *textDocument, const QColor &color, bool bold = true,
                            bool json = false, const QColor &strColor = QColor(),
                            const QColor &numColor = QColor(), const QColor &kwColor = QColor()) const;

    // clipboard
    Q_INVOKABLE void copyText(const QString &text) const;
    Q_INVOKABLE QString clipboardText() const;
};
