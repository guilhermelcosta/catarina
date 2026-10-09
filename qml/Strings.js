.pragma library

// Central de textos da UI (inglês). É o único arquivo a editar para mudar qualquer
// texto exibido no app. Uso: `import "Strings.js" as Strings` → `text: Strings.t.save`.
//
// Não coloque aqui valores de lógica (métodos HTTP, tipos de corpo, escopos, ids),
// nem texto que o usuário digita. Só rótulos exibidos.

var t = {
    appName: "katarina",

    // ---- barra superior / painéis ----
    history: "History",
    settings: "Settings",
    add: "Add",
    deleteSelected: "Delete selected",
    moreActions: "More actions",
    hideCollections: "Hide collections panel",
    showCollections: "Show collections panel",
    hideResponse: "Hide response panel",
    showResponse: "Show response panel",
    noEnvironment: "No environment",

    // ---- ambientes ----
    activeEnvironment: "Active environment",
    readyToStart: "Ready to start?",
    createEnvHint: "Create an environment to have variables like base_url and tokens.",
    createEnvironment: "Create environment…",
    manageVariables: "Manage variables…",
    environments: "Environments",
    newEnvironment: "New environment…",
    delete: "Delete",
    viewAllVariables: "All variables",
    globalsEverywhere: "globals show in every view",
    newEnvironmentShort: "environment name",
    saveBeforeRenameEnv: "Save before renaming",
    renameEnvTooltip: "Rename environment",

    // ---- coleções / barra lateral ----
    collections: "Collections",
    collection: "Collection",
    overview: "Overview",
    folder: "Folder",
    location: "Location",
    requests: "Requests",
    subfolders: "Subfolders",
    folderHint: "Folder is only organization. Headers and variables live on the collection.",
    effectiveVariables: "Effective variables",
    noCollectionVariables: "No variables defined in this collection.",
    requestsInFolder: "Requests in this folder",
    requestsInCollection: "Requests in this collection",
    noRequestsInFolder: "No requests in this folder yet.",
    noRequestsInCollection: "No requests in this collection yet.",
    collectionHeaders: "Collection headers",
    collectionHeadersHint: "Sent on every request in this collection. A request can override.",
    collectionVariables: "Collection variables",
    collectionVariablesHint: "Use {{name}} in any request in this collection. Mark as secret to keep the value out of version control.",
    collectionAuth: "Collection authentication",
    collectionAuthHint: "Used by every request in this collection that sets Authentication to “Inherit from collection”.",
    collectionAuthSaved: "Collection authentication saved",
    noRequestOpen: "No request open",
    noRequestOpenHint: "Select a request in the sidebar or create a new one.",
    newRequest: "New request…",

    // ---- request ----
    parameters: "Parameters",
    headers: "Headers",
    body: "Body",
    authentication: "Authentication",
    variables: "Variables",
    type: "Type",
    bodyNone: "none",
    bodyText: "text",
    formatJson: "Indent the JSON",
    noBody: "No body.",
    authNone: "No authentication.",
    variable: "variable",
    parameter: "parameter",
    header: "header",
    field: "field",
    jsonExample: '{ "key": "value" }',
    urlExample: "{{base_url}}/resource",
    noVariablesDefined: "No variables defined.",
    copy: "Copy",
    copyAllHeaders: "Copy all headers",
    copyResponse: "Copy response to clipboard",
    send: "Send",
    cancel: "Cancel",
    create: "Create",
    save: "Save",
    discard: "Discard",
    rename: "Rename",
    close: "Close",
    clear: "Clear",
    apply: "Apply",
    browse: "Browse…",
    formatButton: "Format",
    unsavedMarker: "unsaved changes",
    discardTooltip: "Discard unsaved changes",
    saveTooltip: "Save (Ctrl+S)",
    renameTooltip: "Rename",

    // auth types
    authBearer: "Bearer token",
    authBasic: "Basic (user/password)",
    authApiKey: "API key",
    authInherit: "Inherit from collection",
    authInheritHint: "Using the collection's authentication.",
    token: "Token",
    user: "User",
    password: "Password",
    headerName: "Header name",
    value: "Value",

    // ---- resposta ----
    responseBody: "Body",
    responseTree: "Tree",
    responseHeaders: "Headers",
    responseCookies: "Cookies",
    responseNetwork: "Network",
    searchResponse: "Search response…",
    noCookies: "No cookies.",
    noResponseYet: "No response yet",
    noResponseHint: "Send the request (Ctrl+Enter) to see the response here.",
    openPaletteHint: "opens the command palette",
    prevMatch: "Previous match",
    nextMatch: "Next match",
    bodyHint: "Response body",
    treeHint: "Explore the JSON as a tree",
    headersHint: "Response headers",
    cookiesHint: "Response cookies",
    networkHint: "Connection details and the sent request",
    clearFind: "Clear search",
    findTooltip: "Find in response (Ctrl+F)",

    // ---- rede ----
    connection: "Connection",
    host: "Host",
    port: "Port",
    protocol: "Protocol",
    encrypted: "Encrypted",
    yesTls: "Yes (TLS)",
    no: "No",
    size: "Size",
    requestSent: "Request sent",
    noHeaders: "no headers",
    noHeadersEmpty: "No headers.",
    bodySent: "Body sent",
    networkEmpty: "Send a request to see network data.",

    // ---- tabelas / árvore ----
    active: "Active",
    key: "Key",
    scope: "Scope",
    secret: "Secret",
    secretInVault: "secret (in vault)",
    chooseFile: "Choose file…",
    removeRow: "Remove row",
    nothingHere: "Nothing here yet.",
    add: "Add",
    remove: "Remove",
    removeRowQuestion: "Remove this row?",
    noResponse: "No response.",
    invalidJson: "Response is not valid JSON.",
    notDefined: "not defined",
    disabled: "disabled",
    origin: "Origin",
    name: "Name",

    // ---- diálogos ----
    newRequestTitle: "New request",
    nameLabel: "Name",
    urlLabel: "URL",
    requestNamePlaceholder: "request name",
    urlPlaceholder: "https://...",
    newFolderTitle: "New folder",
    newCollectionTitle: "New collection",
    folderNamePlaceholder: "folder name",
    collectionNamePlaceholder: "collection name",
    unsavedChangesTitle: "Unsaved changes",
    quitTitle: "Quit katarina",
    importCurlTitle: "Import cURL",
    importCurlLabel: "Paste a cURL command:",
    importCurlPlaceholder: "curl 'https://…' -H '…' -d '…'",
    import: "Import",
    exportTitle: "Export code",
    chooseCollectionsFolder: "Choose collections folder",
    renameTitle: "Rename",
    newNameLabel: "New name:",
    historyTitle: "History",
    historyHint: "Click to create a new pre-filled request.",
    historyEmpty: "Nothing in history yet — send a request.",
    createEnvTitle: "Create environment",
    envNameLabel: "Environment name",
    envNamePlaceholder: "e.g. dev",
    discardChangesTitle: "Discard changes?",
    discardEnvMessage: "There are unsaved changes in this environment. Switching environments will discard them.",
    renameEnvTitle: "Rename environment",
    newEnvNameLabel: "New environment name",
    scopeOfVariable: "Variable scope",
    globalTab: "Global",
    collectionsTab: "Collections",
    noCollectionsYet: "You don't have collections yet.",
    chooseFileTitle: "Choose file",
    commandPalette: "Command palette",
    commandPlaceholder: "Type a command…",
    deleteTitle: "Delete",
    cannotBeUndone: "This action can't be undone.",

    // ---- erros ----
    errorPrefix: "Error: ",
    sending: "Sending…",
    canceled: "Canceled",
    invalidJsonShort: "Invalid JSON",
    saveBeforeRename: "Save your changes before renaming",
    environmentExists: "An environment with this name already exists.",
    renameFailed: "Couldn't rename",
    codeCopied: "Code copied",
    headersCopied: "Headers copied",
    responseCopied: "Response copied",
    environmentSaved: "Environment saved",
    provideUrl: "Provide a URL",
    collectionVarsSaved: "Collection variables saved",
    collectionHeadersSaved: "Collection headers saved",
    changesDiscarded: "Changes discarded",
    unsavedChanges: "Unsaved changes.",
    unsavedRequests: "There are requests with unsaved changes.",
    discardAndQuit: "Discard and quit",
    saveAndQuit: "Save and quit",
    itemExists: "An item with this name already exists here.",
    nameCannotContainSlash: "The name can't contain '/'.",

    // ---- validação de variável repetida ----
    duplicateNameHint: "Variable name repeated in this scope",

    // ---- escopo da variável (chip) ----
    validForAllCollections: "Applies to all collections",
    noCollectionSelected: "No collection selected",
    chooseCollections: "choose collections…",
    authNoneOption: "none",

    // ---- configurações ----
    view: "View:",
    appearance: "Appearance",
    editorFont: "Editor font:",
    defaultZero: "0 = default",
    collectionsFolder: "Folder where collections are saved:",
    storageDirHint: "When applied, katarina uses this folder. Current collections are not moved — to bring them, copy the files there.",
    network: "Network",
    timeoutSeconds: "Timeout (seconds):",
    noLimit: "0 = no limit",
    ignoreSsl: "Ignore TLS certificate errors (self-signed)",
    behavior: "Behavior",
    confirmDeleteOption: "Confirm before deleting",
    autoSaveOnSend: "Save automatically when sending",
    shortcuts: "Shortcuts",
    shortcutsHint: "Click a shortcut and press the new combination. Esc cancels.",
    restoreDefault: "Restore default",
    optionsApplyInstantly: "Options apply instantly.",
    pressCombination: "Press the combination…",

    // ---- menus ----
    newCollection: "New collection…",
    importCurl: "Import cURL…",
    newRequestHere: "New request here…",
    newFolderHere: "New folder here",
    moveToEllipsis: "Move to…",
    rootTop: "Root (top)",
    renameEllipsis: "Rename…",
    duplicate: "Duplicate",
    exportCode: "Export code…",

    // ---- paleta de comandos ----
    paletteGroupGlobal: "Global",
    paletteGroupContext: "Current context",
    newFolder: "New folder…",
    settingsEllipsis: "Settings…",
    manageEnvVariables: "Manage environment variables…",
    closeTab: "Close tab",
    reopenTab: "Reopen closed tab",
    saveRequest: "Save request",
    sendRequest: "Send request",
    moveSelected: "Move selected…",
    renameSelected: "Rename selected…",
    duplicateSelected: "Duplicate selected",

    // ---- atalhos ----
    shortcutSend: "Send request",
    shortcutNewRequest: "New request",
    shortcutCloseTab: "Close tab",
    shortcutSave: "Save request",
    shortcutPrevTab: "Previous tab",
    shortcutNextTab: "Next tab",
    shortcutReopenTab: "Reopen closed tab",
    shortcutPalette: "Command palette",
    shortcutFind: "Find in response"
};

// ---- mensagens parametrizadas ----

function variableRepeated(name) { return "Repeated variable: " + name; }
function unresolvedVariables(list) { return "Unresolved variables: " + list; }
function notFound(q) { return "Not found: " + q; }
function duplicateInCollection(name) { return "Repeated variable name in collection: " + name; }
function duplicateInRequest(name) { return "Repeated variable name in request: " + name; }
function duplicateInEnvironment(name) { return "Repeated variable name in environment: " + name; }
function collectionsNow(dir) { return "Collections now at " + dir; }
function savedTo(path) { return "Saved to ~/katarina-collections/" + path + ".json"; }
function curlNoUrl() { return "Couldn't find a URL in the command."; }
function willBeCreatedIn(folder) { return "Will be created in: " + folder; }
function rootFolder() { return "root"; }
function moveTo(name) { return "Move \"" + name + "\" to:"; }
function clearHistoryConfirm() { return "Clear all history?"; }
function deleteItemConfirm(name) {
    return "Delete \"" + name + "\"?\nThis erases from disk (recursively, if a folder).";
}
function deleteEnvConfirm(name) { return "Delete environment \"" + name + "\"?"; }
function nCollections(n) { return n + (n === 1 ? " collection" : " collections"); }
function restrictedTo(list) { return "restricted to: " + list; }
// "The request 'x' has unsaved changes." (kind: collection|environment|request)
function unsavedItem(name, kind) {
    var noun = kind === "collection" ? "collection" : (kind === "environment" ? "environment" : "request");
    return "The " + noun + " '" + name + "' has unsaved changes.";
}
// motivo de uma variável não resolver (vindo do backend por código)
function variableNote(code, collections) {
    if (code === "disabled") return t.disabled;
    if (code === "restricted") return restrictedTo((collections || []).join(", "));
    if (code === "undefined") return t.notDefined;
    return "";
}
// erro de rede do backend por código
function backendError(code, args) {
    args = args || [];
    if (code === "unresolved") return t.errorPrefix + unresolvedVariables((args[0] || []).join(", "));
    if (code === "invalidUrl") return t.errorPrefix + "Invalid URL";
    if (code === "fileOpen") return t.errorPrefix + "Couldn't open the file: " + args[0];
    if (code === "network") return t.errorPrefix + args[0];
    return t.errorPrefix + code;
}
