#pragma once

#include <QColor>
#include <QObject>
#include <QRegularExpression>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>

// Highlights {{variable}} (and, optionally, JSON tokens) in an editor.
class VarHighlighter : public QSyntaxHighlighter
{
    Q_OBJECT
public:
    VarHighlighter(QTextDocument *doc, const QColor &varColor, bool bold, bool json,
                   const QColor &strColor = QColor(), const QColor &numColor = QColor(),
                   const QColor &kwColor = QColor(), const QColor &keyColor = QColor());

protected:
    void highlightBlock(const QString &text) override;

private:
    QRegularExpression m_var, m_str, m_num, m_kw, m_key;
    QTextCharFormat m_varFmt, m_strFmt, m_numFmt, m_kwFmt, m_keyFmt;
    bool m_json;
};

class VarSupport : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;

    // attaches a highlighter to an editor's QQuickTextDocument (TextArea);
    // the JSON key/string/number/keyword colors come from the theme (optional)
    Q_INVOKABLE void attach(QObject *textDocument, const QColor &color, bool bold = true,
                            bool json = false, const QColor &strColor = QColor(),
                            const QColor &numColor = QColor(), const QColor &kwColor = QColor(),
                            const QColor &keyColor = QColor()) const;

    // clipboard
    Q_INVOKABLE void copyText(const QString &text) const;
};
