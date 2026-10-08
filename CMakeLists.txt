cmake_minimum_required(VERSION 3.20)
project(katarina VERSION 0.1.0 LANGUAGES CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)
find_package(KF6Kirigami REQUIRED)

qt_standard_project_setup(REQUIRES 6.5)

# core compartilhado (backend + settings) compilado uma vez só, usado pelo app e testes
qt_add_library(katarina_core OBJECT
    src/backend.cpp
    src/settings.cpp
)
target_include_directories(katarina_core PRIVATE src)
target_link_libraries(katarina_core PRIVATE Qt6::Core Qt6::Gui Qt6::Network)

qt_add_executable(katarina
    src/main.cpp
    src/highlighter.cpp
)
target_sources(katarina PRIVATE $<TARGET_OBJECTS:katarina_core>)
target_include_directories(katarina PRIVATE src)

target_link_libraries(katarina PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    KF6::Kirigami
)

qt_add_resources(katarina "qml"
    PREFIX "/"
    FILES
        qml/Main.qml
        qml/Util.js
        qml/Strings.js
        qml/KvTable.qml
        qml/SaveBar.qml
        qml/EmptyState.qml
        qml/ResolvedVarsTable.qml
        qml/JsonTree.qml
        qml/HeaderTable.qml
        qml/NetworkView.qml
        qml/VarCompleter.qml
        qml/VarField.qml
        qml/ShortcutField.qml
)

qt_add_resources(katarina "appicon"
    PREFIX "/icons"
    BASE icons
    FILES icons/katarina.svg
)

# Autochecagem da lógica do Backend (sem rede), hermética.
qt_add_executable(check_storage tests/check_storage.cpp)
target_sources(check_storage PRIVATE $<TARGET_OBJECTS:katarina_core>)
target_include_directories(check_storage PRIVATE src)
target_link_libraries(check_storage PRIVATE Qt6::Core Qt6::Gui Qt6::Network)

# Benchmark dos caminhos quentes (não é teste; roda à mão).
qt_add_executable(bench_storage tests/bench.cpp)
target_sources(bench_storage PRIVATE $<TARGET_OBJECTS:katarina_core>)
target_include_directories(bench_storage PRIVATE src)
target_link_libraries(bench_storage PRIVATE Qt6::Core Qt6::Gui Qt6::Network)

# ---- testes (ctest) ----
find_package(Qt6 REQUIRED COMPONENTS QuickTest)

add_test(NAME check_storage COMMAND check_storage)

# componentes reutilizáveis (KvTable/HeaderTable/JsonTree)
qt_add_executable(tst_components tests/tst_components.cpp)
target_link_libraries(tst_components PRIVATE Qt6::Quick Qt6::QuickTest)
target_compile_definitions(tst_components PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_test(NAME tst_components COMMAND tst_components)

# garante que o Main.qml carrega sem erros de QML
add_test(NAME qml_smoke
         COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/qml_smoke.sh $<TARGET_FILE:katarina>)

set_tests_properties(check_storage tst_components qml_smoke PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# ---- instalação: binário, ícone e lançador ----
install(TARGETS katarina ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES icons/katarina.svg DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

configure_file(packaging/org.katarina.Katarina.desktop.cmake
               ${CMAKE_CURRENT_BINARY_DIR}/org.katarina.Katarina.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.katarina.Katarina.desktop
        DESTINATION ${KDE_INSTALL_APPDIR})
