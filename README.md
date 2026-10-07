# 享联 ShareLink

> 同一局域网内设备自动互现，共享内容即取即用，无需上传云端。

**享联** 是一款基于 Flutter 的跨设备局域网工具。开启「接受别人连接」后，同一网络下的其他设备可以发现你；对方输入连接密码后，即可浏览你共享的相册、音乐、文档、下载目录或自定义文件夹，并在本机**在线预览或下载**文件。所有数据仅在局域网内点对点传输，不经过任何中转服务器。

- **当前版本**：1.0.0
- **已完成构建与验证的平台**：Windows x64、Android arm64
- **保留工程目录但尚未验证**：iOS、macOS、Linux、Web

---

## 1. 运行原理

| 环节 | 实现方式 |
| --- | --- |
| 设备发现 | **UDP 广播**（`RawDatagramSocket`，端口 `38381`），周期性发送 beacon；在热点/AP 环境下额外向已发现的在线设备**单播**，避免 AP 不转发广播导致设备掉线 |
| 连接与鉴权 | **WebSocket** 直连对端 `38381` 端口，提交 6 位连接密码（仅字母与数字）校验；密码错误或对端拒绝时给出明确提示 |
| 目录与文件访问 | 被连接方内置 **HTTP 文件服务**（同一端口）：`/filelist` 返回目录列表、`/file?path=` 返回文件流（支持 Range，可拖动进度）、`/thumb?path=` 返回缩略图 |
| 在线预览 | 图片、视频、音频、文本直接以网络 URI 预览播放，**不落盘**；「用系统打开」才会下载一份临时副本 |

---

## 2. 功能说明

### 首页 · 设备发现
- 自动搜索同一网络内开启了连接功能的设备，搜索过程中显示加载状态。
- 分别展示「附近设备」与「已连接过的设备」，标注在线/离线状态。
- 点击设备进入连接流程，输入连接密码后建立连接；支持自动重连、手动断开与移除记录。
- 主动断开后，该设备在「已连接过」列表中的在线状态保持不变。
- 附近设备全部离线时自动重新搜索；两步设备均无在线项时展示空状态。

### 文件 · 浏览与预览
- 浏览已连接设备共享的内容，支持目录层级导航与远程列表刷新。
- **分类与筛选**：内置图片 / 视频 / 音频 / 文本 / Word / PPT / 表格 / PDF / 压缩包等分类，并可自定义分类（名称、图标、匹配后缀，或直接「全选」）。
- **排序与布局**：按文件名 / 时间轴 / 大小排序；单列或双列布局；分类栏支持下拉框与横向列表两种展现方式。
- **预览能力**：
  - 图片：双指缩放、拖动，支持旋转（旋转后平移边界同步适配）。
  - 视频：播放/暂停、拖动进度、倍速、全屏；左侧上下滑动调亮度、右侧上下滑动调系统音量（退出时恢复）。
  - 音频：后台播放控制与封面展示。
  - 文本 / 代码：直接阅读。
  - 不支持的格式提供「用系统打开」入口。
- **TS 分片处理**：视频目录中的 `.ts` 分片不会单独作为条目展示，而是先拼接并校验（MPEG-TS 结构 + 静音起播探测）通过后合成为一个可播放项。
- **缩略图与时长**：图片/视频封面与媒体时长本地缓存，滚动和切换标签页时保持不闪烁。
- **文件详情面板**：长按/右键显示，展示名称、大小、类型、时长等信息，并提供下载。

### 设置
- **外观设置**：深色模式（跟随系统 / 浅色 / 深色）。
- **连接设置**：开启「接受别人连接」、设置与校验连接密码。
- **共享设置**：选择对外共享的来源——相册 / 音乐 / 文档 / 下载 / 自定义文件夹（可增删多个文件夹，带运行时权限引导）。
- **缓存设置**：查看远程文件缓存占用，一键清空。
- **关于软件**：应用名称、版本号、设备型号。

### 平台适配
- **桌面端（Windows）**：左侧玻璃导航栏；自定义标题栏；窗口关闭按钮最小化到系统托盘，仅通过托盘右键菜单退出。
- **移动端（Android）**：底部导航栏；前台服务常驻，锁屏或后台时仍能维持设备发现（回到前台时自动重启发现服务）；所有提示使用根级 Overlay Toast，按类型展示不同图标。
- **统一视觉**：深浅色主题、玻璃拟态与液态玻璃组件、统一的色板与字符串常量管理。

---

## 3. 技术栈与依赖

- **框架**：Flutter 3.44.7（stable）/ Dart 3.12.2，SDK 约束 `^3.12.2`
- **状态管理**：`flutter_riverpod`（NotifierProvider 为主）
- **通信**：`web_socket_channel`（连接与事件）、`RawDatagramSocket`（UDP 发现，Dart 内置）
- **媒体**：`media_kit` + `media_kit_video`（各平台原生库，替代 `video_player` / `just_audio`）、`fc_native_video_thumbnail`（视频缩略图）、`media_metadata`（媒体时长与元数据）、`screen_brightness`、`volume_controller`
- **图片**：`photo_view`（缩放查看）、`cached_network_image` + `flutter_cache_manager`（磁盘持久化缓存）
- **文件与权限**：`file_picker`、`permission_handler`、`open_filex`、`path_provider`、`url_launcher`
- **桌面端**：`window_manager`（无边框窗口与自定义标题栏）、`tray_manager`（系统托盘）
- **存储与系统信息**：`shared_preferences`、`device_info_plus`、`network_info_plus`
- **后台与提示**：`flutter_background_service`（Android 前台服务）、`unified_popups`（Toast / Loading / Confirm / Sheet）
- **日志**：`logger`
- **开发依赖**：`flutter_lints`

---

## 4. 目录结构

```
share_link/
├── lib/
│   ├── main.dart                 # 应用入口
│   ├── app.dart                  # 应用外壳（移动端底部导航 / 桌面端侧边栏）
│   ├── core/
│   │   ├── constants/            # 颜色、字符串常量（所有 UI 文案集中于此）
│   │   ├── providers/            # 全局 Provider（主题、剪贴板开关等）
│   │   ├── services/             # 缓存目录、图片缓存、后台服务、托盘、设备信息、网络平台
│   │   └── utils/                # 平台判断、网络工具、权限、日志、设备图标、UUID
│   ├── features/
│   │   ├── device_discovery/     # 设备发现与连接
│   │   │   ├── models/           # Device
│   │   │   ├── providers/        # 设备列表状态
│   │   │   ├── services/         # discovery_service(UDP)、connection_server、connection_client、device_service、已连接记录
│   │   │   ├── views/            # 首页
│   │   │   └── widgets/          # 连接/权限/确认对话框、设备项、搜索动画
│   │   ├── file_browser/         # 文件浏览与预览
│   │   │   ├── models/           # FileItem、FileCategory
│   │   │   ├── providers/        # 文件列表、分类、排序、筛选状态
│   │   │   ├── services/         # 本地扫描与索引、远程访问、下载、缓存、媒体时长
│   │   │   ├── views/            # 文件页、预览页
│   │   │   └── widgets/          # 列表项、分类表单、图片/视频/音频预览器、详情面板
│   │   ├── settings/             # 设置页与共享内容管理
│   │   └── clipboard_sync/       # 剪贴板模块（当前未接入导航，功能未开放）
│   └── shared/
│       ├── themes/               # 亮色/暗色主题
│       └── widgets/              # 玻璃拟态组件、Toast、窗口控件等通用组件
├── android/  ios/  windows/  macos/  linux/  web/   # 各平台工程
├── windows/installer/            # Windows 安装向导源码（见下）
├── assets/                       # 应用图标等资源
├── dist/                         # 打包产物输出目录
└── pubspec.yaml
```

---

## 5. 构建与打包

```bash
# 拉取依赖
flutter pub get

# Windows 桌面版（Release）
flutter build windows --release --split-debug-info=build\symbols\windows

# Android（仅 arm64-v8a）
flutter build apk --release --target-platform=android-arm64
```

Windows 安装包不是用 Inno Setup / NSIS 制作的，而是用系统自带的 `csc` 编译了一个 WinForms 安装向导（含应用图标、名称、版本信息、安装路径选择、桌面/开始菜单快捷方式、进度条与自带卸载器），把应用文件与解压引擎内嵌为资源：

```powershell
rc  /nologo /fo dist\_setup.res windows\installer\ShareLinkSetup.rc
csc /target:winexe /codepage:65001 /main:ShareLinkSetup.Program `
    /out:dist\ShareLink-Setup-x64.exe /win32res:dist\_setup.res `
    /resource:dist\payload.7z,PAYLOAD /resource:dist\7zr.exe,SEVENZR `
    /resource:dist\Uninstall.exe,UNINSTALLER /resource:assets\app_icon.png,APPICONPNG `
    /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll `
    windows\installer\ShareLinkSetup.cs windows\installer\ShareLinkUninstaller.cs
```

构建产物统一输出到 `dist/`，包括安装向导 exe、Windows 便携 7z、Android APK 及其压缩包。

> 备注：在 Windows 上首次执行 `flutter pub get` 需要插件符号链接权限（开发者模式）。若无法开启开发者模式，可用目录联接（junction）替代，效果等价。

---

## 6. 许可协议（允许自由使用，禁止商业使用）

本项目采用 **PolyForm Noncommercial License 1.0.0（非商业许可）**。

> 请注意：这是**源码公开**许可，而非 OSI 认可的开源许可——它明确禁止商业使用。

### ✅ 允许（免费，无需申请授权）
- 个人学习、研究、自用，以及任何**非商业目的**的安装与使用；
- 复制、修改源代码，并在**非商业**前提下分发原版或修改版（须保留本协议与版权声明）；
- 在非商业项目中集成、二次开发。

### ❌ 禁止
- 任何形式的**商业使用**，包括但不限于：售卖本软件或其修改版、用于公司/组织的商业运营、作为付费产品或付费服务的一部分提供、以本软件开展有偿服务、通过广告或增值功能盈利；
- 移除或篡改版权声明与许可信息后再分发；
- 以本项目名义进行商业宣传，或暗示获得官方授权、合作。

### 说明
- 如需商业授权，请与作者联系并取得书面许可。
- 用户可以自由使用本工具访问自己拥有合法权利的文件。**工具本身不提供、不托管、不传播任何第三方内容**；所访问数据的版权与合法性由使用者自行负责。
- 本软件按「现状」提供，不附带任何明示或暗示的担保。因使用本软件造成的数据丢失、泄露或其他损失，由使用者自行承担。

---

*Made with ❤️ for seamless connectivity.*