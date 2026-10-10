#include "highlighter.h"

#include <QClipboard>
#include <QFont>
#include <QGuiApplication>
#include <QQuickTextDocument>
#include <QTextDocument>

VarHighlighter::VarHighlighter(QTextDocument *doc, const QColor &varColor, bool bold, bool json,
                               const QColor &strColor, const QColor &numColor, const QColor &kwColor,
                               const QColor &keyColor)
    : QSyntaxHighlighter(doc)
    , m_var(QStringLiteral("\\{\\{[^{}]*\\}\\}"))
    , m_str(QStringLiteral("\"(?:[^\"\\\\]|\\\\.)*\""))
    , m_num(QStringLiteral("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"))
    , m_kw(QStringLiteral("\\b(?:true|false|null)\\b"))
    // key = string followed (with spaces) by ':' — lookahead to avoid painting the ':'
    , m_key(QStringLiteral("\"(?:[^\"\\\\]|\\\\.)*\"(?=\\s*:)"))
    , m_json(json)
{
    m_varFmt.setForeground(varColor);
    m_varFmt.setFontWeight(bold ? QFont::Bold : QFont::Normal);

    // JSON token colors (only used when json=true; the caller always passes them)
    m_strFmt.setForeground(strColor);
    m_numFmt.setForeground(numColor);
    m_kwFmt.setForeground(kwColor);
    m_keyFmt.setForeground(keyColor);
}

void VarHighlighter::highlightBlock(const QString &text)
{
    if (m_json) {
        for (const auto &pair : {qMakePair(&m_str, m_strFmt), qMakePair(&m_num, m_numFmt),
                                 qMakePair(&m_kw, m_kwFmt)}) {
            auto it = pair.first->globalMatch(text);
            while (it.hasNext()) {
                const QRegularExpressionMatch m = it.next();
                setFormat(m.capturedStart(), m.capturedLength(), pair.second);
            }
        }
        // keys last: they override the string color of the same span
        auto kt = m_key.globalMatch(text);
        while (kt.hasNext()) {
            const QRegularExpressionMatch m = kt.next();
            setFormat(m.capturedStart(), m.capturedLength(), m_keyFmt);
        }
    }
    // variables last so they override (even inside strings)
    auto it = m_var.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        setFormat(m.capturedStart(), m.capturedLength(), m_varFmt);
    }
}

void VarSupport::attach(QObject *textDocument, const QColor &color, bool bold, bool json,
                        const QColor &strColor, const QColor &numColor, const QColor &kwColor,
                        const QColor &keyColor) const
{
    auto *qdoc = qobject_cast<QQuickTextDocument *>(textDocument);
    if (!qdoc || !qdoc->textDocument())
        return;
    auto *h = new VarHighlighter(qdoc->textDocument(), color, bold, json, strColor, numColor, kwColor,
                                 keyColor);
    h->setParent(qdoc);
}

void VarSupport::copyText(const QString &text) const
{
    if (auto *cb = QGuiApplication::clipboard())
        cb->setText(text);
}
