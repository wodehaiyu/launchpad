const {
    app,
    BrowserWindow,
    ipcMain,
    screen
} = require('electron');

const path = require('path');
const fs = require('fs');
const { pathToFileURL } = require('url');
const {
    spawn
} = require('child_process');


// ============================================================
// 路径
// ============================================================

const ICON_CACHE_DIR =
    path.join(
        app.getPath('userData'),
        'icon-cache'
    );

const APP_CACHE_FILE =
    path.join(
        app.getPath('userData'),
        'apps.json'
    );

const APP_ORDER_FILE =
    path.join(
        app.getPath('userData'),
        'app-order.json'
    );

const APP_GROUPS_FILE =
    path.join(
        app.getPath('userData'),
        'app-groups.json'
    );

const ICON_HELPER =
    path.join(
        __dirname,
        'icon-helper',
        'icon-helper'
    );


// ============================================================
// 全局
// ============================================================

let mainWindow = null;

let iconHelper = null;

const iconQueue = [];

let iconProcessing = false;

let activeIconBatchSize = 0;

const ICON_BATCH_SIZE = 8;
const ICON_CSS_SIZE = 86;

let iconQueuePaths =
    new Set();


function getTargetIconSize() {

    const display = screen.getDisplayNearestPoint(
        screen.getCursorScreenPoint()
    );

    return Math.round(
        ICON_CSS_SIZE * display.scaleFactor
    );

}


// ============================================================
// 创建缓存目录
// ============================================================

function ensureCacheDir() {

    if (
        !fs.existsSync(
            ICON_CACHE_DIR
        )
    ) {

        fs.mkdirSync(
            ICON_CACHE_DIR,
            {
                recursive: true
            }
        );

    }

}


// ============================================================
// App 缓存
// ============================================================

async function saveAppCache(
    apps
) {

    try {

        const cachedApps = apps.map(appInfo => {
            const { icon, ...cachedApp } = appInfo;
            return cachedApp;
        });

        await fs.promises.writeFile(
            APP_CACHE_FILE,
            JSON.stringify(
                cachedApps,
                null,
                2
            ),
            'utf8'
        );

    } catch (error) {

        console.error(
            '保存 App 缓存失败:',
            error
        );

    }

}


function loadAppCache() {

    try {

        if (
            !fs.existsSync(
                APP_CACHE_FILE
            )
        ) {

            return [];

        }

        const data =
            fs.readFileSync(
                APP_CACHE_FILE,
                'utf8'
            );

        return JSON.parse(
            data
        );

    } catch (error) {

        console.error(
            '读取 App 缓存失败:',
            error
        );

        return [];

    }

}


function loadAppOrderData() {

    try {

        const data = fs.readFileSync(
            APP_ORDER_FILE,
            'utf8'
        );
        const appOrders = JSON.parse(data);

        if (appOrders && typeof appOrders === 'object' && !Array.isArray(appOrders)) {
            return appOrders;
        }

    } catch (error) {

        return {};

    }

    return {};

}


function loadAppGroups() {

    try {

        const groups = JSON.parse(
            fs.readFileSync(
                APP_GROUPS_FILE,
                'utf8'
            )
        );

        return Array.isArray(groups) ? groups : [];

    } catch (error) {

        return [];

    }

}


function getAppOrderKey(context) {

    return typeof context === 'string' && context
        ? `folder:${context}`
        : 'root';

}


// ============================================================
// Icon Cache
// ============================================================

function getIconCachePath(
    appPath
) {

    const safeName =
        Buffer
            .from(appPath)
            .toString('base64')
            .replace(
                /[^a-zA-Z0-9]/g,
                ''
            );

    return path.join(
        ICON_CACHE_DIR,
        safeName + '.png'
    );

}


async function getCachedIconUrl(
    appPath
) {

    let fileHandle = null;

    try {

        const cachePath = getIconCachePath(appPath);
        fileHandle = await fs.promises.open(cachePath, 'r');

        const header = Buffer.alloc(24);
        const { bytesRead } = await fileHandle.read(
            header,
            0,
            header.length,
            0
        );
        const stats = await fileHandle.stat();

        if (bytesRead < header.length) {
            return null;
        }

        const width = header.readUInt32BE(16);
        const height = header.readUInt32BE(20);
        const iconUrl = pathToFileURL(cachePath);
        iconUrl.searchParams.set(
            'v',
            `${stats.mtimeMs}-${stats.size}`
        );

        const targetSize = getTargetIconSize();

        if (width !== targetSize || height !== targetSize) {
            requestIcon(appPath);
        }

        return iconUrl.href;

    } catch (error) {

        return null;

    } finally {

        if (fileHandle) {
            await fileHandle.close().catch(() => {});
        }

    }

}


// ============================================================
// 扫描 App
// ============================================================

function getBundleLocalizedApplicationNames(apps) {

    return new Promise(resolve => {

        const names = new Map();
        const helper = spawn(
            ICON_HELPER,
            ['--localized-names'],
            {
                stdio: [
                    'pipe',
                    'pipe',
                    'ignore'
                ]
            }
        );

        let buffer = '';

        function readNameLines() {

            let index;

            while (
                (index = buffer.indexOf('\n')) !== -1
            ) {

                const line = buffer.slice(0, index).trim();
                buffer = buffer.slice(index + 1);

                if (!line) {
                    continue;
                }

                try {

                    const result = JSON.parse(line);

                    if (result.path && result.name) {
                        names.set(result.path, result.name);
                    }

                } catch (error) {

                    console.error(
                        'Localized Name JSON 错误:',
                        error
                    );

                }

            }

        }

        helper.stdout.setEncoding('utf8');
        helper.stdout.on('data', data => {
            buffer += data;
            readNameLines();
        });

        helper.on('error', () => resolve(names));
        helper.on('close', () => {

            readNameLines();
            resolve(names);

        });

        helper.stdin.on('error', () => resolve(names));
        helper.stdin.end(
            apps.map(appInfo => JSON.stringify({ path: appInfo.path })).join('\n') + '\n'
        );

    });

}


function getFinderLocalizedApplicationNames(apps) {

    return new Promise(resolve => {

        const names = new Map();

        if (!apps.length) {
            resolve(names);
            return;
        }

        const script = [
            'on run argv',
            'set outputNames to {}',
            'tell application "Finder"',
            'repeat with itemPath in argv',
            'set filePath to contents of itemPath',
            'try',
            'set displayName to displayed name of (POSIX file filePath as alias)',
            'on error',
            'set displayName to ""',
            'end try',
            'set end of outputNames to displayName',
            'end repeat',
            'end tell',
            'set text item delimiters to linefeed',
            'return outputNames as text',
            'end run'
        ].join('\n');

        let output = '';
        let timeoutId = null;
        let settled = false;

        const helper = spawn(
            '/usr/bin/osascript',
            [
                '-e',
                script,
                ...apps.map(appInfo => appInfo.path)
            ],
            {
                stdio: [
                    'ignore',
                    'pipe',
                    'ignore'
                ]
            }
        );

        function finish() {

            if (settled) {
                return;
            }

            settled = true;

            if (timeoutId) {
                clearTimeout(timeoutId);
            }

            const displayNames = output
                .replace(/\r/g, '')
                .replace(/\n$/, '')
                .split('\n');

            apps.forEach((appInfo, index) => {

                const name = displayNames[index]?.trim();

                if (name) {
                    names.set(appInfo.path, name);
                }

            });

            resolve(names);

        }

        helper.stdout.setEncoding('utf8');
        helper.stdout.on('data', data => {
            output += data;
        });
        helper.on('error', finish);
        helper.on('close', finish);

        timeoutId = setTimeout(() => {
            helper.kill();
            finish();
        }, 8000);

    });

}


function getLocalizedApplicationNames(apps) {

    return getFinderLocalizedApplicationNames(apps).then(finderNames => {

        if (finderNames.size === apps.length) {
            return finderNames;
        }

        return getBundleLocalizedApplicationNames(apps).then(bundleNames => {

            for (const [appPath, name] of bundleNames) {

                if (!finderNames.has(appPath)) {
                    finderNames.set(appPath, name);
                }

            }

            return finderNames;

        });

    });

}

async function scanApplications() {

    const directories = [

        '/Applications',

        '/System/Applications',

        path.join(
            app.getPath(
                'home'
            ),
            'Applications'
        )

    ];

    const apps = [];

    const seen =
        new Set();

    async function walkDirectory(directory) {

        let entries;

        try {

            entries = await fs.promises.readdir(
                directory,
                {
                    withFileTypes: true
                }
            );

        } catch (error) {

            return;

        }


        for (
            const entry
            of entries
        ) {

            const entryPath =
                path.join(
                    directory,
                    entry.name
                );

            if (
                entry.isDirectory()
            ) {

                if (
                    entry.name.endsWith(
                        '.app'
                    )
                ) {

                    if (
                        seen.has(
                            entryPath
                        )
                    ) {

                        continue;

                    }

                    seen.add(
                        entryPath
                    );

                    const icon =
                        await getCachedIconUrl(
                            entryPath
                        );

                    apps.push({

                        name:
                            entry.name.replace(
                                /\.app$/,
                                ''
                            ),

                        path:
                            entryPath,

                        icon:
                            icon

                    });

                    continue;

                }

                await walkDirectory(
                    entryPath
                );

            }

        }

    }


    for (
        const directory
        of directories
    ) {

        await walkDirectory(
            directory
        );

    }


    const localizedNames = await getLocalizedApplicationNames(apps);

    for (const appInfo of apps) {

        appInfo.name = localizedNames.get(appInfo.path) || appInfo.name;

    }


    apps.sort(
        (a, b) =>
            a.name.localeCompare(
                b.name
            )
    );


    return apps;

}


// ============================================================
// 获取 Applications
// ============================================================

async function getApplications() {

    const apps = await scanApplications();


    await saveAppCache(
        apps
    );


    return apps;

}


function queueMissingIcons(apps) {

    for (const appInfo of apps) {

        if (!appInfo.icon) {

            requestIcon(appInfo.path);

        }

    }

}


function hydrateCachedIcons(apps) {

    for (const appInfo of apps) {

        getCachedIconUrl(
            appInfo.path
        ).then(cachedIconUrl => {

            if (cachedIconUrl) {

                appInfo.icon = cachedIconUrl;

                if (mainWindow && !mainWindow.isDestroyed()) {

                    mainWindow.webContents.send(
                        'icon-loaded',
                        {
                            path: appInfo.path,
                            icon: cachedIconUrl,
                        }
                    );

                }

                return;

            }

            if (!appInfo.icon) {

                requestIcon(appInfo.path);

            }

        });

    }

}


async function refreshApplicationsInBackground() {

    try {

        const freshApps = await getApplications();
        queueMissingIcons(freshApps);

        if (mainWindow && !mainWindow.isDestroyed()) {

            mainWindow.webContents.send(
                'applications-updated',
                freshApps
            );

        }

    } catch (error) {

        console.error(
            '刷新 App 列表失败:',
            error
        );

    }

}


// ============================================================
// Swift Icon Helper
// ============================================================

function startIconHelper() {

    if (
        iconHelper
    ) {

        return;

    }


    if (
        !fs.existsSync(
            ICON_HELPER
        )
    ) {

        console.error(
            '找不到 icon-helper:',
            ICON_HELPER
        );

        return;

    }


    iconHelper =
        spawn(
            ICON_HELPER,
            [],
            {
                stdio: [
                    'pipe',
                    'pipe',
                    'pipe'
                ]
            }
        );


    iconHelper.on(
        'error',
        error => {

            console.error(
                'Icon Helper 启动失败:',
                error
            );

            iconHelper = null;

            setTimeout(
                () => {

                    if (
                        !app.isQuitting
                    ) {

                        startIconHelper();

                    }

                },
                150
            );

        }
    );


    let buffer = '';


    iconHelper.stdout.on(
        'data',
        data => {

            buffer +=
                data.toString();


            let index;


            while (
                (
                    index =
                        buffer.indexOf(
                            '\n'
                        )
                ) !== -1
            ) {

                const line =
                    buffer
                        .slice(
                            0,
                            index
                        )
                        .trim();


                buffer =
                    buffer.slice(
                        index + 1
                    );


                if (
                    !line
                ) {

                    continue;

                }


                try {

                    const result =
                        JSON.parse(
                            line
                        );


                    handleIconResult(
                        result.path,
                        result.success
                    );

                } catch (error) {

                    console.error(
                        'Icon Helper JSON 错误:',
                        error
                    );

                }

            }

        }
    );


    iconHelper.stderr.on(
        'data',
        data => {

            console.error(
                'Icon Helper:',
                data.toString()
            );

        }
    );


    iconHelper.on(
        'exit',
        (code, signal) => {

            console.warn(
                'Icon Helper 已退出:',
                {
                    code,
                    signal
                }
            );

            iconHelper = null;
            iconProcessing = false;

            if (
                !app.isQuitting
            ) {

                setTimeout(
                    () => {

                        startIconHelper();

                    },
                    150
                );

            }

        }
    );

}


// ============================================================
// Icon 返回
// ============================================================

function handleIconResult(
    appPath,
    succeeded
) {

    iconQueuePaths.delete(
        appPath
    );


    if (succeeded) {

        getCachedIconUrl(appPath).then(iconUrl => {

            if (
                iconUrl &&
                mainWindow &&
                !mainWindow.isDestroyed()
            ) {

                mainWindow.webContents.send(
                    'icon-loaded',
                    {
                        path: appPath,
                        icon: iconUrl,
                    }
                );

            }

        });

    }


    activeIconBatchSize -= 1;

    if (
        activeIconBatchSize <= 0
    ) {

        activeIconBatchSize = 0;
        iconProcessing = false;

    }

    processNextIcon();

}


// ============================================================
// 请求 Icon
// ============================================================

function requestIcon(
    appPath
) {

    if (
        iconQueuePaths.has(
            appPath
        )
    ) {

        return;

    }


    iconQueue.push(
        appPath
    );

    iconQueuePaths.add(
        appPath
    );


    processNextIcon();

}


// ============================================================
// Icon Queue
// ============================================================

function processNextIcon() {

    if (
        iconProcessing
    ) {

        return;

    }


    if (
        iconQueue.length === 0
    ) {

        return;

    }


    if (
        !iconHelper
    ) {

        startIconHelper();

    }


    if (
        !iconHelper
    ) {

        return;

    }


    const batch = [];

    while (
        batch.length < ICON_BATCH_SIZE &&
        iconQueue.length > 0
    ) {

        batch.push(
            iconQueue.shift()
        );

    }

    if (
        batch.length === 0
    ) {

        return;

    }


    iconProcessing = true;
    activeIconBatchSize += batch.length;


    try {

        const requests = batch.map(appPath => JSON.stringify({
            path: appPath,
            cachePath: getIconCachePath(appPath),
            pixels: getTargetIconSize(),
        }));

        iconHelper.stdin.write(
            requests.join('\n') + '\n'
        );

    } catch (error) {

        iconProcessing = false;
        activeIconBatchSize = 0;

        for (
            const appPath
            of batch
        ) {

            iconQueuePaths.delete(
                appPath
            );

            iconQueue.unshift(
                appPath
            );

        }

        processNextIcon();

    }

}


// ============================================================
// 创建窗口
// ============================================================

function createWindow() {

    mainWindow =
        new BrowserWindow({

            x: 0,
            y: 0,

            width: 1100,
            height: 750,

            backgroundColor:
                '#00000000',

            frame: false,

            transparent: true,

            fullscreen: false,

            resizable: false,

            movable: false,

            minimizable: false,

            maximizable: false,

            closable: true,

            show: false,

            webPreferences: {

                preload:
                    path.join(
                        __dirname,
                        'renderer.js'
                    ),

                contextIsolation:
                    true,

                nodeIntegration:
                    false

            }

        });


    // ========================================================
    // 当前显示器完整区域
    // ========================================================

    const display =
        screen.getDisplayNearestPoint(
            screen.getCursorScreenPoint()
        );


    mainWindow.setBounds(
        display.bounds
    );


    // 禁止出现 macOS 原生全屏
    mainWindow.setFullScreenable(
        false
    );


    mainWindow.loadFile(
        path.join(
            __dirname,
            'index.html'
        )
    );


    mainWindow.webContents.once(
        'did-finish-load',
        () => {

            console.log(
                'Launchpad 页面加载完成'
            );

        }
    );


    mainWindow.once(
        'ready-to-show',
        () => {

            mainWindow.show();
            mainWindow.focus();

        }
    );


    // 用户点击关闭按钮时
    // 不真正退出程序
    mainWindow.on(
        'close',
        event => {

            if (
                !app.isQuitting
            ) {

                event.preventDefault();

                hideLaunchpad();

            }

        }
    );

}


// ============================================================
// 显示 Launchpad
// ============================================================

function showLaunchpad() {

    if (
        !mainWindow ||
        mainWindow.isDestroyed()
    ) {

        return;

    }


    const display =
        screen.getDisplayNearestPoint(
            screen.getCursorScreenPoint()
        );


    const currentBounds = mainWindow.getBounds();
    const targetBounds = display.bounds;

    if (
        currentBounds.x !== targetBounds.x ||
        currentBounds.y !== targetBounds.y ||
        currentBounds.width !== targetBounds.width ||
        currentBounds.height !== targetBounds.height
    ) {

        mainWindow.setBounds(
            targetBounds
        );

    }


    mainWindow.webContents.send(
        'launchpad-show'
    );

}


// ============================================================
// 隐藏 Launchpad
// ============================================================

function hideLaunchpad() {

    if (
        !mainWindow ||
        mainWindow.isDestroyed()
    ) {

        return;

    }


    mainWindow.webContents.send(
        'launchpad-hide'
    );

    mainWindow.hide();

}


// ============================================================
// IPC
// ============================================================

ipcMain.handle(
    'get-app-groups',
    () => loadAppGroups()
);


ipcMain.handle(
    'save-app-groups',
    async (_event, groups) => {

        if (!Array.isArray(groups)) {
            return false;
        }

        const sanitizedGroups = groups
            .filter(group =>
                group &&
                typeof group.id === 'string' &&
                typeof group.name === 'string' &&
                (group.context === null || typeof group.context === 'string') &&
                Array.isArray(group.appPaths)
            )
            .map(group => ({
                id: group.id.slice(0, 128),
                name: group.name.trim().slice(0, 80) || '文件夹',
                context: group.context,
                appPaths: [...new Set(
                    group.appPaths.filter(appPath =>
                        typeof appPath === 'string' &&
                        appPath.length > 0 &&
                        appPath.length <= 4096
                    )
                )].slice(0, 256),
            }))
            .filter(group => group.id && group.appPaths.length >= 2)
            .slice(0, 1024);

        try {

            await fs.promises.writeFile(
                APP_GROUPS_FILE,
                JSON.stringify(sanitizedGroups, null, 2),
                'utf8'
            );

            return true;

        } catch (error) {

            console.error(
                '保存 App 分组失败:',
                error
            );

            return false;

        }

    }
);

ipcMain.handle(
    'get-app-order',
    (_event, context) => {

        const appOrders = loadAppOrderData();
        const order = appOrders[getAppOrderKey(context)];

        return Array.isArray(order) ? order : [];

    }
);


ipcMain.handle(
    'save-app-order',
    async (_event, context, orderedPaths) => {

        if (!Array.isArray(orderedPaths)) {
            return false;
        }

        const appOrders = loadAppOrderData();
        const uniquePaths = [...new Set(
            orderedPaths.filter(appPath =>
                typeof appPath === 'string' &&
                appPath.length > 0 &&
                appPath.length <= 4096
            )
        )].slice(0, 4096);

        appOrders[getAppOrderKey(context)] = uniquePaths;

        try {

            await fs.promises.writeFile(
                APP_ORDER_FILE,
                JSON.stringify(appOrders, null, 2),
                'utf8'
            );

            return true;

        } catch (error) {

            console.error(
                '保存 App 排序失败:',
                error
            );

            return false;

        }

    }
);

ipcMain.handle(
    'get-applications',
    async () => {

        const cachedApps = loadAppCache();

        if (cachedApps.length) {

            const apps = cachedApps.map(appInfo => ({ ...appInfo }));

            saveAppCache(cachedApps);
            setImmediate(() => hydrateCachedIcons(apps));
            setTimeout(refreshApplicationsInBackground, 300);

            return apps;

        }

        const apps = await getApplications();
        queueMissingIcons(apps);
        return apps;

    }
);


ipcMain.handle(
    'get-app-icon',
    async (
        event,
        appPath
    ) => {

        const cachedUrl = await getCachedIconUrl(appPath);


        if (
            cachedUrl
        ) {

            return cachedUrl;

        }


        requestIcon(
            appPath
        );


        return null;

    }
);


ipcMain.handle(
    'launch-application',
    (
        event,
        appPath
    ) => {

        hideLaunchpad();


        spawn(
            'open',
            [appPath],
            {
                detached: true,
                stdio: 'ignore'
            }
        ).unref();

    }
);


ipcMain.on(
    'hide-launchpad',
    () => {

        hideLaunchpad();

    }
);


ipcMain.on(
    'launchpad-ready-to-show',
    () => {

        if (
            !mainWindow ||
            mainWindow.isDestroyed()
        ) {

            return;

        }

        mainWindow.show();
        mainWindow.focus();

    }
);


// ============================================================
// App 生命周期
// ============================================================

app.whenReady().then(
    () => {

        ensureCacheDir();

        createWindow();


        setImmediate(
            () => {

                startIconHelper();

                processNextIcon();

            }
        );

    }
);


app.on(
    'activate',
    () => {

        showLaunchpad();

    }
);


// 不因为窗口隐藏而退出
app.on(
    'window-all-closed',
    event => {

        event.preventDefault();

    }
);


// ============================================================
// 退出
// ============================================================

app.on(
    'before-quit',
    () => {

        app.isQuitting = true;


        if (
            iconHelper
        ) {

            iconHelper.kill();

            iconHelper = null;

        }

    }
);