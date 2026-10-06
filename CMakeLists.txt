cmake_minimum_required(VERSION 3.20)
project(katarina VERSION 0.1.0 LANGUAGES CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)
find_package(KF6Kirigami REQUIRED)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(katarina
    src/main.cpp
    src/backend.cpp
    src/highlighter.cpp
    src/settings.cpp
)
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
        qml/KvTable.qml
        qml/FormTable.qml
        qml/JsonTree.qml
        qml/VarCompleter.qml
        qml/ShortcutField.qml
)

qt_add_resources(katarina "appicon"
    PREFIX "/icons"
    BASE icons
    FILES icons/katarina.svg
)

# Autochecagem da lógica de armazenamento.
qt_add_executable(check_storage tests/check_storage.cpp src/backend.cpp)
target_include_directories(check_storage PRIVATE src)
target_link_libraries(check_storage PRIVATE Qt6::Core Qt6::Network)

# ---- instalação: binário, ícone e lançador ----
install(TARGETS katarina ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES icons/katarina.svg DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

configure_file(packaging/org.katarina.Katarina.desktop.cmake
               ${CMAKE_CURRENT_BINARY_DIR}/org.katarina.Katarina.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.katarina.Katarina.desktop
        DESTINATION ${KDE_INSTALL_APPDIR})
