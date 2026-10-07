// Benchmark dos caminhos quentes do Backend: resolução de variáveis e árvore.
// Roda com: ./build/bin/bench_storage
// Compara o custo de um "refresh" completo (o que a UI fazia por edição/troca)
// e de reconstruir a árvore de coleções.
#include "backend.h"

#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QSettings>
#include <QTemporaryDir>

#include <cstdio>

int main(int argc, char **argv)
{
    QTemporaryDir tmp;
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", tmp.path().toUtf8());
    QCoreApplication app(argc, argv);

    QSettings s(QSettings::IniFormat, QSettings::UserScope,
                QStringLiteral("katarina"), QStringLiteral("katarina"));
    s.setValue(QStringLiteral("storageDir"), tmp.path() + QStringLiteral("/collections"));
    s.sync();

    Backend b;

    // 10 coleções x 30 requests, cada coleção com 20 variáveis
    for (int c = 0; c < 10; ++c) {
        const QString col = QStringLiteral("col%1").arg(c);
        b.createFolder(col);
        QVariantList vars;
        for (int v = 0; v < 20; ++v)
            vars.append(QVariantMap{{QStringLiteral("name"), QStringLiteral("v%1").arg(v)},
                                    {QStringLiteral("value"), QStringLiteral("x")},
                                    {QStringLiteral("enabled"), true}});
        b.saveCollectionVariables(col, vars);
        for (int r = 0; r < 30; ++r)
            b.saveRequest(col + QStringLiteral("/req%1").arg(r),
                          {{QStringLiteral("method"), QStringLiteral("GET")},
                           {QStringLiteral("url"), QStringLiteral("http://x")},
                           {QStringLiteral("vars"), QVariantList{}}});
    }

    // ambiente com 30 variáveis, 10 delas secretas
    QVariantList ev;
    for (int k = 0; k < 30; ++k) {
        QVariantMap m{{QStringLiteral("name"), QStringLiteral("g%1").arg(k)},
                      {QStringLiteral("value"), QStringLiteral("g")},
                      {QStringLiteral("scope"), QStringLiteral("all")}};
        if (k < 10) {
            m[QStringLiteral("secret")] = true;
            const QString id = QStringLiteral("sid%1").arg(k);
            m[QStringLiteral("secretId")] = id;
            b.saveSecret(id, QStringLiteral("segredo"));
        }
        ev.append(m);
    }
    b.saveEnvironment(QStringLiteral("bench"), ev);
    b.setActiveEnvironment(QStringLiteral("bench"));

    const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{g0}}/{{g9}}")},
                          {QStringLiteral("vars"), QVariantList{}}};
    const int WARM = 20;
    const int N = 500;

    // ---- refresh de variáveis (uma passada, como a UI faz hoje) ----
    for (int i = 0; i < WARM; ++i) {
#ifdef BENCH_AFTER
        const auto st = b.variablesState(req, QStringLiteral("col0"));
        Q_UNUSED(st);
#else
        const auto miss = b.missingVariables(req, QStringLiteral("col0"));
        const auto res = b.resolvedVariables(QStringLiteral("col0"), {});
        Q_UNUSED(miss);
        Q_UNUSED(res);
#endif
    }
    QElapsedTimer t;
    t.start();
    for (int i = 0; i < N; ++i) {
#ifdef BENCH_AFTER
        const auto st = b.variablesState(req, QStringLiteral("col0"));
        Q_UNUSED(st);
#else
        const auto miss = b.missingVariables(req, QStringLiteral("col0"));
        const auto res = b.resolvedVariables(QStringLiteral("col0"), {});
        Q_UNUSED(miss);
        Q_UNUSED(res);
#endif
    }
    std::printf("resolve        x%d: %lld ms\n", N, static_cast<long long>(t.elapsed()));

    // ---- rajada de digitação (30 teclas) ----
    // antes: re-resolve a cada tecla; depois: debounce => 1 resolução no fim
    const int KEYS = 30;
    const int BURSTS = 20;
    t.restart();
    for (int burst = 0; burst < BURSTS; ++burst) {
#ifdef BENCH_AFTER
        // teclas só marcam "dirty"; o debounce dispara uma vez após a rajada
        const auto st = b.variablesState(req, QStringLiteral("col0"));
        Q_UNUSED(st);
#else
        for (int k = 0; k < KEYS; ++k) {
            const auto miss = b.missingVariables(req, QStringLiteral("col0"));
            const auto res = b.resolvedVariables(QStringLiteral("col0"), {});
            Q_UNUSED(miss);
            Q_UNUSED(res);
        }
#endif
    }
    std::printf("digitar %dx%d teclas: %lld ms\n", BURSTS, KEYS,
                static_cast<long long>(t.elapsed()));

    // ---- árvore de coleções ----
    for (int i = 0; i < WARM; ++i) {
        const auto tree = b.collectionTree();
        Q_UNUSED(tree);
    }
    t.restart();
    for (int i = 0; i < N; ++i) {
        const auto tree = b.collectionTree();
        Q_UNUSED(tree);
    }
    std::printf("collectionTree x%d: %lld ms\n", N, static_cast<long long>(t.elapsed()));
    std::fflush(stdout);
    return 0;
}
