import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_link/core/constants/app_strings.dart';
import 'package:unified_popups/unified_popups.dart';
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'shared/widgets/window_manager_stub.dart';

import 'core/constants/app_colors.dart';
import 'core/providers/global_providers.dart';
import 'core/utils/platform_utils.dart';
import 'features/device_discovery/providers/device_provider.dart';
import 'features/device_discovery/views/device_discovery_view.dart';
import 'features/file_browser/views/file_browser_view.dart';
import 'features/settings/views/settings_view.dart';
import 'shared/themes/app_theme.dart';
import 'shared/widgets/glass_nav_bar.dart';
import 'shared/widgets/neuomorphic_style.dart';
import 'shared/widgets/window_title_bar.dart';

class ShareLinkApp extends ConsumerWidget {
  const ShareLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      navigatorObservers: [Pop.routeObserver],
      builder: Pop.hostBuilder,
      home: PlatformUtils.isDesktop
          ? const DesktopShell()
          : const MobileShell(),
    );
  }
}

/// 手机端外壳：悬浮胶囊底部导航
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    DeviceDiscoveryView(),
    FileBrowserView(),
    SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 手机锁屏/切后台后恢复前台时，重启发现服务快速重新发现设备
    // （Android Doze 模式会挂起 UDP socket，导致设备被判定离线）
    // 注意：只重启 UDP 发现服务，不中断已建立的 WebSocket 连接
    if (state == AppLifecycleState.resumed) {
      if (ref.read(connectionEnabledProvider)) {
        ref.read(deviceServiceProvider).restartDiscovery().catchError((_) {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _pages[_currentIndex],
      bottomNavigationBar: GlassNavBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          GlassNavDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: AppStrings.tabbarHome,
          ),
          GlassNavDestination(
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder,
            label: AppStrings.tabbarFiles,
          ),
          GlassNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: AppStrings.tabbarSettings,
          ),
        ],
      ),
    );
  }
}

/// 桌面端外壳：玻璃侧边栏（带滑动胶囊 + 悬浮文字）
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell>
    with WindowListener {
  int _currentIndex = 0;
  int _hoveredIndex = -1;

  static const _entries = <_DesktopNavEntry>[
    _DesktopNavEntry(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: AppStrings.tabbarHome,
    ),
    _DesktopNavEntry(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: AppStrings.tabbarFiles,
    ),
    _DesktopNavEntry(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: AppStrings.tabbarSettings,
    ),
  ];

  static const _itemSize = 48.0;
  static const _itemSpacing = 8.0;
  static const _sidebarHPadding = 12.0;
  static const _sidebarMargin = 12.0;

  @override
  void initState() {
    super.initState();
    // 桌面端：拦截窗口关闭按钮，改为最小化到托盘
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // 点击关闭按钮时隐藏窗口到托盘，而非退出应用
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final activeColor = theme.colorScheme.primary;

    final pages = [
      const DeviceDiscoveryView(),
      const FileBrowserView(),
      const SettingsView(),
    ];

    // 侧边栏总宽度（含 margin）
    final sidebarWidth = _itemSize + _sidebarHPadding * 2;
    final sidebarOffset = sidebarWidth + _sidebarMargin;

    return Scaffold(
      body: Stack(
        children: [
          // Layer 1: 页面内容（先绘制，底层）
          // ClipRect 防止页面内容溢出到侧边栏区域
          Positioned(
            top: 0,
            bottom: 0,
            left: sidebarOffset,
            right: 0,
            child: ClipRect(
              child: Stack(
                children: [
                  pages[_currentIndex],
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: WindowTitleBar(),
                  ),
                ],
              ),
            ),
          ),
          // Layer 2: 侧边栏（后绘制，顶层）
          // 确保悬浮胶囊文字可超出侧边栏显示在页面内容之上
          Positioned(
            top: _sidebarMargin,
            bottom: _sidebarMargin,
            left: _sidebarMargin,
            child: Container(
              width: sidebarWidth,
              padding: const EdgeInsets.symmetric(
                horizontal: _sidebarHPadding,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: colors.glassBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: NeuomorphicStyle.adaptive(
                  theme.brightness,
                  blur: 20,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const logoSize = 40.0;
                  final itemsHeight =
                      _entries.length * _itemSize +
                      (_entries.length - 1) * _itemSpacing;
                  final navStartY =
                      logoSize +
                      (constraints.maxHeight - logoSize - itemsHeight) / 2;

                  final isHovering = _hoveredIndex >= 0;
                  // 激活胶囊：固定在当前选中项位置
                  final activeY =
                      navStartY + _currentIndex * (_itemSize + _itemSpacing);
                  // 悬浮胶囊：跟随鼠标所在项，悬浮在任何 tab（含激活项）时都显示
                  final hoverY =
                      navStartY + _hoveredIndex * (_itemSize + _itemSpacing);
                  final showHoverCapsule = isHovering;
                  final hoverEntry = isHovering
                      ? _entries[_hoveredIndex]
                      : null;
                  // 悬浮在激活项上时，隐藏激活胶囊避免重叠
                  final showActiveCapsule =
                      !(isHovering && _hoveredIndex == _currentIndex);

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // ===== 胶囊层（背景，IgnorePointer）=====

                      // 激活胶囊：蓝色主题，在 tab 间平滑滑动
                      // 悬浮在激活项上时隐藏，避免与悬浮胶囊重叠
                      if (showActiveCapsule)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          top: activeY,
                          left: 0,
                          height: _itemSize,
                          child: IgnorePointer(
                            child: Container(
                              width: _itemSize,
                              decoration: BoxDecoration(
                                color: activeColor.withValues(
                                  alpha: isDark ? 0.3 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: activeColor.withValues(
                                    alpha: isDark ? 0.5 : 0.3,
                                  ),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: activeColor.withValues(alpha: 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // 悬浮胶囊：白色底，独立于激活胶囊，可向右扩展显示文字
                      if (showHoverCapsule && hoverEntry != null)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          top: hoverY,
                          left: 0,
                          height: _itemSize,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.3 : 0.1,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(width: _itemSize),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 16),
                                    child: Text(
                                      hoverEntry.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF1C1C1E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ===== 内容层（Logo + 所有图标，交互）=====
                      Column(
                        children: [
                          // Logo
                          Container(
                            width: logoSize,
                            height: logoSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF007AFF), Color(0xFF5AC8FA)],
                              ),
                            ),
                            child: const Icon(
                              Icons.link,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const Spacer(),
                          // 所有导航项（图标始终可见 + 可交互）
                          ...List.generate(_entries.length, (index) {
                            final isSelected = index == _currentIndex;
                            final item = _entries[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index < _entries.length - 1
                                    ? _itemSpacing
                                    : 0,
                              ),
                              child: MouseRegion(
                                onEnter: (_) =>
                                    setState(() => _hoveredIndex = index),
                                onExit: (_) {
                                  if (_hoveredIndex == index) {
                                    setState(() => _hoveredIndex = -1);
                                  }
                                },
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _currentIndex = index),
                                  behavior: HitTestBehavior.opaque,
                                  child: SizedBox(
                                    width: _itemSize,
                                    height: _itemSize,
                                    child: Icon(
                                      isSelected
                                          ? item.selectedIcon
                                          : item.icon,
                                      size: 24,
                                      color: isSelected
                                          ? activeColor
                                          : (isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.5,
                                                  )
                                                : colors.iconSecondary),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          const Spacer(),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavEntry {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _DesktopNavEntry({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
