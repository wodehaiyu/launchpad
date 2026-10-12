const {
    contextBridge,
    ipcRenderer
} = require('electron');


// ============================================================
// 暴露给网页
// ============================================================

contextBridge.exposeInMainWorld(
    'launchpad',
    {

        getApplications:
            () =>
                ipcRenderer.invoke(
                    'get-applications'
                ),


        getAppOrder:
            context =>
                ipcRenderer.invoke(
                    'get-app-order',
                    context
                ),


        saveAppOrder:
            (context, orderedPaths) =>
                ipcRenderer.invoke(
                    'save-app-order',
                    context,
                    orderedPaths
                ),


        getAppGroups:
            () =>
                ipcRenderer.invoke(
                    'get-app-groups'
                ),


        saveAppGroups:
            groups =>
                ipcRenderer.invoke(
                    'save-app-groups',
                    groups
                ),


        getAppIcon:
            (
                appPath
            ) =>
                ipcRenderer.invoke(
                    'get-app-icon',
                    appPath
                ),


        launchApplication:
            (
                appPath
            ) =>
                ipcRenderer.invoke(
                    'launch-application',
                    appPath
                ),


        hide:
            () =>
                ipcRenderer.send(
                    'hide-launchpad'
                )

    }
);


// ============================================================
// Icon 加载完成
// ============================================================

ipcRenderer.on(
    'applications-updated',
    (_event, apps) => {

        window.dispatchEvent(
            new CustomEvent(
                'launchpad-applications-updated',
                {
                    detail: apps
                }
            )
        );

    }
);

ipcRenderer.on(
    'icon-loaded',
    (
        event,
        data
    ) => {

        window.dispatchEvent(
            new CustomEvent(
                'launchpad-icon-loaded',
                {
                    detail:
                        data
                }
            )
        );

    }
);


// ============================================================
// Launchpad 显示
// ============================================================

ipcRenderer.on(
    'launchpad-show',
    () => {

        document.body.classList.remove(
            'launchpad-hidden'
        );

        document.body.classList.add(
            'launchpad-visible'
        );

        const isVisible =
            window.getComputedStyle(document.body).opacity === '1';

        if (isVisible) {
            ipcRenderer.send(
                'launchpad-ready-to-show'
            );
        }

    }
);


// ============================================================
// Launchpad 隐藏
// ============================================================

ipcRenderer.on(
    'launchpad-hide',
    () => {

        document.body.classList.remove(
            'launchpad-visible'
        );

        document.body.classList.add(
            'launchpad-hidden'
        );

    }
);