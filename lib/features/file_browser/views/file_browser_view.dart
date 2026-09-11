import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart' show AppColorScheme, AppColors;
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/device_icon_utils.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/glass_dropdown.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/neuomorphic_style.dart';
import '../../../shared/widgets/segmented_tab.dart';
import '../../device_discovery/models/device.dart';
import '../models/file_category.dart';
import '../models/file_item.dart';
import '../providers/file_browser_provider.dart';
import '../widgets/add_category_drawer.dart';
import '../widgets/add_category_sheet.dart';
import '../widgets/file_details_sheet.dart';
import '../widgets/file_list_item.dart';
import 'file_viewer_page.dart';

class FileBrowserView extends ConsumerWidget {
  const FileBrowserView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = PlatformUtils.isDesktop;
    return isDesktop
        ? const _DesktopFileBrowser()
        : const _MobileFileBrowser();
  }
}

/// 打开文件预览页面
void _openFile(BuildContext context, WidgetRef ref, FileItem file) {
  final deviceIp = ref.read(selectedDeviceIpProvider);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FileViewerPage(
        file: file,
        remoteDeviceIp: deviceIp,
      ),
    ),
  );
}

/// 文件卡片长按/右键：直接拉起详情弹窗（本机/远程皆如此）
///
/// 下载、打开、预览、删除等操作均已内置在详情弹窗中，无需再走选项弹窗。
void _handleFileActions(BuildContext cardContext, WidgetRef ref, FileItem file) {
  final deviceIp = ref.read(selectedDeviceIpProvider);
  final deviceName = ref.read(effectiveSelectedDeviceProvider) ?? '本机';
  final categoryName = ref.read(fileCategoryProvider);
  openFileDetails(
    cardContext,
    file: file,
    deviceIp: deviceIp,
    deviceName: deviceName,
    categoryName: categoryName,
  );
}

/// 加载中状态组件
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colors.iconActive,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '正在扫描文件…',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 顶部扫描进度提示条（列表已有数据时的刷新/渐进扫描状态显示）
///
/// 液态玻璃胶囊样式（与 tabbar / 返回顶部按钮设计语言一致），
/// 悬浮于列表顶部，不遮挡内容、不拦截点击。
class _ScanningIndicator extends StatelessWidget {
  const _ScanningIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.9),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.scanningFiles,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空结果状态组件
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: colors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无文件',
            style: TextStyle(fontSize: 15, color: colors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            '请在设置中添加共享文件夹',
            style: TextStyle(fontSize: 13, color: colors.textHint),
          ),
        ],
      ),
    );
  }
}

/// 根据当前选中的设备名称解析对应的设备图标
IconData _resolveDeviceIcon(String? deviceName, List<Device> connectedDevices) {
  if (deviceName == null || connectedDevices.isEmpty) {
    return Icons.computer;
  }
  final device = connectedDevices.firstWhere(
    (d) => d.name == deviceName,
    orElse: () => connectedDevices.first,
  );
  return deviceTypeIcon(device.typeIcon);
}

/// 胶囊操作按钮的悬浮提示（统一风格）
Widget _actionTooltip(String message, Widget child) {
  return Tooltip(
    message: message,
    preferBelow: false,
    verticalOffset: 20,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(6),
    ),
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    child: child,
  );
}

/// 液态玻璃图标动作按钮（刷新 / 添加分类等）
///
/// 与 tabbar 激活块 / 液态玻璃胶囊一致：白色发光 + 半透明白渐变 + 白色描边，
/// 深色模式下用白图标/白字，浅色模式用主色。带 Material+InkWell 水波纹反馈。
/// 内边距统一放在玻璃内部并居中，保证图标/文字与边框留白一致。
Widget _glassActionButton({
  required BuildContext context,
  required IconData icon,
  required VoidCallback onPressed,
  String? tooltip,
  String? label,
  double radius = 12,
  Color? iconColor,
  bool fillWidth = false,
}) {
  final colors = AppColorScheme.of(context);
  final isDark = colors.isDark;
  final color = iconColor ?? (isDark ? Colors.white : colors.iconActive);
  final hasLabel = label != null;

  final button = Container(
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        // 白色发光：与 tabbar 外框一致，保证统一发光强度
        BoxShadow(
          color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.3),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
        // 常规投影：让按钮从背景脱离
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          // 有文字时给玻璃内部左右留白，与单图标按钮的居中内边距一致
          padding: EdgeInsets.symmetric(horizontal: hasLabel ? 12 : 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0x45383842),
                      Color(0x3824242A),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.9),
                      Colors.white.withValues(alpha: 0.6),
                    ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.8),
            ),
          ),
          child: SizedBox(
            width: fillWidth ? double.infinity : null,
            height: 44,
            child: Center(
              child: hasLabel
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    )
                  : Icon(icon, size: 20, color: color),
            ),
          ),
        ),
      ),
    ),
  );

  return tooltip == null ? button : _actionTooltip(tooltip, button);
}

// ---------------------------------------------------------------------------
// 筛选条件栏（全端共用）
// ---------------------------------------------------------------------------

/// 筛选条件标签 + 三个 toggle tab
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    final showFileName = ref.watch(showFileNameProvider);
    final timelineGroup = ref.watch(timelineGroupProvider);
    final extensionGroup = ref.watch(extensionGroupProvider);
    final sortAscending = ref.watch(sortAscendingProvider);
    final onlyDownloaded = ref.watch(onlyDownloadedProvider);
    // 激活按钮内部元素颜色：与 tabbar 激活块呼应（深色用白，浅色用主色）
    final activeColor = colors.isDark ? Colors.white : colors.iconActive;

    return Row(
      children: [
        // 左侧：筛选条件文字
        Text(
          AppStrings.filterLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        // 中间：三个 toggle tab
        Expanded(
          child: SegmentedTab<_FilterTab>(
            items: const [
              SegmentedTabItem(value: _FilterTab.fileName, icon: Icons.sort_by_alpha),
              SegmentedTabItem(value: _FilterTab.timeline, icon: Icons.schedule),
              SegmentedTabItem(value: _FilterTab.extension, icon: Icons.extension),
            ],
            selectedValues: {
              if (showFileName) _FilterTab.fileName,
              if (timelineGroup) _FilterTab.timeline,
              if (extensionGroup) _FilterTab.extension,
            },
            multiSelect: true,
            onChanged: (values) {
              ref.read(showFileNameProvider.notifier).value = values.contains(_FilterTab.fileName);
              ref.read(timelineGroupProvider.notifier).value = values.contains(_FilterTab.timeline);
              ref.read(extensionGroupProvider.notifier).value = values.contains(_FilterTab.extension);
            },
          ),
        ),
        const SizedBox(width: 8),
        // 右侧：排序方向切换按钮（液态玻璃 + 激活发光）
        GestureDetector(
          onTap: () => ref.read(sortAscendingProvider.notifier).toggle(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: sortAscending
                ? GlassCapsuleDecoration.build(colors, 10, strong: false)
                : BoxDecoration(
                    color: colors.glassBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.glassBorder),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                  color: sortAscending
                      ? activeColor
                      : colors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  sortAscending ? '正序' : '倒序',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sortAscending
                        ? activeColor
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 右侧：仅显示本设备下载的文件开关（液态玻璃 + 激活发光）
        GestureDetector(
          onTap: () => ref.read(onlyDownloadedProvider.notifier).toggle(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: onlyDownloaded
                ? GlassCapsuleDecoration.build(colors, 10, strong: false)
                : BoxDecoration(
                    color: colors.glassBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.glassBorder),
                  ),
            child: Icon(
              Icons.download_outlined,
              size: 18,
              color: onlyDownloaded
                  ? activeColor
                  : colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 筛选 tab 枚举
enum _FilterTab { fileName, timeline, extension }

// ---------------------------------------------------------------------------
// 桌面端文件浏览器
// ---------------------------------------------------------------------------

class _DesktopFileBrowser extends ConsumerWidget {
  const _DesktopFileBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(filteredFileListProvider);
    final timelineGroups = ref.watch(timelineGroupedFileListProvider);
    final selectedCategory = ref.watch(fileCategoryProvider);
    final categories = ref.watch(allCategoriesProvider);
    final effectiveDevice = ref.watch(effectiveSelectedDeviceProvider);
    final connectedDevices = ref.watch(connectedDevicesProvider);
    final columnMode = ref.watch(desktopColumnModeProvider);
    final showFileName = ref.watch(showFileNameProvider);
    final timelineGroup = ref.watch(timelineGroupProvider);
    final extensionGroup = ref.watch(extensionGroupProvider);
    final nestedGroups = ref.watch(nestedGroupedFileListProvider);
    final extensionGroups = ref.watch(extensionGroupedFileListProvider);
    final scanState = ref.watch(fileScanStateProvider);
    final remoteDeviceIp = ref.watch(selectedDeviceIpProvider);
    // 预热分组缓存，确保切换开关时即时响应
    ref.watch(groupCacheWarmupProvider);

    // 选择分类时检查文件变更
    ref.listen(fileCategoryProvider, (_, _) {
      ref.read(fileListProvider.notifier).refreshIfNeeded();
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 48, 0, 0),
          child: Row(
            children: [
              _DesktopSidebar(
                categories: categories,
                selectedCategory: selectedCategory,
                effectiveDevice: effectiveDevice,
                connectedDevices: connectedDevices,
                columnMode: columnMode,
                onCategoryTap: (name) {
                  ref.read(fileCategoryProvider.notifier).category = name;
                },
                onDeviceTap: (name) {
                  ref.read(selectedDeviceProvider.notifier).device = name;
                },
                onColumnModeChanged: (mode) {
                  ref.read(desktopColumnModeProvider.notifier).mode = mode;
                },
                onAddCategory: () => showAddCategoryDesktopDrawer(context),
                onRefresh: () {
                  ref.read(fileListProvider.notifier).forceRefresh();
                },
                onRemoveCategory: (name) {
                  ref.read(customCategoriesProvider.notifier).removeCategory(name);
                  showAppToast(context, '分类「$name」已删除', type: ToastType.success);
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 路径面包屑
                      _PathBreadcrumb(
                        device: effectiveDevice ?? '本机',
                        category: selectedCategory,
                        deviceIcon: _resolveDeviceIcon(
                          effectiveDevice,
                          connectedDevices,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 筛选条件栏
                      const _FilterBar(),
                      const SizedBox(height: 16),
                      // 文件内容区
                      Expanded(
                        child: _FileContentArea(
                          timelineGroup: timelineGroup,
                          extensionGroup: extensionGroup,
                          showFileName: showFileName,
                          crossAxisCount: 6,
                          files: files,
                          timelineGroups: timelineGroups,
                          extensionGroups: extensionGroups,
                          nestedGroups: nestedGroups,
                          scanState: scanState,
                          remoteDeviceIp: remoteDeviceIp,
                          onFileTap: (file) => _openFile(context, ref, file),
                          onShowActions: (ctx, file) =>
                              _handleFileActions(ctx, ref, file),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 通用内容区（桌面/手机共用）
// ---------------------------------------------------------------------------

/// 根据分组模式渲染不同的内容区
///
/// 切换分组模式时显示短暂 loading，避免大量文件渲染造成卡顿无反馈。
/// 包含返回顶部悬浮按钮：当滚动位置超过阈值时显示。
class _FileContentArea extends StatefulWidget {
  final bool timelineGroup;
  final bool extensionGroup;
  final bool showFileName;
  final int crossAxisCount;
  final List<FileItem> files;
  final List<TimelineGroup> timelineGroups;
  final List<ExtensionGroup> extensionGroups;
  final List<NestedTimelineGroup> nestedGroups;
  final FileScanState scanState;
  final void Function(FileItem)? onFileTap;
  final String? remoteDeviceIp;

  /// 长按/右键显示操作栏（下载、详情）
  final void Function(BuildContext context, FileItem file) onShowActions;

  /// 底部预留（手机端悬浮 tabbar 高度），加到滚动内容底部，滑到底部不被遮挡
  final double bottomPadding;

  const _FileContentArea({
    required this.timelineGroup,
    required this.extensionGroup,
    required this.showFileName,
    required this.crossAxisCount,
    required this.files,
    required this.timelineGroups,
    required this.extensionGroups,
    required this.nestedGroups,
    required this.scanState,
    required this.onShowActions,
    this.onFileTap,
    this.remoteDeviceIp,
    this.bottomPadding = 0,
  });

  @override
  State<_FileContentArea> createState() => _FileContentAreaState();
}

class _FileContentAreaState extends State<_FileContentArea> {
  /// 是否正在切换分组模式（显示 loading）
  bool _switching = false;

  /// 上一次的分组模式（用于检测变化）
  bool? _prevTimelineGroup;
  bool? _prevExtensionGroup;

  /// 共享滚动控制器（用于返回顶部功能）
  final ScrollController _scrollController = ScrollController();

  /// 是否显示返回顶部按钮
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showBackToTop) {
      setState(() => _showBackToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant _FileContentArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测分组模式变化（选中/取消都会触发）
    final modeChanged = _prevTimelineGroup != null &&
        _prevExtensionGroup != null &&
        (_prevTimelineGroup != widget.timelineGroup ||
            _prevExtensionGroup != widget.extensionGroup);

    if (modeChanged && !_switching) {
      // 开始切换：显示 loading，延迟一帧再渲染内容
      _switching = true;
      _prevTimelineGroup = widget.timelineGroup;
      _prevExtensionGroup = widget.extensionGroup;
      // 使用微任务延迟，让 loading 动画有机会渲染一帧
      Future.microtask(() {
        if (mounted) {
          setState(() => _switching = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;

    // 加载中状态：仅在「还没有任何数据」时才显示全屏 loading。
    // 渐进扫描期间 files 已有部分数据（onProgress 持续更新 state），
    // 直接渲染列表实现"一边扫描一边渲染"，避免首次扫描长时间白屏。
    if (widget.files.isEmpty &&
        (widget.scanState == FileScanState.idle ||
            widget.scanState == FileScanState.scanning)) {
      return const _LoadingState();
    }

    // 空结果状态
    if (widget.files.isEmpty) {
      return const _EmptyState();
    }

    // 首次记录当前模式
    _prevTimelineGroup ??= widget.timelineGroup;
    _prevExtensionGroup ??= widget.extensionGroup;

    // 切换中：显示 loading
    if (_switching) {
      return const _LoadingState();
    }

    return Stack(
      children: [
        _buildContent(),
        // 扫描进行中且列表已有数据（刷新/增量扫描）：顶部玻璃进度提示条，
        // 让用户明确感知 loading 状态，同时不遮挡列表内容
        if (widget.scanState == FileScanState.scanning &&
            widget.files.isNotEmpty)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(child: _ScanningIndicator()),
            ),
          ),
        // 返回顶部悬浮按钮
        if (_showBackToTop)
          Positioned(
            // 紧贴悬浮 tabbar 上方，间隔约一个按钮可见度的距离，避免被遮挡也避免过高
            bottom: MediaQuery.of(context).padding.bottom + 20,
            right: 16,
            child: GestureDetector(
              onTap: _scrollToTop,
              child: Tooltip(
                message: AppStrings.backToTop,
                preferBelow: false,
                verticalOffset: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // 外发光：绘制在圆形容器上，向周围散发，不被内侧裁剪
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.55),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.12,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          // 液态玻璃，与底部 tabbar 设计语言一致
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? const [
                                    Color(0xB8383842),
                                    Color(0x9924242A),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.92),
                                    Colors.white.withValues(alpha: 0.7),
                                  ],
                          ),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.8),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_upward,
                          color: colors.iconPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    // 时间轴 + 后缀嵌套分组（时间轴优先）
    if (widget.timelineGroup && widget.extensionGroup) {
      return _TimelineExtensionView(
        groups: widget.nestedGroups,
        showFileName: widget.showFileName,
        crossAxisCount: widget.crossAxisCount,
        onFileTap: widget.onFileTap,
        remoteDeviceIp: widget.remoteDeviceIp,
        onShowActions: widget.onShowActions,
        scrollController: _scrollController,
        bottomPadding: widget.bottomPadding,
      );
    }
    // 仅时间轴分组
    if (widget.timelineGroup) {
      return _TimelineView(
        groups: widget.timelineGroups,
        showFileName: widget.showFileName,
        crossAxisCount: widget.crossAxisCount,
        onFileTap: widget.onFileTap,
        remoteDeviceIp: widget.remoteDeviceIp,
        onShowActions: widget.onShowActions,
        scrollController: _scrollController,
        bottomPadding: widget.bottomPadding,
      );
    }
    // 仅后缀分组
    if (widget.extensionGroup) {
      return _ExtensionView(
        groups: widget.extensionGroups,
        showFileName: widget.showFileName,
        crossAxisCount: widget.crossAxisCount,
        onFileTap: widget.onFileTap,
        remoteDeviceIp: widget.remoteDeviceIp,
        onShowActions: widget.onShowActions,
        scrollController: _scrollController,
        bottomPadding: widget.bottomPadding,
      );
    }
    // 平铺模式
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = _calcCrossAxisCount(constraints.maxWidth);
        return Stack(
          children: [
            Positioned.fill(
              child: GridView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: 16 + widget.bottomPadding,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: widget.files.length,
                itemBuilder: (context, index) => FileListItem(
                  key: ValueKey('${widget.remoteDeviceIp}|${widget.files[index].path}'),
                  file: widget.files[index],
                  showFileName: widget.showFileName,
                  remoteDeviceIp: widget.remoteDeviceIp,
                  onTap: widget.onFileTap != null
                      ? () => widget.onFileTap!(widget.files[index])
                      : null,
                  onShowActions: (ctx) =>
                      widget.onShowActions(ctx, widget.files[index]),
                ),
              ),
            ),
            // 右侧悬浮液态玻璃进度条（覆盖在列表之上，不挤压列表空间）
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              width: 36,
              child: _FloatingScrollbar(
                scrollController: _scrollController,
              ),
            ),
          ],
        );
      },
    );
  }

  int _calcCrossAxisCount(double width) {
    if (width > 1200) return 8;
    if (width > 900) return 6;
    if (width > 600) return 4;
    return 3;
  }
}

/// 桌面端侧边栏
class _DesktopSidebar extends StatelessWidget {
  final List<FileCategory> categories;
  final String selectedCategory;
  final String? effectiveDevice;
  final List<Device> connectedDevices;
  final ColumnMode columnMode;
  final ValueChanged<String> onCategoryTap;
  final ValueChanged<String> onDeviceTap;
  final ValueChanged<ColumnMode> onColumnModeChanged;
  final VoidCallback onAddCategory;
  final VoidCallback onRefresh;
  final ValueChanged<String> onRemoveCategory;

  const _DesktopSidebar({
    required this.categories,
    required this.selectedCategory,
    required this.effectiveDevice,
    required this.connectedDevices,
    required this.columnMode,
    required this.onCategoryTap,
    required this.onDeviceTap,
    required this.onColumnModeChanged,
    required this.onAddCategory,
    required this.onRefresh,
    required this.onRemoveCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final isCustomSelected = !defaultCategories.any((c) => c.name == selectedCategory);

    return Container(
      width: 220,
      margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: NeuomorphicStyle.adaptive(theme.brightness, blur: 12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.fileBrowserTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '设备',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _SidebarDeviceItem(
              name: '本机',
              icon: Icons.computer,
              isSelected: effectiveDevice == null,
              onTap: () => onDeviceTap('本机'),
            ),
            ...connectedDevices.map(
              (d) => _SidebarDeviceItem(
                name: d.name,
                icon: deviceTypeIcon(d.typeIcon),
                isSelected: effectiveDevice == d.name,
                onTap: () => onDeviceTap(d.name),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '分类',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 80,
                  height: 32,
                  child: SegmentedTab<ColumnMode>(
                    items: const [
                      SegmentedTabItem(value: ColumnMode.single, icon: Icons.view_stream),
                      SegmentedTabItem(value: ColumnMode.double, icon: Icons.grid_view),
                    ],
                    selectedValues: {columnMode},
                    onChanged: (values) {
                      onColumnModeChanged(values.first);
                    },
                    height: 32,
                    borderRadius: 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _CategoryList(
                categories: categories,
                selectedCategory: selectedCategory,
                columnMode: columnMode,
                onTap: onCategoryTap,
                isCustomCategory: (name) {
                  return !defaultCategories.any((c) => c.name == name);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _glassActionButton(
                    context: context,
                    icon: Icons.refresh,
                    onPressed: onRefresh,
                    tooltip: AppStrings.refresh,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: _glassActionButton(
                    context: context,
                    icon: Icons.add,
                    onPressed: onAddCategory,
                    label: isCustomSelected ? '分类' : AppStrings.addCategory,
                    tooltip: AppStrings.addCategory,
                    fillWidth: true,
                  ),
                ),
                if (isCustomSelected) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: AppStrings.deleteCategory,
                    preferBelow: false,
                    verticalOffset: 20,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    child: SizedBox(
                      width: 44,
                      child: OutlinedButton(
                        onPressed: () => onRemoveCategory(selectedCategory),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类列表（支持单列/双列）
class _CategoryList extends StatelessWidget {
  final List<FileCategory> categories;
  final String selectedCategory;
  final ColumnMode columnMode;
  final ValueChanged<String> onTap;
  final bool Function(String) isCustomCategory;

  const _CategoryList({
    required this.categories,
    required this.selectedCategory,
    required this.columnMode,
    required this.onTap,
    required this.isCustomCategory,
  });

  @override
  Widget build(BuildContext context) {
    if (columnMode == ColumnMode.double) {
      return SingleChildScrollView(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: categories.map((cat) {
            final isSelected = cat.name == selectedCategory;
            return SizedBox(
              width: 88,
              child: _SidebarCategoryItem(
                label: cat.name,
                icon: cat.icon,
                isSelected: isSelected,
                onTap: () => onTap(cat.name),
                compact: true,
              ),
            );
          }).toList(),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: categories.map((cat) {
        final isSelected = cat.name == selectedCategory;
        return _SidebarCategoryItem(
          label: cat.name,
          icon: cat.icon,
          isSelected: isSelected,
          onTap: () => onTap(cat.name),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// 手机端文件浏览器
// ---------------------------------------------------------------------------

class _MobileFileBrowser extends ConsumerWidget {
  const _MobileFileBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(filteredFileListProvider);
    final timelineGroups = ref.watch(timelineGroupedFileListProvider);
    final extensionGroups = ref.watch(extensionGroupedFileListProvider);
    final nestedGroups = ref.watch(nestedGroupedFileListProvider);
    final selectedCategory = ref.watch(fileCategoryProvider);
    final categories = ref.watch(allCategoriesProvider);
    final effectiveDevice = ref.watch(effectiveSelectedDeviceProvider);
    final connectedDevices = ref.watch(connectedDevicesProvider);
    final displayMode = ref.watch(mobileCategoryDisplayModeProvider);
    final showFileName = ref.watch(showFileNameProvider);
    final timelineGroup = ref.watch(timelineGroupProvider);
    final extensionGroup = ref.watch(extensionGroupProvider);
    final scanState = ref.watch(fileScanStateProvider);
    final remoteDeviceIp = ref.watch(selectedDeviceIpProvider);
    final colors = AppColorScheme.of(context);
    // 预热分组缓存，确保切换开关时即时响应
    ref.watch(groupCacheWarmupProvider);

    // 选择分类时检查文件变更
    ref.listen(fileCategoryProvider, (_, _) {
      ref.read(fileListProvider.notifier).refreshIfNeeded();
    });

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            // 标题
            Text(AppStrings.fileBrowserTitle, style: TextStyle(color: colors.textPrimary)),
            const SizedBox(width: 8),
            // 设备下拉框
            Expanded(
              child: GlassDropdownField<String>(
                value: effectiveDevice ?? '本机',
                items: [
                  DropdownMenuItem<String>(
                    value: '本机',
                    child: Row(
                      children: [
                        Icon(Icons.computer, size: 16, color: colors.iconSecondary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '本机',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...connectedDevices.map(
                    (d) => DropdownMenuItem<String>(
                      value: d.name,
                      child: Row(
                        children: [
                          Icon(deviceTypeIcon(d.typeIcon), size: 16, color: colors.iconSecondary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              d.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: colors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(selectedDeviceProvider.notifier).device = v;
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // 分类显示模式切换
            SizedBox(
              width: 80,
              height: 40,
              child: SegmentedTab<CategoryDisplayMode>(
                items: const [
                  SegmentedTabItem(value: CategoryDisplayMode.dropdown, icon: Icons.keyboard_arrow_down),
                  SegmentedTabItem(value: CategoryDisplayMode.list, icon: Icons.view_list),
                ],
                selectedValues: {displayMode},
                onChanged: (values) {
                  ref.read(mobileCategoryDisplayModeProvider.notifier).mode = values.first;
                },
                height: 40,
                borderRadius: 10,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 分类选择区域
            if (displayMode == CategoryDisplayMode.dropdown)
              _MobileDropdownCategoryBar(
                categories: categories,
                selectedCategory: selectedCategory,
                onTap: (name) {
                  ref.read(fileCategoryProvider.notifier).category = name;
                },
                onAddCategory: () => showAddCategoryMobileSheet(context),
                onRefresh: () {
                  ref.read(fileListProvider.notifier).forceRefresh();
                },
                onRemoveCategory: (name) {
                  ref.read(customCategoriesProvider.notifier).removeCategory(name);
                  showAppToast(context, '分类「$name」已删除', type: ToastType.success);
                },
              )
            else
              _MobileListCategoryBar(
                categories: categories,
                selectedCategory: selectedCategory,
                onTap: (name) {
                  ref.read(fileCategoryProvider.notifier).category = name;
                },
                onAddCategory: () => showAddCategoryMobileSheet(context),
                onRefresh: () {
                  ref.read(fileListProvider.notifier).forceRefresh();
                },
                onRemoveCategory: (name) {
                  ref.read(customCategoriesProvider.notifier).removeCategory(name);
                  showAppToast(context, '分类「$name」已删除', type: ToastType.success);
                },
              ),
            // 筛选条件栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const _FilterBar(),
            ),
            // 文件内容区（列表伸展到屏幕底部；底部预留交给滚动内容 padding，
            // 保证滑到底部时最后一行不被悬浮 tabbar 遮挡）
            Expanded(
              child: _FileContentArea(
                timelineGroup: timelineGroup,
                extensionGroup: extensionGroup,
                showFileName: showFileName,
                crossAxisCount: 3,
                files: files,
                timelineGroups: timelineGroups,
                extensionGroups: extensionGroups,
                nestedGroups: nestedGroups,
                scanState: scanState,
                remoteDeviceIp: remoteDeviceIp,
                onFileTap: (file) => _openFile(context, ref, file),
                onShowActions: (ctx, file) =>
                    _handleFileActions(ctx, ref, file),
                bottomPadding: MediaQuery.of(context).padding.bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 手机端下拉框模式分类栏
class _MobileDropdownCategoryBar extends StatelessWidget {
  final List<FileCategory> categories;
  final String selectedCategory;
  final ValueChanged<String> onTap;
  final VoidCallback onAddCategory;
  final VoidCallback onRefresh;
  final ValueChanged<String> onRemoveCategory;

  const _MobileDropdownCategoryBar({
    required this.categories,
    required this.selectedCategory,
    required this.onTap,
    required this.onAddCategory,
    required this.onRefresh,
    required this.onRemoveCategory,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isCustomSelected = !defaultCategories.any((c) => c.name == selectedCategory);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: GlassDropdownField<String>(
              value: selectedCategory,
              items: categories.map((cat) {
                return DropdownMenuItem<String>(
                  value: cat.name,
                  child: Row(
                    children: [
                      Icon(cat.icon, size: 16, color: colors.iconSecondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          cat.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onTap(v);
              },
            ),
          ),
          const SizedBox(width: 8),
          _glassActionButton(
            context: context,
            icon: Icons.refresh,
            onPressed: onRefresh,
            tooltip: AppStrings.refresh,
          ),
          const SizedBox(width: 8),
          _glassActionButton(
            context: context,
            icon: Icons.add,
            onPressed: onAddCategory,
            tooltip: AppStrings.addCategory,
          ),
          if (isCustomSelected) ...[
            const SizedBox(width: 8),
            _actionTooltip(
              AppStrings.deleteCategory,
              OutlinedButton(
                onPressed: () => onRemoveCategory(selectedCategory),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(44, 44),
                ),
                child: const Icon(Icons.delete_outline, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 手机端横向列表模式分类栏
class _MobileListCategoryBar extends StatelessWidget {
  final List<FileCategory> categories;
  final String selectedCategory;
  final ValueChanged<String> onTap;
  final VoidCallback onAddCategory;
  final VoidCallback onRefresh;
  final ValueChanged<String> onRemoveCategory;

  const _MobileListCategoryBar({
    required this.categories,
    required this.selectedCategory,
    required this.onTap,
    required this.onAddCategory,
    required this.onRefresh,
    required this.onRemoveCategory,
  });

  @override
  Widget build(BuildContext context) {
    final isCustomSelected = !defaultCategories.any((c) => c.name == selectedCategory);

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: categories.map((cat) {
              final isSelected = cat.name == selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CategoryChip(
                  label: cat.name,
                  icon: cat.icon,
                  isSelected: isSelected,
                  onTap: () => onTap(cat.name),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _glassActionButton(
                context: context,
                icon: Icons.refresh,
                onPressed: onRefresh,
                tooltip: AppStrings.refresh,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _glassActionButton(
                    context: context,
                    icon: Icons.add,
                    onPressed: onAddCategory,
                    label: AppStrings.addCategory,
                    tooltip: AppStrings.addCategory,
                  ),
                ),
              ),
              if (isCustomSelected)
                _actionTooltip(
                  AppStrings.deleteCategory,
                  OutlinedButton.icon(
                    onPressed: () => onRemoveCategory(selectedCategory),
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    label: const Text(
                      '删除',
                      style: TextStyle(fontSize: 13, color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 时间轴分组视图
// ---------------------------------------------------------------------------

/// 时间轴分组视图：上方时间标签，下方文件网格，右侧进度条
class _TimelineView extends StatefulWidget {
  final List<TimelineGroup> groups;
  final bool showFileName;
  final int crossAxisCount;
  final void Function(FileItem)? onFileTap;
  final String? remoteDeviceIp;
  final void Function(BuildContext context, FileItem file) onShowActions;
  final ScrollController scrollController;

  /// 底部预留（手机端悬浮 tabbar 高度），加到滚动内容底部
  final double bottomPadding;

  const _TimelineView({
    required this.groups,
    required this.showFileName,
    required this.crossAxisCount,
    required this.onShowActions,
    this.onFileTap,
    this.remoteDeviceIp,
    required this.scrollController,
    this.bottomPadding = 0,
  });

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    // 构建 sliver 列表：标题 + 文件网格交替
    final slivers = <Widget>[];
    for (final group in widget.groups) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: GlassCapsuleDecoration.build(colors, 8),
                child: Text(
                  group.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    // 深色模式：液态玻璃胶囊上用白字；浅色模式保持主色
                    color: colors.isDark ? Colors.white : colors.iconActive,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.files.length} 个文件',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ));
      slivers.add(SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            crossAxisSpacing: 8,
            mainAxisSpacing: 2,
            childAspectRatio: 0.85,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => FileListItem(
              key: ValueKey('${widget.remoteDeviceIp}|${group.files[index].path}'),
              file: group.files[index],
              showFileName: widget.showFileName,
              remoteDeviceIp: widget.remoteDeviceIp,
              onTap: widget.onFileTap != null
                  ? () => widget.onFileTap!(group.files[index])
                  : null,
              onShowActions: (ctx) =>
                  widget.onShowActions(ctx, group.files[index]),
            ),
            childCount: group.files.length,
          ),
        ),
      ));
    }
    // 底部留白（预留悬浮 tabbar 高度）
    slivers.add(SliverPadding(
      padding: EdgeInsets.only(bottom: 16 + widget.bottomPadding),
      sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
    ));

    return Stack(
      children: [
        // 文件列表（隐藏原生滚动条）
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: CustomScrollView(
              controller: widget.scrollController,
              slivers: slivers,
            ),
          ),
        ),
        // 右侧悬浮液态玻璃进度条（覆盖在列表之上，不挤压列表空间）
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          width: 36,
          child: _FloatingScrollbar(
            scrollController: widget.scrollController,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 后缀名分组视图
// ---------------------------------------------------------------------------

/// 按后缀名分组的文件列表视图
class _ExtensionView extends StatelessWidget {
  final List<ExtensionGroup> groups;
  final bool showFileName;
  final int crossAxisCount;
  final void Function(FileItem)? onFileTap;
  final String? remoteDeviceIp;
  final void Function(BuildContext context, FileItem file) onShowActions;
  final ScrollController scrollController;

  /// 底部预留（手机端悬浮 tabbar 高度），加到滚动内容底部
  final double bottomPadding;

  const _ExtensionView({
    required this.groups,
    required this.showFileName,
    required this.crossAxisCount,
    required this.onShowActions,
    this.onFileTap,
    this.remoteDeviceIp,
    required this.scrollController,
    this.bottomPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    // 构建 sliver 列表：标题 + 文件网格交替
    final slivers = <Widget>[];
    for (final group in groups) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: GlassCapsuleDecoration.build(colors, 8),
                child: Text(
                  group.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    // 深色模式：液态玻璃胶囊上用白字；浅色模式保持主色
                    color: colors.isDark ? Colors.white : colors.iconActive,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.files.length} 个文件',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ));
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => FileListItem(
              key: ValueKey('$remoteDeviceIp|${group.files[index].path}'),
              file: group.files[index],
              showFileName: showFileName,
              remoteDeviceIp: remoteDeviceIp,
              onTap: onFileTap != null
                  ? () => onFileTap!(group.files[index])
                  : null,
              onShowActions: (ctx) =>
                  onShowActions(ctx, group.files[index]),
            ),
            childCount: group.files.length,
          ),
        ),
      ));
    }
    // 底部留白（预留悬浮 tabbar 高度）
    slivers.add(SliverPadding(
      padding: EdgeInsets.only(bottom: 16 + bottomPadding),
      sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
    ));

    return Stack(
      children: [
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: CustomScrollView(
              controller: scrollController,
              slivers: slivers,
            ),
          ),
        ),
        // 右侧悬浮液态玻璃进度条（覆盖在列表之上，不挤压列表空间）
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          width: 36,
          child: _FloatingScrollbar(
            scrollController: scrollController,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 后缀名 + 时间轴嵌套分组视图
// ---------------------------------------------------------------------------

/// 时间轴 + 后缀嵌套分组视图（时间轴优先，外层时间轴，内层后缀）
class _TimelineExtensionView extends StatelessWidget {
  final List<NestedTimelineGroup> groups;
  final bool showFileName;
  final int crossAxisCount;
  final void Function(FileItem)? onFileTap;
  final String? remoteDeviceIp;
  final void Function(BuildContext context, FileItem file) onShowActions;
  final ScrollController scrollController;

  /// 底部预留（手机端悬浮 tabbar 高度），加到滚动内容底部
  final double bottomPadding;

  const _TimelineExtensionView({
    required this.groups,
    required this.showFileName,
    required this.crossAxisCount,
    required this.onShowActions,
    this.onFileTap,
    this.remoteDeviceIp,
    required this.scrollController,
    this.bottomPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    final slivers = <Widget>[];
    for (final group in groups) {
      // 时间轴分组标题
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: GlassCapsuleDecoration.build(colors, 8),
                child: Text(
                  group.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    // 深色模式：液态玻璃胶囊上用白字；浅色模式保持主色
                    color: colors.isDark ? Colors.white : colors.iconActive,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.extensionGroups.fold<int>(0, (sum, g) => sum + g.files.length)} 个文件',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ));

      // 后缀子分组
      for (final extGroup in group.extensionGroups) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.inputBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${extGroup.label} · ${extGroup.files.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        slivers.add(SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => FileListItem(
                key: ValueKey('$remoteDeviceIp|${extGroup.files[index].path}'),
                file: extGroup.files[index],
                showFileName: showFileName,
                remoteDeviceIp: remoteDeviceIp,
                onTap: onFileTap != null
                    ? () => onFileTap!(extGroup.files[index])
                    : null,
                onShowActions: (ctx) =>
                    onShowActions(ctx, extGroup.files[index]),
              ),
              childCount: extGroup.files.length,
            ),
          ),
        ));
      }
    }
    // 底部留白（预留悬浮 tabbar 高度）
    slivers.add(SliverPadding(
      padding: EdgeInsets.only(bottom: 16 + bottomPadding),
      sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
    ));

    return Stack(
      children: [
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: CustomScrollView(
              controller: scrollController,
              slivers: slivers,
            ),
          ),
        ),
        // 右侧悬浮液态玻璃进度条（覆盖在列表之上，不挤压列表空间）
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          width: 36,
          child: _FloatingScrollbar(
            scrollController: scrollController,
          ),
        ),
      ],
    );
  }
}

/// 右侧悬浮液态玻璃进度条
///
/// 仅显示滑块（无轨道），默认隐藏：列表滚动/拖动时出现，停止滚动 3s 后自动隐藏。
/// 以悬浮层方式叠加在列表之上，不挤压列表空间；滑块采用与底部 tabbar 同款的
/// 液态玻璃质感，按下/拖动时切换为激活形态（放大、变蓝）并主动控制滚动。
class _FloatingScrollbar extends StatefulWidget {
  final ScrollController scrollController;

  const _FloatingScrollbar({
    required this.scrollController,
  });

  @override
  State<_FloatingScrollbar> createState() => _FloatingScrollbarState();
}

class _FloatingScrollbarState extends State<_FloatingScrollbar> {
  double _fraction = 0;
  bool _visible = false;
  bool _pressed = false; // 触摸/按住滑块（激活态：变蓝、放大）
  bool _dragging = false; // 是否正在拖动
  Timer? _hideTimer;

  // 由 build 记录的可视轨道区域（用于手势换算）
  double _trackTop = 0;
  double _trackHeight = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    // 首次布局后滚动控制器才附加 position（hasClients 才为 true）。
    // 主动重建一次，让热区即刻可用（滑块仍保持默认隐藏，滚动时才出现）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _hideTimer?.cancel();
    super.dispose();
  }

  bool get _hasContent {
    final c = widget.scrollController;
    return c.hasClients && c.position.maxScrollExtent > 0;
  }

  void _onScroll() {
    final c = widget.scrollController;
    if (_hasContent) {
      _fraction = (c.offset / c.position.maxScrollExtent).clamp(0.0, 1.0);
    } else {
      _fraction = 0;
    }
    _appearThenAutoHide();
  }

  /// 出现并启动 3s 自动隐藏倒计时（拖拽中不隐藏）
  void _appearThenAutoHide() {
    if (_dragging) return;
    setState(() => _visible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_dragging) {
        setState(() => _visible = false);
      }
    });
  }

  void _onTapDown(double localY) {
    // 触摸滑块：进入激活态（变蓝、放大），跳转到该位置，
    // 短暂激活反馈后若无后续拖动则恢复。
    setState(() => _pressed = true);
    _hideTimer?.cancel();
    _jumpTo(localY);
    _hideTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_dragging) {
        setState(() => _pressed = false);
        _appearThenAutoHide();
      }
    });
  }

  void _onDragStart(double thumbY, DragStartDetails d) {
    setState(() {
      _dragging = true;
      _pressed = true;
      _visible = true;
    });
    _hideTimer?.cancel();
    // 落点即当前进度，让滑块保持在手指下方（再按 delta 增量移动）
    if (_hasContent) {
      final absY = thumbY + d.localPosition.dy;
      final frac = ((absY - _trackTop) / _trackHeight).clamp(0.0, 1.0);
      setState(() => _fraction = frac);
      widget.scrollController.jumpTo(
          frac * widget.scrollController.position.maxScrollExtent);
    }
  }

  void _onDragEnd() {
    setState(() {
      _dragging = false;
      _pressed = false;
    });
    _appearThenAutoHide();
  }

  void _jumpTo(double localY) {
    final c = widget.scrollController;
    if (!_hasContent) return;
    final frac = ((localY - _trackTop) / _trackHeight).clamp(0.0, 1.0);
    c.jumpTo(frac * c.position.maxScrollExtent);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_hasContent) return;
    // 按手指增量（delta.dy）换算进度，1:1 跟随手指，避免过快/越界
    final step = d.delta.dy / _trackHeight;
    setState(() => _fraction = (_fraction + step).clamp(0.0, 1.0));
    widget.scrollController.jumpTo(
        _fraction * widget.scrollController.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalH = constraints.maxHeight;
        // 计算悬浮轨道区域：
        //   轨道底部 = 屏幕底 - (安全区 + tabbar 高度 + 底部安全间隔)；
        //   轨道高度 = (轨道可用高度) * 80%，顶部自然留白 20%。
        final safeBottom = MediaQuery.of(context).padding.bottom;
        const tabbarHeight = 78.0; // 悬浮 tabbar 高度（含上下 padding）
        const bottomGap = 10.0; // 轨道底边距 tabbar 顶部的安全间隔
        final trackBottom = totalH - (safeBottom + tabbarHeight + bottomGap);
        final span = trackBottom.clamp(0.0, totalH); // 可用高度
        _trackHeight = span * 0.8; // 80% 高度
        _trackTop = span - _trackHeight; // 轨道顶边（顶部留白 20%）

        final hasContent = _hasContent && _trackHeight > 0;
        final active = _pressed || _dragging;
        final showThumb = hasContent && (_visible || active);

        final thumbW = active ? 36.0 : 28.0;
        final thumbH = active ? 60.0 : 46.0;
        final thumbX = (constraints.maxWidth - thumbW) / 2;
        final thumbY = (_trackTop +
                _fraction * (_trackHeight - thumbH))
            .clamp(_trackTop, _trackTop + _trackHeight - thumbH);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 液态玻璃滑块：唯一交互元素，分激活/未激活两种形态。
            // 未激活时默认跟随列表滚动进度（_onScroll 更新 fraction）；
            // 按下/拖动时切换为激活形态，抓住滑块主动控制滚动位置。
            if (showThumb)
              Positioned(
                left: thumbX,
                top: thumbY,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _onTapDown(thumbY + d.localPosition.dy),
                  onVerticalDragStart: (d) => _onDragStart(thumbY, d),
                  onVerticalDragUpdate: (d) => _onDragUpdate(d),
                  onVerticalDragEnd: (_) => _onDragEnd(),
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: thumbW,
                  height: thumbH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(thumbW / 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.12,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                      if (active)
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(thumbW / 2),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: active
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    activeColor
                                        .withValues(alpha: isDark ? 0.85 : 0.75),
                                    activeColor.withValues(
                                        alpha: isDark ? 0.55 : 0.5),
                                  ],
                                )
                              : LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isDark
                                      ? const [
                                          Color(0xB8383842),
                                          Color(0x9924242A),
                                        ]
                                      : [
                                          Colors.white
                                              .withValues(alpha: 0.92),
                                          Colors.white
                                              .withValues(alpha: 0.6),
                                        ],
                                ),
                          borderRadius:
                              BorderRadius.circular(thumbW / 2),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.8),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.compress,
                            size: active ? 20 : 16,
                            color: active
                                ? Colors.white
                                : (isDark
                                    ? Colors.white70
                                    : const Color(0xFF1C1C1E)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ),
            // 未激活/激活两种形态的滑块即唯一交互元素，无进度信息块
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 通用组件
// ---------------------------------------------------------------------------

/// 侧边栏设备项
class _SidebarDeviceItem extends StatefulWidget {
  final String name;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  const _SidebarDeviceItem({
    required this.name,
    required this.icon,
    required this.isSelected,
    this.onTap,
  });

  @override
  State<_SidebarDeviceItem> createState() => _SidebarDeviceItemState();
}

class _SidebarDeviceItemState extends State<_SidebarDeviceItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final showHover = _hovering && !widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: widget.isSelected
                // 选中态：液态玻璃（深色白字呼叫胶囊）
                ? GlassCapsuleDecoration.build(colors, 10)
                : BoxDecoration(
                    color: showHover
                        ? (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: widget.isSelected
                      ? (isDark ? Colors.white : colors.iconActive)
                      : colors.iconSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: widget.isSelected
                          ? (isDark ? Colors.white : colors.iconActive)
                          : colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧边栏分类项
class _SidebarCategoryItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarCategoryItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_SidebarCategoryItem> createState() => _SidebarCategoryItemState();
}

class _SidebarCategoryItemState extends State<_SidebarCategoryItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final showHover = _hovering && !widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 6 : 12,
              vertical: widget.compact ? 8 : 10,
            ),
            decoration: widget.isSelected
                // 选中态：液态玻璃（深色白字/白图标呼叫胶囊）
                ? GlassCapsuleDecoration.build(colors, 10)
                : BoxDecoration(
                    color: showHover
                        ? (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
            child: widget.compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: 18,
                        color: widget.isSelected
                            ? (isDark ? Colors.white : colors.iconActive)
                            : colors.iconSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.isSelected
                              ? (isDark ? Colors.white : colors.iconActive)
                              : colors.textPrimary,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 18,
                        color: widget.isSelected
                            ? (isDark ? Colors.white : colors.iconActive)
                            : colors.iconSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: widget.isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: widget.isSelected
                                ? (isDark ? Colors.white : colors.iconActive)
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 路径面包屑
class _PathBreadcrumb extends StatelessWidget {
  final String device;
  final String category;
  final IconData deviceIcon;

  const _PathBreadcrumb({
    required this.device,
    required this.category,
    required this.deviceIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(deviceIcon, size: 16, color: colors.iconSecondary),
        const SizedBox(width: 6),
        Text(
          device,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, size: 16, color: colors.iconSecondary),
        const SizedBox(width: 6),
        Icon(Icons.folder, size: 16, color: colors.iconActive),
        const SizedBox(width: 6),
        Text(
          category,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 手机端分类筛选胶囊
class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: isSelected
            // 选中态：液态玻璃胶囊（深色模式下用白字/白图标呼应）
            ? GlassCapsuleDecoration.build(colors, 20)
            : BoxDecoration(
                color: colors.glassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.glassBorder),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? (colors.isDark ? Colors.white : colors.iconActive)
                  : colors.iconSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? (colors.isDark ? Colors.white : colors.iconActive)
                    : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
