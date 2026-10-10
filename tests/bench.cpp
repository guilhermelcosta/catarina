// Benchmark of the Backend hot paths: variable resolution and tree.
// Run with: ./build/bin/bench_storage
// Compares the cost of a full "refresh" (what the UI did per edit/switch)
// and of rebuilding the collections tree.
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
                QStringLiteral("catarina"), QStringLiteral("catarina"));
    s.setValue(QStringLiteral("storageDir"), tmp.path() + QStringLiteral("/collections"));
    s.sync();

    Backend b;

    // 10 collections x 30 requests, each collection with 20 variables
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

    // environment with 30 variables, 10 of them secret
    QVariantList ev;
    for (int k = 0; k < 30; ++k) {
        QVariantMap m{{QStringLiteral("name"), QStringLiteral("g%1").arg(k)},
                      {QStringLiteral("value"), QStringLiteral("g")},
                      {QStringLiteral("scope"), QStringLiteral("all")}};
        if (k < 10) {
            m[QStringLiteral("secret")] = true;
            const QString id = QStringLiteral("sid%1").arg(k);
            m[QStringLiteral("secretId")] = id;
            b.saveSecret(id, QStringLiteral("secret"));
        }
        ev.append(m);
    }
    b.saveEnvironment(QStringLiteral("bench"), ev);
    b.setActiveEnvironment(QStringLiteral("bench"));

    const QVariantMap req{{QStringLiteral("url"), QStringLiteral("{{g0}}/{{g9}}")},
                          {QStringLiteral("vars"), QVariantList{}}};
    const int WARM = 20;
    const int N = 500;

    // ---- variable refresh (one pass, as the UI does today) ----
    for (int i = 0; i < WARM; ++i) {
        const auto st = b.variablesState(req, QStringLiteral("col0"));
        Q_UNUSED(st);
    }
    QElapsedTimer t;
    t.start();
    for (int i = 0; i < N; ++i) {
        const auto st = b.variablesState(req, QStringLiteral("col0"));
        Q_UNUSED(st);
    }
    std::printf("resolve        x%d: %lld ms\n", N, static_cast<long long>(t.elapsed()));

    // ---- typing burst (30 keys) ----
    // before: re-resolves on every key; after: debounce => 1 resolution at the end
    const int KEYS = 30;
    const int BURSTS = 20;
    t.restart();
    for (int burst = 0; burst < BURSTS; ++burst) {
        // keys only mark "dirty"; the debounce fires once after the burst
        const auto st = b.variablesState(req, QStringLiteral("col0"));
        Q_UNUSED(st);
    }
    std::printf("type %dx%d keys: %lld ms\n", BURSTS, KEYS,
                static_cast<long long>(t.elapsed()));

    // ---- collections tree ----
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
