以下是为“享联-ShareLink”项目准备的完整 `README.md` 文档，涵盖了从项目初始化到技术选型、目录规划及功能定义的全部内容。

---

# 享联-ShareLink

> 跨设备无缝互联，文件即取即用，剪贴板跨屏同步。

---

## 1. 项目创建命令

使用 Flutter 创建项目（确保已安装 Flutter SDK）：

```bash
# 创建项目（包名建议使用 com.yourcompany.sharelink）
flutter create share_link

# 进入项目目录
cd share_link

# 查看当前 Flutter 版本及设备
flutter doctor

# 运行项目（默认调试）
flutter run
```

---

## 2. 第三方库选型

| 功能模块               | 使用的库                                    | 说明                                                         |
| ---------------------- | ------------------------------------------- | ------------------------------------------------------------ |
| **局域网文件访问 (SMB)** | `dart_smb2`                                 | Dart 实现的 SMB2/3 客户端，支持流式读取，无需下载到本地。     |
| **剪贴板同步**         | `clipboard_watcher`<br/>`flutter_share_plus` | 监听本地剪贴板变化；跨设备传输剪贴板内容。                     |
| **网络通信基础**       | `socket_io_client` 或 `web_socket_channel`   | 用于设备发现及剪贴板数据的实时同步（WebSocket / Socket.IO）。 |
| **本地网络服务发现**   | `network_info_plus`<br/>`multicast_dns`     | 获取本机 IP，通过 mDNS 进行局域网内设备自动发现。             |
| **状态管理**           | `provider` 或 `riverpod`                    | 推荐 `riverpod`，更轻量且易于测试。                           |
| **本地存储**           | `shared_preferences`                        | 保存用户配置（如记住的共享文件夹、设备列表）。                |
| **文件/媒体浏览 UI**   | `file_picker`（可选）                       | 用于选择本地文件夹，非必须。                                 |
| **后台运行（安卓）**   | `flutter_background_service`                | 让剪贴板监听服务常驻后台（需谨慎优化）。                      |
| **日志记录**           | `logger`                                    | 便于调试和问题追踪。                                         |

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  dart_smb2: ^0.2.0          # SMB 客户端
  clipboard_watcher: ^0.1.0   # 剪贴板监听
  web_socket_channel: ^2.4.0  # WebSocket
  network_info_plus: ^4.0.0   # 网络信息
  multicast_dns: ^0.3.0       # mDNS 服务发现
  riverpod: ^2.3.0            # 状态管理
  shared_preferences: ^2.0.0  # 本地存储
  flutter_background_service: ^4.0.0  # 后台服务
  logger: ^1.0.0              # 日志
```

---

## 3. 项目文件目录结构

采用功能模块化分层，保持清晰：

```
sharelink/
├── android/                     # Android 原生代码（自动生成）
├── ios/                         # iOS 原生代码
├── windows/                     # Windows 桌面支持
├── lib/
│   ├── main.dart                # 应用入口
│   ├── app.dart                 # 应用根Widget（主题、路由）
│   ├── core/                    # 核心基础层
│   │   ├── constants/           # 常量（颜色、字符串、枚举）
│   │   ├── utils/               # 工具类（日志、网络检测）
│   │   ├── services/            # 全局服务（后台任务、通知）
│   │   └── providers/           # 全局Provider（Riverpod）
│   ├── features/                # 功能模块（按领域划分）
│   │   ├── file_browser/        # 文件浏览功能
│   │   │   ├── models/          # 文件/文件夹实体
│   │   │   ├── providers/       # 文件列表状态、SMB连接状态
│   │   │   ├── views/           # 目录树、文件列表UI
│   │   │   └── widgets/         # 文件项、路径导航等组件
│   │   ├── clipboard_sync/      # 剪贴板同步功能
│   │   │   ├── models/          # 剪贴板条目模型
│   │   │   ├── providers/       # 剪贴板数据源、设备列表
│   │   │   ├── views/           # 剪贴板历史界面
│   │   │   └── widgets/         # 剪贴板卡片、设备选择器
│   │   ├── device_discovery/    # 设备发现功能
│   │   │   ├── providers/       # 设备列表、mDNS服务
│   │   │   └── widgets/         # 设备图标、状态指示
│   │   └── settings/            # 设置页面
│   │       ├── providers/       # 设置项状态
│   │       └── views/           # 设置界面
│   ├── shared/                  # 跨模块共享组件
│   │   ├── widgets/             # 通用按钮、对话框、加载动画
│   │   └── themes/              # 亮色/暗色主题定义
│   └── l10n/                    # 多语言支持（如需）
├── assets/                      # 资源文件（图标、字体）
├── pubspec.yaml                 # 依赖与配置
└── README.md                    # 项目说明（本文档）
```

---

## 4. 功能介绍

### 🎯 核心理念
**不是传输，而是“联通”**——设备间就像是在同一个空间内，文件可随时取用，剪贴板内容跨设备共享，所有操作无需下载到本地，不占用手机存储。

### 🔍 主要功能

#### 1. 局域网文件浏览（SMB 客户端）
- 自动发现同一 Wi-Fi 下的 Windows 共享文件夹。
- 支持输入 IP、用户名、密码，手动添加网络位置。
- 以树形目录展示电脑上的文件和文件夹。
- **流式预览**：点击图片、视频、文档，直接在线预览（不下载到手机）。
- 支持常用格式：图片（jpg/png/gif）、视频（mp4/mkv/avi）、PDF、文本文件等。

#### 2. 剪贴板跨设备同步
- **全自动无感同步**：任意一端复制文本，另一端剪贴板自动更新（可设置开关）。
- **历史记录查看**：在 App 内可查看所有设备上复制过的剪贴板历史条目。
- **手动选择粘贴**：在任意设备上，从历史列表中选择一条内容，点击“粘贴”即可将其写入本机剪贴板。
- 支持端到端加密（可选），确保隐私安全。

#### 3. 设备发现与连接
- 基于 mDNS（Bonjour）自动发现同一子网内运行“享联”的设备。
- 设备列表显示设备名称、IP、在线状态。
- 点击设备即可快速浏览其共享文件夹或查看其剪贴板历史。

#### 4. 极简 UI 设计
- 摒弃传统文件管理器的复杂按钮，采用卡片式布局和手势操作。
- 底部导航栏切换“文件浏览”、“剪贴板”、“设备”三个主要页面。
- 支持深色/浅色主题跟随系统。

#### 5. 后台常驻（安卓）
- 剪贴板监听服务可在后台运行，确保复制内容即时同步。
- 内存占用优化至合理范围，避免被系统频繁回收。

#### 6. 跨平台支持
- 一套代码同时覆盖 **Android、iOS、Windows、macOS、Linux**（桌面端主要作为“被访问端”和“剪贴板发送端”）。

---

## 5. 开发计划与里程碑

- **v0.1.0**：基础 SMB 连接、文件浏览、图片/视频预览。
- **v0.2.0**：剪贴板监听与跨设备同步（WebSocket）。
- **v0.3.0**：mDNS 设备自动发现、设备列表 UI。
- **v1.0.0**：完整功能稳定版，发布至各应用商店。

---

## 6. 许可与免责

本项目采用 **MIT 许可证**。工具本身不提供任何侵权内容，用户使用本工具访问的文件与数据，其版权与合法性由用户自行负责。

---

*Made with ❤️ for seamless connectivity.*