# Launchpad

Launchpad 是一款使用 SwiftUI 和 AppKit 构建的原生 macOS 应用启动器。它以全屏面板展示已安装的应用，支持搜索、排序和文件夹分组。

## 功能

- 扫描 `/Applications`、`/System/Applications` 和当前用户的 `~/Applications`。
- 按应用所在目录自动归类；目录中有多个应用时显示为文件夹。
- 搜索应用名称或路径，并按回车启动根页面中的第一个匹配应用。
- 拖动图标调整应用顺序，或将应用拖到其他应用、文件夹上创建或扩展分组。
- 打开文件夹查看其中的应用；手动分组可以重命名，也可以通过拖出应用来移除成员。
- 自动保存应用顺序和手动分组，重启后继续使用。

## 使用

启动 Launchpad 后，搜索框会自动获得焦点。点击应用图标即可启动应用；点击文件夹可进入文件夹。按 `Esc` 或点击背景可返回上一级，在根页面则关闭面板。

拖动图标可调整顺序。将一个应用拖到另一个应用或文件夹上可创建或扩展手动分组。手动分组名称可双击编辑，也可通过右键菜单选择“重命名分组”。在分组内将应用拖到“移出分组”区域，可将其移出分组。

搜索支持应用名称和路径。搜索时会过滤当前页面内容；根页面输入搜索词后按回车，可启动第一个匹配的应用。

## 环境要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本，以及 Xcode Command Line Tools

## 开发与检查

在项目根目录运行：

```sh
# 编译
swift build

# 执行原生逻辑检查
swift run LaunchpadCoreChecks

# 以调试配置运行应用
swift run LaunchpadApp
```

`LaunchpadCoreChecks` 是一个可执行检查程序，使用断言验证应用归类、搜索、分组、排序和持久化等核心逻辑。

## 构建 macOS 应用包

运行打包脚本：

```sh
./scripts/build-macos.sh
```

脚本以 Release 配置构建应用，并在 `dist/` 下生成 `LaunchpadApp.app` 和 `LaunchpadApp-mac-x64.zip`。可以直接打开应用包：

```sh
open dist/LaunchpadApp.app
```

## 项目结构

```text
Sources/
  LaunchpadApp/        SwiftUI 界面和 AppKit 应用入口
  LaunchpadCore/       应用扫描、分组、排序和持久化逻辑
  LaunchpadCoreChecks/ 核心逻辑检查程序
app-resources/         macOS 应用包的 Info.plist
scripts/               macOS 应用包构建脚本
Launchpad.icns         应用图标
Package.swift          Swift Package 定义
```

## 本地数据

应用将数据保存在：

```text
~/Library/Application Support/launchpadapp/
```

- `app-order.json`：根页面和各自动文件夹中的应用顺序。
- `app-groups.json`：手动分组的名称、所属目录及应用路径。

应用扫描已安装的应用，不会移动或修改这些应用本身。
