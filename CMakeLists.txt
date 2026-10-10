cmake_minimum_required(VERSION 3.20)
project(katarina VERSION 0.1.0 LANGUAGES CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)
find_package(KF6Kirigami REQUIRED)

# segredos: cofre do SO (QtKeychain) quando disponível; senão, arquivo 0600.
# Opcional de propósito — o projeto compila sem o QtKeychain.
find_package(Qt6Keychain QUIET)
if(Qt6Keychain_FOUND)
    message(STATUS "QtKeychain encontrado: segredos no cofre do sistema")
    set(KATARINA_SECRETS_DEFS KATARINA_HAVE_KEYCHAIN)
    set(KATARINA_SECRETS_LIBS Qt6Keychain::Qt6Keychain)
else()
    message(STATUS "QtKeychain não encontrado: segredos em arquivo (0600)")
    set(KATARINA_SECRETS_DEFS "")
    set(KATARINA_SECRETS_LIBS "")
endif()

qt_standard_project_setup(REQUIRES 6.5)

# core compartilhado (backend + settings) compilado uma vez só, usado pelo app e testes
qt_add_library(katarina_core OBJECT
    src/backend.cpp
    src/core/request_logic.cpp
    src/core/variable_resolver.cpp
    src/net/http_client.cpp
    src/net/request_builder.cpp
    src/storage/collection_storage.cpp
    src/storage/environment_store.cpp
    src/storage/history_store.cpp
    src/storage/secret_store.cpp
    src/settings.cpp
)
target_include_directories(katarina_core PRIVATE src)
target_compile_definitions(katarina_core PRIVATE ${KATARINA_SECRETS_DEFS})
target_link_libraries(katarina_core PRIVATE Qt6::Core Qt6::Gui Qt6::Network ${KATARINA_SECRETS_LIBS})

# coleção de exemplo embutida (seed/), copiada no primeiro uso
# (Backend::seedDefaultCollection) — recursos em :/seed/...
file(GLOB_RECURSE KATARINA_SEED_FILES CONFIGURE_DEPENDS
     ${CMAKE_CURRENT_SOURCE_DIR}/seed/*)
qt_add_resources(katarina_core "seed"
    PREFIX "/"
    BASE ${CMAKE_CURRENT_SOURCE_DIR}
    FILES ${KATARINA_SEED_FILES})

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
    ${KATARINA_SECRETS_LIBS}
)

qt_add_resources(katarina "qml"
    PREFIX "/"
    FILES
        qml/Main.qml
        qml/Util.js
        qml/Strings.js
        qml/js/VarTokens.js
        qml/KvTable.qml
        qml/SaveBar.qml
        qml/EmptyState.qml
        qml/DialogHeader.qml
        qml/DialogActions.qml
        qml/ResolvedVarsTable.qml
        qml/JsonTree.qml
        qml/HeaderTable.qml
        qml/NetworkView.qml
        qml/VarCompleter.qml
        qml/VarField.qml
        qml/AuthEditor.qml
        qml/ShortcutField.qml
        qml/MethodBadge.qml
        qml/SourceChip.qml
        qml/SplitGrip.qml
        qml/AppController.qml
        qml/Sidebar.qml
        qml/TabStrip.qml
        qml/dialogs/NewReqDialog.qml
        qml/dialogs/NameDialog.qml
        qml/dialogs/ConfirmCloseDialog.qml
        qml/dialogs/QuitDialog.qml
        qml/dialogs/CurlImportDialog.qml
        qml/dialogs/CurlExportDialog.qml
        qml/dialogs/FolderPicker.qml
        qml/dialogs/MoveDialog.qml
        qml/dialogs/RenameDialog.qml
        qml/dialogs/HistoryDialog.qml
        qml/dialogs/CreateEnvDialog.qml
        qml/dialogs/DiscardEnvDialog.qml
        qml/dialogs/RenameEnvDialog.qml
        qml/dialogs/ScopePopup.qml
        qml/dialogs/FilePickDialog.qml
        qml/dialogs/DeleteDialog.qml
        qml/dialogs/CommandPalette.qml
        qml/screens/SettingsScreen.qml
        qml/screens/EnvironmentScreen.qml
        qml/screens/CollectionScreen.qml
        qml/screens/RequestEditor.qml
        qml/screens/BodyEditor.qml
        qml/screens/ReqVarsEditor.qml
        qml/screens/ResponsePane.qml
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
target_link_libraries(check_storage PRIVATE Qt6::Core Qt6::Gui Qt6::Network ${KATARINA_SECRETS_LIBS})

# Benchmark dos caminhos quentes (não é teste; roda à mão).
qt_add_executable(bench_storage tests/bench.cpp)
target_sources(bench_storage PRIVATE $<TARGET_OBJECTS:katarina_core>)
target_include_directories(bench_storage PRIVATE src)
target_link_libraries(bench_storage PRIVATE Qt6::Core Qt6::Gui Qt6::Network ${KATARINA_SECRETS_LIBS})

# ---- testes (ctest) ----
find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)

add_test(NAME check_storage COMMAND check_storage)

# componentes reutilizáveis (KvTable/HeaderTable/JsonTree)
qt_add_executable(tst_components tests/tst_components.cpp)
target_link_libraries(tst_components PRIVATE Qt6::Quick Qt6::QuickTest)
target_compile_definitions(tst_components PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/components")
add_test(NAME tst_components COMMAND tst_components)

# comportamento de tela: instancia o Main com backend/settings reais e dirige o AppController
qt_add_executable(tst_app tests/tst_app.cpp src/highlighter.cpp)
target_sources(tst_app PRIVATE $<TARGET_OBJECTS:katarina_core>)
target_include_directories(tst_app PRIVATE src)
target_link_libraries(tst_app PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickTest Qt6::Network ${KATARINA_SECRETS_LIBS})
target_compile_definitions(tst_app PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/app")
add_test(NAME tst_app COMMAND tst_app)

# realce JSON (chave != valor) — lógica pura sobre QTextDocument
qt_add_executable(check_highlighter tests/check_highlighter.cpp src/highlighter.cpp)
target_include_directories(check_highlighter PRIVATE src)
target_link_libraries(check_highlighter PRIVATE Qt6::Gui Qt6::Quick Qt6::Test)
add_test(NAME check_highlighter COMMAND check_highlighter)

# integração HTTP hermética (QTcpServer local): resposta, headers, querystring,
# erro de rede, cancelamento, multipart e falha ao abrir arquivo
qt_add_executable(check_http tests/check_http.cpp)
target_sources(check_http PRIVATE $<TARGET_OBJECTS:katarina_core>)
target_include_directories(check_http PRIVATE src)
target_link_libraries(check_http PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Test ${KATARINA_SECRETS_LIBS})
add_test(NAME check_http COMMAND check_http)

# garante que o Main.qml carrega sem erros de QML
add_test(NAME qml_smoke
         COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/qml_smoke.sh $<TARGET_FILE:katarina>)

set_tests_properties(check_storage tst_components tst_app check_highlighter check_http qml_smoke PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# ---- instalação: binário, ícone e lançador ----
install(TARGETS katarina ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES icons/katarina.svg DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

configure_file(packaging/org.katarina.Katarina.desktop.cmake
               ${CMAKE_CURRENT_BINARY_DIR}/org.katarina.Katarina.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.katarina.Katarina.desktop
        DESTINATION ${KDE_INSTALL_APPDIR})
