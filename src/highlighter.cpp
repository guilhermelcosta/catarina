#include "highlighter.h"

#include <QClipboard>
#include <QFont>
#include <QGuiApplication>
#include <QQuickTextDocument>
#include <QTextDocument>

VarHighlighter::VarHighlighter(QTextDocument *doc, const QColor &varColor, bool bold, bool json,
                               const QColor &strColor, const QColor &numColor, const QColor &kwColor)
    : QSyntaxHighlighter(doc)
    , m_var(QStringLiteral("\\{\\{[^{}]*\\}\\}"))
    , m_str(QStringLiteral("\"(?:[^\"\\\\]|\\\\.)*\""))
    , m_num(QStringLiteral("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"))
    , m_kw(QStringLiteral("\\b(?:true|false|null)\\b"))
    , m_json(json)
{
    m_varFmt.setForeground(varColor);
    m_varFmt.setFontWeight(bold ? QFont::Bold : QFont::Normal);

    // cores dos tokens JSON (só usadas quando json=true; o chamador sempre passa)
    m_strFmt.setForeground(strColor);
    m_numFmt.setForeground(numColor);
    m_kwFmt.setForeground(kwColor);
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
    }
    // variáveis por último para sobrepor (mesmo dentro de strings)
    auto it = m_var.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        setFormat(m.capturedStart(), m.capturedLength(), m_varFmt);
    }
}

void VarSupport::attach(QObject *textDocument, const QColor &color, bool bold, bool json,
                        const QColor &strColor, const QColor &numColor, const QColor &kwColor) const
{
    auto *qdoc = qobject_cast<QQuickTextDocument *>(textDocument);
    if (!qdoc || !qdoc->textDocument())
        return;
    auto *h = new VarHighlighter(qdoc->textDocument(), color, bold, json, strColor, numColor, kwColor);
    h->setParent(qdoc);
}

void VarSupport::copyText(const QString &text) const
{
    if (auto *cb = QGuiApplication::clipboard())
        cb->setText(text);
}
