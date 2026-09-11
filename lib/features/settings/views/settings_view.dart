import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unified_popups/unified_popups.dart'
    hide ToastType;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/providers/global_providers.dart';
import '../../../core/services/app_image_cache_manager.dart';
import '../../../core/services/device_info_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../features/file_browser/services/remote_file_service.dart';
import '../../../features/file_browser/services/local_file_service.dart';
import '../../../features/file_browser/services/file_cache_service.dart';
import '../../../features/file_browser/services/media_duration_service.dart';
import '../../../features/file_browser/providers/file_browser_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/glass_dropdown.dart';
import '../../../shared/widgets/glass_switch.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/neuomorphic_style.dart';
import '../providers/settings_provider.dart';
import '../widgets/password_input_field.dart';
import '../widgets/shared_content_drawer.dart';
import '../widgets/shared_content_sheet.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (PlatformUtils.isDesktop) {
      return const _DesktopSettingsView();
    }
    return const _MobileSettingsView();
  }
}

// ===========================================================================
// 手机端设置页
// ===========================================================================

class _MobileSettingsView extends ConsumerWidget {
  const _MobileSettingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceInfo = ref.watch(deviceInfoProvider);
    final deviceName = ref.watch(deviceNameProvider);
    final acceptConnections = ref.watch(acceptConnectionsProvider);
    final usePassword = ref.watch(usePasswordProvider);
    final clipboardSync = ref.watch(clipboardSyncProvider);
    final themePref = ref.watch(themePreferenceProvider);

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            48,
            16,
            MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _DeviceHeader(deviceName: deviceName, info: deviceInfo.value),
            const SizedBox(height: 24),
            _buildSectionTitle(context, AppStrings.settingsAppearance),
            _NeuItemCard(
              child: _ThemeDropdownRow(
                value: themePref,
                onChanged: (v) =>
                    ref.read(themePreferenceProvider.notifier).preference = v,
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionTitle(context, AppStrings.settingsConnection),
            _NeuItemCard(
              child: _NeuSwitchItem(
                title: AppStrings.acceptConnections,
                value: acceptConnections,
                onChanged: (v) =>
                    ref.read(acceptConnectionsProvider.notifier).enabled = v,
              ),
            ),
            const SizedBox(height: 12),
            _NeuItemCard(
              child: _NeuSwitchItem(
                title: AppStrings.connectionPassword,
                value: usePassword,
                onChanged: (v) =>
                    ref.read(usePasswordProvider.notifier).enabled = v,
              ),
            ),
            if (usePassword) ...[
              const SizedBox(height: 12),
              _NeuItemCard(
                child: PasswordInputField(
                  value: ref.watch(connectionPasswordProvider),
                  onChanged: (v) =>
                      ref.read(connectionPasswordProvider.notifier).password =
                          v,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildSectionTitle(context, AppStrings.settingsShared),
            _NeuItemCard(
              onTap: () => _showSharedContentSheet(context, ref),
              child: _NeuTapContent(
                leading: const _SharedContentIcon(),
                title: AppStrings.sharedContent,
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColorScheme.of(context).iconSecondary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _NeuItemCard(
              child: _NeuSwitchItem(
                title: AppStrings.clipboardSync,
                value: clipboardSync,
                onChanged: (v) =>
                    ref.read(clipboardSyncProvider.notifier).enabled = v,
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionTitle(context, AppStrings.settingsCache),
            const _CacheSettingsGroup(),
            const SizedBox(height: 20),
            _buildSectionTitle(context, AppStrings.settingsAbout),
            _NeuItemCard(
              onTap: () => _showMobileAboutDialog(context, ref),
              child: _NeuTapContent(
                leading: Icon(
                  Icons.info_outline,
                  size: 22,
                  color: AppColorScheme.of(context).iconSecondary,
                ),
                title: AppStrings.aboutTitle,
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColorScheme.of(context).iconSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 桌面端设置页：左侧设置项 + 右侧详情
// ===========================================================================

enum _SettingsSection { appearance, connection, shared, cache, about }

class _DesktopSettingsView extends ConsumerStatefulWidget {
  const _DesktopSettingsView();

  @override
  ConsumerState<_DesktopSettingsView> createState() =>
      _DesktopSettingsViewState();
}

class _DesktopSettingsViewState extends ConsumerState<_DesktopSettingsView> {
  _SettingsSection _selected = _SettingsSection.appearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 48, 0, 0),
          child: Row(
            children: [
              // 左侧导航列表（无分割线，用阴影分层）—— 宽度与文件管理页统一为 220
              Container(
                width: 220,
                margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                decoration: BoxDecoration(
                  color: colors.glassBg,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: NeuomorphicStyle.adaptive(
                    theme.brightness,
                    blur: 20,
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      child: Text(
                        AppStrings.settingsTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _DesktopNavItem(
                      icon: Icons.palette_outlined,
                      label: AppStrings.navAppearance,
                      selected: _selected == _SettingsSection.appearance,
                      onTap: () => setState(
                        () => _selected = _SettingsSection.appearance,
                      ),
                    ),
                    _DesktopNavItem(
                      icon: Icons.link,
                      label: AppStrings.navConnection,
                      selected: _selected == _SettingsSection.connection,
                      onTap: () => setState(
                        () => _selected = _SettingsSection.connection,
                      ),
                    ),
                    _DesktopNavItem(
                      icon: Icons.folder_shared_outlined,
                      label: AppStrings.navShared,
                      selected: _selected == _SettingsSection.shared,
                      onTap: () =>
                          setState(() => _selected = _SettingsSection.shared),
                    ),
                    _DesktopNavItem(
                      icon: Icons.cached,
                      label: AppStrings.navCache,
                      selected: _selected == _SettingsSection.cache,
                      onTap: () =>
                          setState(() => _selected = _SettingsSection.cache),
                    ),
                    _DesktopNavItem(
                      icon: Icons.info_outline,
                      label: AppStrings.navAbout,
                      selected: _selected == _SettingsSection.about,
                      onTap: () =>
                          setState(() => _selected = _SettingsSection.about),
                    ),
                  ],
                ),
              ),
              // 右侧详情区
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  child: switch (_selected) {
                    _SettingsSection.appearance => _DesktopAppearanceSection(),
                    _SettingsSection.connection => _DesktopConnectionSection(),
                    _SettingsSection.shared => _DesktopSharedSection(),
                    _SettingsSection.cache => _DesktopCacheSection(),
                    _SettingsSection.about => _DesktopAboutSection(),
                  },
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
// 桌面端 - 外观
// ---------------------------------------------------------------------------

class _DesktopAppearanceSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final themePref = ref.watch(themePreferenceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.settingsAppearance,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _NeuItemCard(
          child: _ThemeDropdownRow(
            value: themePref,
            onChanged: (v) =>
                ref.read(themePreferenceProvider.notifier).preference = v,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端 - 连接设置
// ---------------------------------------------------------------------------

class _DesktopConnectionSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final acceptConnections = ref.watch(acceptConnectionsProvider);
    final usePassword = ref.watch(usePasswordProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.settingsConnection,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _NeuItemCard(
          child: _NeuSwitchItem(
            title: AppStrings.acceptConnections,
            subtitle: AppStrings.acceptConnectionsSub,
            value: acceptConnections,
            onChanged: (v) =>
                ref.read(acceptConnectionsProvider.notifier).enabled = v,
          ),
        ),
        const SizedBox(height: 12),
        _NeuItemCard(
          child: _NeuSwitchItem(
            title: AppStrings.connectionPassword,
            subtitle: AppStrings.connectionPasswordSub,
            value: usePassword,
            onChanged: (v) =>
                ref.read(usePasswordProvider.notifier).enabled = v,
          ),
        ),
        if (usePassword) ...[
          const SizedBox(height: 12),
          _NeuItemCard(
            child: PasswordInputField(
              value: ref.watch(connectionPasswordProvider),
              onChanged: (v) =>
                  ref.read(connectionPasswordProvider.notifier).password = v,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端 - 共享设置
// ---------------------------------------------------------------------------

class _DesktopSharedSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final clipboardSync = ref.watch(clipboardSyncProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.settingsShared,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _NeuItemCard(
          onTap: () => _showSharedContentSheet(context, ref),
          child: _NeuTapContent(
            leading: const _SharedContentIcon(),
            title: AppStrings.sharedContent,
            subtitle: AppStrings.sharedContentSub,
            trailing: Icon(
              Icons.chevron_right,
              size: 20,
              color: colors.iconSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _NeuItemCard(
          child: _NeuSwitchItem(
            title: AppStrings.clipboardSync,
            subtitle: AppStrings.clipboardSyncSub,
            value: clipboardSync,
            onChanged: (v) =>
                ref.read(clipboardSyncProvider.notifier).enabled = v,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端 - 缓存设置
// ---------------------------------------------------------------------------

class _DesktopCacheSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DesktopCacheSection> createState() =>
      _DesktopCacheSectionState();
}

class _DesktopCacheSectionState extends ConsumerState<_DesktopCacheSection> {
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() =>
      ref.read(cacheSizeProvider.notifier).refresh();

  Future<void> _clearCache() async {
    if (_clearing) return;
    final confirmed = await _confirmClearCache(context);
    if (confirmed != true || !context.mounted) return;
    setState(() => _clearing = true);
    // 内存与磁盘必须**一致清除**，否则内存里的旧映射指向已删除的磁盘文件，
    // 缩略图会永远渲染失败（远程设备经 /thumb 接口也会命中旧映射）
    // 1. 先清远程图片缓存（清空其索引与文件，保持 flutter_cache_manager 状态一致）
    try {
      await AppImageCacheManager.instance.emptyCache();
    } catch (_) {}
    // 2. 本地文件索引 + 缩略图内存映射（clearAllCaches 内部同步清空 _thumbnailCache）
    LocalFileService.instance.clearAllCaches();
    // 3. 清空整个缓存目录（索引、缩略图、ts 合并、临时文件、远程图片）
    await RemoteFileService.instance.clearAllTempFiles();
    // 4. 远程文件列表 + 媒体时长
    await FileCacheService.instance.clearAllCaches();
    MediaDurationService.instance.clearAll();
    // 5. Flutter 内存图片缓存（避免已解码图片继续占用内存/显示旧内容）
    PaintingBinding.instance.imageCache.clear();
    ref.invalidate(fileListProvider);
    ref.read(downloadedStampProvider.notifier).bump();
    await _refreshSize();
    if (mounted) {
      setState(() => _clearing = false);
      showAppToast(context, '缓存已清空', type: ToastType.success);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final cacheSize = ref.watch(cacheSizeProvider);
    // 扫描完成时自动刷新缓存大小：进入页面时扫描可能仍在进行，
    // 索引/缩略图尚未写盘，此时统计会是 0，扫描结束后需重新统计
    ref.listen<FileScanState>(fileScanStateProvider, (prev, next) {
      if (next == FileScanState.done || next == FileScanState.empty) {
        _refreshSize();
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.settingsCache,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _NeuItemCard(
          child: _NeuTapContent(
            leading: Icon(Icons.cached, size: 22, color: colors.iconSecondary),
            title: AppStrings.cacheData,
            subtitle: '${AppStrings.cacheDataSub}：${_formatSize(cacheSize)}',
            trailing: _RefreshCacheButton(
              onPressed: () => ref.read(cacheSizeProvider.notifier).refresh(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _NeuItemCard(
          child: _NeuTapContent(
            leading: Icon(
              Icons.delete_sweep_outlined,
              size: 22,
              color: colors.iconSecondary,
            ),
            title: AppStrings.clearCache,
            subtitle: AppStrings.clearCacheSub,
            trailing: _ClearCacheButton(
              busy: _clearing,
              onPressed: _clearCache,
              enabled: cacheSize > 0,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端 - 关于
// ---------------------------------------------------------------------------

class _DesktopAboutSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final deviceInfo = ref.watch(deviceInfoProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AppStrings.aboutTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _DeviceHeader(
          deviceName: ref.watch(deviceNameProvider),
          info: deviceInfo.value,
        ),
        const SizedBox(height: 20),
        _NeuItemCard(
          child: Column(
            children: [
              _NeuInfoRow(
                label: AppStrings.aboutAppName,
                value: AppStrings.appName,
              ),
              Divider(height: 1, color: colors.divider),
              _NeuInfoRow(
                label: AppStrings.aboutVersion,
                value: AppStrings.appVersion,
              ),
              Divider(height: 1, color: colors.divider),
              _NeuInfoRow(
                label: AppStrings.aboutDeviceModel,
                value: deviceInfo.value?.model ?? '—',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// 共享组件：新拟物卡片 + 设置项
// ===========================================================================

/// 桌面端设置页左侧导航项
///
/// 始终显示图标 + 文字（与文件管理页的"仅图标"侧边栏不同）。
class _DesktopNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final activeColor = theme.colorScheme.primary;
    final showHover = _hovering && !widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: (widget.selected || showHover)
                  ? [
                      BoxShadow(
                        color: (widget.selected ? activeColor : Colors.black)
                            .withValues(alpha: widget.selected ? 0.2 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            // Stack: 背景层在下，图标+文字在上，避免被白色覆盖
            child: Stack(
              children: [
                // 背景层：选中蓝色 / 悬浮白色 / 无则透明（填满整个区域）
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? activeColor.withValues(alpha: isDark ? 0.3 : 0.12)
                          : showHover
                          ? (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                // 内容层：图标 + 文字（带内边距，与胶囊边缘保持间距）
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 22,
                        color: widget.selected
                            ? activeColor
                            : colors.iconPrimary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: widget.selected
                              ? activeColor
                              : colors.textPrimary,
                        ),
                      ),
                    ],
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

/// 清空缓存确认弹窗（样式与删除文件弹窗一致）
class _ClearCacheConfirmDialog extends StatelessWidget {
  const _ClearCacheConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 28,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '清除缓存',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '缓存内容中包括文件管理中的信息，清除后需要重新扫描文件。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('清除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出"清除缓存"确认框
Future<bool?> _confirmClearCache(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ClearCacheConfirmDialog(),
  );
}

/// 缓存设置组：显示缓存占用大小 + 一键清空缓存
///
/// 打开页面时实时计算缓存大小，清空后自动刷新。清空会清除内存/磁盘文件索引、
/// 临时缓存目录、远程文件列表缓存与媒体时长缓存，并触发重新扫描。
class _CacheSettingsGroup extends ConsumerStatefulWidget {
  const _CacheSettingsGroup();

  @override
  ConsumerState<_CacheSettingsGroup> createState() => _CacheSettingsGroupState();
}

class _CacheSettingsGroupState extends ConsumerState<_CacheSettingsGroup> {
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() =>
      ref.read(cacheSizeProvider.notifier).refresh();

  Future<void> _clearCache() async {
    if (_clearing) return;
    final confirmed = await _confirmClearCache(context);
    if (confirmed != true || !context.mounted) return;
    setState(() => _clearing = true);
    // 清除全部缓存：内存/磁盘文件索引 + 临时目录 + 远程列表 + 媒体时长
    // 内存与磁盘必须**一致清除**，否则内存里的旧映射指向已删除的磁盘文件，
    // 缩略图会永远渲染失败（远程设备经 /thumb 接口也会命中旧映射）
    // 1. 先清远程图片缓存（清空其索引与文件，保持 flutter_cache_manager 状态一致）
    try {
      await AppImageCacheManager.instance.emptyCache();
    } catch (_) {}
    // 2. 本地文件索引 + 缩略图内存映射（clearAllCaches 内部同步清空 _thumbnailCache）
    LocalFileService.instance.clearAllCaches();
    // 3. 清空整个缓存目录（索引、缩略图、ts 合并、临时文件、远程图片）
    await RemoteFileService.instance.clearAllTempFiles();
    // 4. 远程文件列表 + 媒体时长
    await FileCacheService.instance.clearAllCaches();
    MediaDurationService.instance.clearAll();
    // 5. Flutter 内存图片缓存（避免已解码图片继续占用内存/显示旧内容）
    PaintingBinding.instance.imageCache.clear();
    // 触发重新扫描与"仅下载"过滤重算
    ref.invalidate(fileListProvider);
    ref.read(downloadedStampProvider.notifier).bump();
    await _refreshSize();
    if (mounted) {
      setState(() => _clearing = false);
      showAppToast(context, '缓存已清空', type: ToastType.success);
    }
  }

  /// 根据大小自动切换单位：B / KB / MB / GB，MB、GB 保留两位小数
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final cacheSize = ref.watch(cacheSizeProvider);
    // 扫描完成时自动刷新缓存大小：进入页面时扫描可能仍在进行，
    // 索引/缩略图尚未写盘，此时统计会是 0，扫描结束后需重新统计
    ref.listen<FileScanState>(fileScanStateProvider, (prev, next) {
      if (next == FileScanState.done || next == FileScanState.empty) {
        _refreshSize();
      }
    });
    return Column(
      children: [
        _NeuItemCard(
          child: _NeuTapContent(
            leading: Icon(Icons.cached, size: 22, color: colors.iconSecondary),
            title: AppStrings.cacheData,
            subtitle:
                '${AppStrings.cacheDataSub}：${_formatSize(cacheSize)}',
            trailing: _RefreshCacheButton(
              onPressed: () => ref.read(cacheSizeProvider.notifier).refresh(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _NeuItemCard(
          child: _NeuTapContent(
            leading: Icon(
              Icons.delete_sweep_outlined,
              size: 22,
              color: colors.iconSecondary,
            ),
            title: AppStrings.clearCache,
            subtitle: AppStrings.clearCacheSub,
            trailing: _ClearCacheButton(
              busy: _clearing,
              onPressed: _clearCache,
              enabled: cacheSize > 0,
            ),
          ),
        ),
      ],
    );
  }
}

/// 缓存数据刷新按钮（点击重新扫描缓存目录计算大小）
///
/// 点击后按钮进入 loading 状态并禁用，直到计算完成，避免重复点击。
class _RefreshCacheButton extends StatefulWidget {
  final Future<void> Function() onPressed;

  const _RefreshCacheButton({required this.onPressed});

  @override
  State<_RefreshCacheButton> createState() => _RefreshCacheButtonState();
}

class _RefreshCacheButtonState extends State<_RefreshCacheButton> {
  bool _busy = false;

  /// 最小显示时长：保证点击后动画至少停留一段时间，避免扫描太快一闪而过
  static const Duration _minDuration = Duration(milliseconds: 1000);

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final started = DateTime.now();
    try {
      await widget.onPressed();
    } finally {
      // 确保 loading 动画至少显示最小时长，防止刷新过快无感知
      final elapsed = DateTime.now().difference(started);
      final remain = _minDuration - elapsed;
      if (remain > Duration.zero) {
        await Future.delayed(remain);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : _handleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: _busy
                ? CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colors.iconActive,
                  )
                : Icon(
                    Icons.refresh,
                    size: 20,
                    color: colors.iconSecondary,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 清空缓存按钮（右侧显示，风格与开关等控件统一，适配深色/浅色模式）
class _ClearCacheButton extends StatelessWidget {
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  const _ClearCacheButton({
    required this.busy,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    // 缓存为空时禁用，清空过程中也禁用
    final canTap = enabled && !busy;
    final fgColor = enabled ? colors.textPrimary : colors.textHint;
    return GestureDetector(
      onTap: canTap ? onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? colors.inputBg : colors.scaffoldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? colors.inputBorder
                : colors.inputBorder.withValues(alpha: 0.4),
          ),
          boxShadow: NeuomorphicStyle.adaptive(
            Theme.of(context).brightness,
            blur: 8,
          ),
        ),
        child: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.iconActive,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_sweep_outlined,
                    size: 16,
                    color: fgColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppStrings.clearCache,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 新拟物单项卡片
///
/// 每个设置项独立一张卡片，项与项之间用间距分隔（不再共用一个背景胶囊）。
/// 可选 [onTap] 提供水波纹触摸反馈。
class _NeuItemCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _NeuItemCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: NeuomorphicStyle.adaptive(theme.brightness, blur: 12),
      ),
      child: onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(padding: const EdgeInsets.all(12), child: child),
              ),
            )
          : Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

/// 新拟物开关项（使用自定义 GlassSwitch）
class _NeuSwitchItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NeuSwitchItem({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        GlassSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// 点击项的内容布局（配合 _NeuItemCard 的 InkWell 使用）
class _NeuTapContent extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _NeuTapContent({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 信息行
class _NeuInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _NeuInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 深色模式下拉选择行（使用自定义 GlassDropdownField）
class _ThemeDropdownRow extends StatelessWidget {
  final ThemePreference value;
  final ValueChanged<ThemePreference> onChanged;

  const _ThemeDropdownRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.dark_mode_outlined, size: 22, color: colors.iconSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            AppStrings.darkMode,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          width: 130,
          child: GlassDropdownField<ThemePreference>(
            value: value,
            items: [
              DropdownMenuItem<ThemePreference>(
                value: ThemePreference.system,
                child: Text(
                  AppStrings.themeSystem,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
              DropdownMenuItem<ThemePreference>(
                value: ThemePreference.light,
                child: Text(
                  AppStrings.themeLight,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
              DropdownMenuItem<ThemePreference>(
                value: ThemePreference.dark,
                child: Text(
                  AppStrings.themeDark,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

/// 设备头部：图标 + 名称（居中显示）
class _DeviceHeader extends StatelessWidget {
  final String deviceName;
  final DeviceInfo? info;

  const _DeviceHeader({required this.deviceName, this.info});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Center(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              _iconForType(info?.typeIcon),
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            deviceName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(DeviceTypeIcon? type) {
    return switch (type) {
      DeviceTypeIcon.windows => Icons.desktop_windows,
      DeviceTypeIcon.mac => Icons.laptop_mac,
      DeviceTypeIcon.linux => Icons.computer,
      DeviceTypeIcon.android => Icons.android,
      DeviceTypeIcon.ios => Icons.phone_iphone,
      DeviceTypeIcon.web => Icons.language,
      null => Icons.devices,
    };
  }
}

/// 共享内容图标
class _SharedContentIcon extends StatelessWidget {
  const _SharedContentIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          colors: [Colors.redAccent, Colors.pinkAccent],
        ),
      ),
      child: const Icon(Icons.folder, color: Colors.white, size: 18),
    );
  }
}

Widget _buildSectionTitle(BuildContext context, String title) {
  final colors = AppColorScheme.of(context);
  return Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// 显示共享内容弹窗（根据平台区分：手机端 Sheet / 桌面端右侧抽屉）
void _showSharedContentSheet(BuildContext context, WidgetRef ref) {
  if (PlatformUtils.isDesktop) {
    // 桌面端：从右侧弹出的抽屉
    showSharedContentDesktopDrawer(context);
  } else {
    // 手机端：可拖拽底部 Sheet，默认 2/3 高度，最高到顶
    Pop.sheet<void>(
      SheetConfig<void>(
        direction: SheetDirection.bottom,
        header: const SheetHeaderConfig(
          title: AppStrings.sharedContent,
          showCloseButton: false,
        ),
        size: const SheetSizeConfig(
          height: SheetDimension.fraction(0.67),
          maxHeight: SheetDimension.fraction(1.0),
        ),
        drag: const SheetDragConfig(
          showHandle: true,
          mode: SheetDragDismissMode.fullBody,
        ),
        builder: (context, handle) {
          return const SharedContentMobileBody();
        },
      ),
    );
  }
}

/// 手机端关于弹窗（居中显示）
void _showMobileAboutDialog(BuildContext context, WidgetRef ref) {
  final deviceInfo = ref.read(deviceInfoProvider);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AboutDialog(info: deviceInfo.value);
    },
  );
}

/// 居中关于弹窗
class _AboutDialog extends StatelessWidget {
  final DeviceInfo? info;

  const _AboutDialog({this.info});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题：关于软件
            Text(
              AppStrings.aboutTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            // 详情表格：液态玻璃质感（参考 tabbar 效果）
            LiquidGlassContainer(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // 表格信息密集首行紧贴顶部，关闭顶部高光避免"玻璃里嵌玻璃"的细边
              sheen: false,
              child: Column(
                children: [
                  _NeuInfoRow(
                    label: AppStrings.aboutAppName,
                    value: AppStrings.appName,
                  ),
                  Divider(height: 1, color: colors.divider),
                  _NeuInfoRow(
                    label: AppStrings.aboutVersion,
                    value: AppStrings.appVersion,
                  ),
                  Divider(height: 1, color: colors.divider),
                  _NeuInfoRow(
                    label: AppStrings.aboutDeviceModel,
                    value: info?.model ?? '—',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 关闭按钮（带边框）
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.inputBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(AppStrings.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
