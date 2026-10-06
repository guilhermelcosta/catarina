/****************************************************************************
** Meta object code from reading C++ file 'backend.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.11.2)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../src/backend.h"
#include <QtNetwork/QSslError>
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'backend.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.11.2. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN7BackendE_t {};
} // unnamed namespace

template <> constexpr inline auto Backend::qt_create_metaobjectdata<qt_meta_tag_ZN7BackendE_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "Backend",
        "responseReady",
        "",
        "status",
        "statusText",
        "QVariantList",
        "headers",
        "body",
        "elapsedMs",
        "sizeBytes",
        "error",
        "message",
        "started",
        "canceled",
        "collectionsChanged",
        "environmentsChanged",
        "historyChanged",
        "setStorageDir",
        "dir",
        "send",
        "QVariantMap",
        "request",
        "collection",
        "cancel",
        "missingVariables",
        "variableNoteFor",
        "name",
        "collectionTree",
        "loadRequest",
        "relPath",
        "saveRequest",
        "data",
        "deleteEntry",
        "createFolder",
        "moveEntry",
        "from",
        "toFolder",
        "renameEntry",
        "newName",
        "duplicateEntry",
        "collectionVariables",
        "saveCollectionVariables",
        "vars",
        "collectionHeaders",
        "saveCollectionHeaders",
        "environments",
        "environmentVariables",
        "saveEnvironment",
        "variables",
        "deleteEnvironment",
        "renameEnvironment",
        "oldName",
        "setActiveEnvironment",
        "secretValue",
        "id",
        "saveSecret",
        "value",
        "removeSecret",
        "history",
        "clearHistory",
        "effectiveVariables",
        "requestVars",
        "resolvedVariables",
        "storageDir",
        "activeEnvironment"
    };

    QtMocHelpers::UintData qt_methods {
        // Signal 'responseReady'
        QtMocHelpers::SignalData<void(int, const QString &, const QVariantList &, const QString &, int, int)>(1, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::Int, 3 }, { QMetaType::QString, 4 }, { 0x80000000 | 5, 6 }, { QMetaType::QString, 7 },
            { QMetaType::Int, 8 }, { QMetaType::Int, 9 },
        }}),
        // Signal 'error'
        QtMocHelpers::SignalData<void(const QString &)>(10, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 11 },
        }}),
        // Signal 'started'
        QtMocHelpers::SignalData<void()>(12, 2, QMC::AccessPublic, QMetaType::Void),
        // Signal 'canceled'
        QtMocHelpers::SignalData<void()>(13, 2, QMC::AccessPublic, QMetaType::Void),
        // Signal 'collectionsChanged'
        QtMocHelpers::SignalData<void()>(14, 2, QMC::AccessPublic, QMetaType::Void),
        // Signal 'environmentsChanged'
        QtMocHelpers::SignalData<void()>(15, 2, QMC::AccessPublic, QMetaType::Void),
        // Signal 'historyChanged'
        QtMocHelpers::SignalData<void()>(16, 2, QMC::AccessPublic, QMetaType::Void),
        // Method 'setStorageDir'
        QtMocHelpers::MethodData<void(const QString &)>(17, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 18 },
        }}),
        // Method 'send'
        QtMocHelpers::MethodData<void(const QVariantMap &, const QString &)>(19, 2, QMC::AccessPublic, QMetaType::Void, {{
            { 0x80000000 | 20, 21 }, { QMetaType::QString, 22 },
        }}),
        // Method 'cancel'
        QtMocHelpers::MethodData<void()>(23, 2, QMC::AccessPublic, QMetaType::Void),
        // Method 'missingVariables'
        QtMocHelpers::MethodData<QStringList(const QVariantMap &, const QString &) const>(24, 2, QMC::AccessPublic, QMetaType::QStringList, {{
            { 0x80000000 | 20, 21 }, { QMetaType::QString, 22 },
        }}),
        // Method 'variableNoteFor'
        QtMocHelpers::MethodData<QString(const QString &, const QString &) const>(25, 2, QMC::AccessPublic, QMetaType::QString, {{
            { QMetaType::QString, 26 }, { QMetaType::QString, 22 },
        }}),
        // Method 'collectionTree'
        QtMocHelpers::MethodData<QVariantList() const>(27, 2, QMC::AccessPublic, 0x80000000 | 5),
        // Method 'loadRequest'
        QtMocHelpers::MethodData<QVariantMap(const QString &) const>(28, 2, QMC::AccessPublic, 0x80000000 | 20, {{
            { QMetaType::QString, 29 },
        }}),
        // Method 'saveRequest'
        QtMocHelpers::MethodData<bool(const QString &, const QVariantMap &)>(30, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 29 }, { 0x80000000 | 20, 31 },
        }}),
        // Method 'deleteEntry'
        QtMocHelpers::MethodData<bool(const QString &)>(32, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 29 },
        }}),
        // Method 'createFolder'
        QtMocHelpers::MethodData<bool(const QString &)>(33, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 29 },
        }}),
        // Method 'moveEntry'
        QtMocHelpers::MethodData<bool(const QString &, const QString &)>(34, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 35 }, { QMetaType::QString, 36 },
        }}),
        // Method 'renameEntry'
        QtMocHelpers::MethodData<bool(const QString &, const QString &)>(37, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 29 }, { QMetaType::QString, 38 },
        }}),
        // Method 'duplicateEntry'
        QtMocHelpers::MethodData<bool(const QString &)>(39, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 29 },
        }}),
        // Method 'collectionVariables'
        QtMocHelpers::MethodData<QVariantList(const QString &) const>(40, 2, QMC::AccessPublic, 0x80000000 | 5, {{
            { QMetaType::QString, 22 },
        }}),
        // Method 'saveCollectionVariables'
        QtMocHelpers::MethodData<bool(const QString &, const QVariantList &)>(41, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 22 }, { 0x80000000 | 5, 42 },
        }}),
        // Method 'collectionHeaders'
        QtMocHelpers::MethodData<QVariantList(const QString &) const>(43, 2, QMC::AccessPublic, 0x80000000 | 5, {{
            { QMetaType::QString, 22 },
        }}),
        // Method 'saveCollectionHeaders'
        QtMocHelpers::MethodData<bool(const QString &, const QVariantList &)>(44, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 22 }, { 0x80000000 | 5, 6 },
        }}),
        // Method 'environments'
        QtMocHelpers::MethodData<QVariantList() const>(45, 2, QMC::AccessPublic, 0x80000000 | 5),
        // Method 'environmentVariables'
        QtMocHelpers::MethodData<QVariantList(const QString &) const>(46, 2, QMC::AccessPublic, 0x80000000 | 5, {{
            { QMetaType::QString, 26 },
        }}),
        // Method 'saveEnvironment'
        QtMocHelpers::MethodData<bool(const QString &, const QVariantList &)>(47, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 26 }, { 0x80000000 | 5, 48 },
        }}),
        // Method 'deleteEnvironment'
        QtMocHelpers::MethodData<bool(const QString &)>(49, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 26 },
        }}),
        // Method 'renameEnvironment'
        QtMocHelpers::MethodData<bool(const QString &, const QString &)>(50, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 51 }, { QMetaType::QString, 38 },
        }}),
        // Method 'setActiveEnvironment'
        QtMocHelpers::MethodData<void(const QString &)>(52, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 26 },
        }}),
        // Method 'secretValue'
        QtMocHelpers::MethodData<QString(const QString &) const>(53, 2, QMC::AccessPublic, QMetaType::QString, {{
            { QMetaType::QString, 54 },
        }}),
        // Method 'saveSecret'
        QtMocHelpers::MethodData<bool(const QString &, const QString &)>(55, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 54 }, { QMetaType::QString, 56 },
        }}),
        // Method 'removeSecret'
        QtMocHelpers::MethodData<bool(const QString &)>(57, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 54 },
        }}),
        // Method 'history'
        QtMocHelpers::MethodData<QVariantList() const>(58, 2, QMC::AccessPublic, 0x80000000 | 5),
        // Method 'clearHistory'
        QtMocHelpers::MethodData<void()>(59, 2, QMC::AccessPublic, QMetaType::Void),
        // Method 'effectiveVariables'
        QtMocHelpers::MethodData<QVariantMap(const QString &, const QVariantList &) const>(60, 2, QMC::AccessPublic, 0x80000000 | 20, {{
            { QMetaType::QString, 22 }, { 0x80000000 | 5, 61 },
        }}),
        // Method 'resolvedVariables'
        QtMocHelpers::MethodData<QVariantList(const QString &, const QVariantList &) const>(62, 2, QMC::AccessPublic, 0x80000000 | 5, {{
            { QMetaType::QString, 22 }, { 0x80000000 | 5, 61 },
        }}),
    };
    QtMocHelpers::UintData qt_properties {
        // property 'storageDir'
        QtMocHelpers::PropertyData<QString>(63, QMetaType::QString, QMC::DefaultPropertyFlags | QMC::Constant),
        // property 'activeEnvironment'
        QtMocHelpers::PropertyData<QString>(64, QMetaType::QString, QMC::DefaultPropertyFlags, 5),
    };
    QtMocHelpers::UintData qt_enums {
    };
    return QtMocHelpers::metaObjectData<Backend, qt_meta_tag_ZN7BackendE_t>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums);
}
Q_CONSTINIT const QMetaObject Backend::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN7BackendE_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN7BackendE_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN7BackendE_t>.metaTypes,
    nullptr
} };

void Backend::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<Backend *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->responseReady((*reinterpret_cast<std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast<std::add_pointer_t<QVariantList>>(_a[3])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[4])),(*reinterpret_cast<std::add_pointer_t<int>>(_a[5])),(*reinterpret_cast<std::add_pointer_t<int>>(_a[6]))); break;
        case 1: _t->error((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1]))); break;
        case 2: _t->started(); break;
        case 3: _t->canceled(); break;
        case 4: _t->collectionsChanged(); break;
        case 5: _t->environmentsChanged(); break;
        case 6: _t->historyChanged(); break;
        case 7: _t->setStorageDir((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1]))); break;
        case 8: _t->send((*reinterpret_cast<std::add_pointer_t<QVariantMap>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2]))); break;
        case 9: _t->cancel(); break;
        case 10: { QStringList _r = _t->missingVariables((*reinterpret_cast<std::add_pointer_t<QVariantMap>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast<QStringList*>(_a[0]) = std::move(_r); }  break;
        case 11: { QString _r = _t->variableNoteFor((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast<QString*>(_a[0]) = std::move(_r); }  break;
        case 12: { QVariantList _r = _t->collectionTree();
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 13: { QVariantMap _r = _t->loadRequest((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 14: { bool _r = _t->saveRequest((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QVariantMap>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 15: { bool _r = _t->deleteEntry((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 16: { bool _r = _t->createFolder((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 17: { bool _r = _t->moveEntry((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 18: { bool _r = _t->renameEntry((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 19: { bool _r = _t->duplicateEntry((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 20: { QVariantList _r = _t->collectionVariables((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 21: { bool _r = _t->saveCollectionVariables((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QVariantList>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 22: { QVariantList _r = _t->collectionHeaders((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 23: { bool _r = _t->saveCollectionHeaders((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QVariantList>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 24: { QVariantList _r = _t->environments();
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 25: { QVariantList _r = _t->environmentVariables((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 26: { bool _r = _t->saveEnvironment((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QVariantList>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 27: { bool _r = _t->deleteEnvironment((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 28: { bool _r = _t->renameEnvironment((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 29: _t->setActiveEnvironment((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1]))); break;
        case 30: { QString _r = _t->secretValue((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QString*>(_a[0]) = std::move(_r); }  break;
        case 31: { bool _r = _t->saveSecret((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 32: { bool _r = _t->removeSecret((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 33: { QVariantList _r = _t->history();
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 34: _t->clearHistory(); break;
        case 35: { QVariantMap _r = _t->effectiveVariables((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QVariantList>>(_a[2])));
            if (_a[0]) *reinterpret_cast<QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 36: { QVariantList _r = _t->resolvedVariables((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QVariantList>>(_a[2])));
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        default: ;
        }
    }
    if (_c == QMetaObject::IndexOfMethod) {
        if (QtMocHelpers::indexOfMethod<void (Backend::*)(int , const QString & , const QVariantList & , const QString & , int , int )>(_a, &Backend::responseReady, 0))
            return;
        if (QtMocHelpers::indexOfMethod<void (Backend::*)(const QString & )>(_a, &Backend::error, 1))
            return;
        if (QtMocHelpers::indexOfMethod<void (Backend::*)()>(_a, &Backend::started, 2))
            return;
        if (QtMocHelpers::indexOfMethod<void (Backend::*)()>(_a, &Backend::canceled, 3))
            return;
        if (QtMocHelpers::indexOfMethod<void (Backend::*)()>(_a, &Backend::collectionsChanged, 4))
            return;
        if (QtMocHelpers::indexOfMethod<void (Backend::*)()>(_a, &Backend::environmentsChanged, 5))
            return;
        if (QtMocHelpers::indexOfMethod<void (Backend::*)()>(_a, &Backend::historyChanged, 6))
            return;
    }
    if (_c == QMetaObject::ReadProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast<QString*>(_v) = _t->storageDir(); break;
        case 1: *reinterpret_cast<QString*>(_v) = _t->activeEnvironment(); break;
        default: break;
        }
    }
}

const QMetaObject *Backend::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *Backend::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN7BackendE_t>.strings))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int Backend::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 37)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 37;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 37)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 37;
    }
    if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 2;
    }
    return _id;
}

// SIGNAL 0
void Backend::responseReady(int _t1, const QString & _t2, const QVariantList & _t3, const QString & _t4, int _t5, int _t6)
{
    QMetaObject::activate<void>(this, &staticMetaObject, 0, nullptr, _t1, _t2, _t3, _t4, _t5, _t6);
}

// SIGNAL 1
void Backend::error(const QString & _t1)
{
    QMetaObject::activate<void>(this, &staticMetaObject, 1, nullptr, _t1);
}

// SIGNAL 2
void Backend::started()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void Backend::canceled()
{
    QMetaObject::activate(this, &staticMetaObject, 3, nullptr);
}

// SIGNAL 4
void Backend::collectionsChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 4, nullptr);
}

// SIGNAL 5
void Backend::environmentsChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 5, nullptr);
}

// SIGNAL 6
void Backend::historyChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 6, nullptr);
}
QT_WARNING_POP
