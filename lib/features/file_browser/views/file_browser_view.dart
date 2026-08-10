import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/glass_dropdown.dart';
import '../../../shared/widgets/neuomorphic_style.dart';
import '../../device_discovery/providers/device_provider.dart';
import '../providers/file_browser_provider.dart';
import '../widgets/file_list_item.dart';

class FileBrowserView extends ConsumerWidget {
  const FileBrowserView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = PlatformUtils.isDesktop;
    return isDesktop
        ? _DesktopFileBrowser(ref: ref)
        : const _MobileFileBrowser();
  }
}

// ---------------------------------------------------------------------------
// 桌面端文件浏览器
// ---------------------------------------------------------------------------

class _DesktopFileBrowser extends ConsumerWidget {
  final WidgetRef ref;

  const _DesktopFileBrowser({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final files = ref.watch(fileListProvider);
    final selectedCategory = ref.watch(fileCategoryProvider);
    const categories = ['图片', '视频', '文本', 'Word', 'PPT'];
    final selectedDevice = ref.watch(selectedDeviceProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 48, 0, 0),
          child: Row(
            children: [
              // 左侧侧边栏
              Container(
                width: 220,
                margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: NeuomorphicStyle.adaptive(
                    theme.brightness,
                    blur: 20,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题在侧边栏内
                      Text(
                        '文件管理',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '设备',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.of(context).textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SidebarDeviceItem(
                        name: selectedDevice ?? '本机',
                        isSelected: true,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '分类',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.of(context).textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 分类列表：选中和悬浮有胶囊
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: categories.map((category) {
                            return _SidebarCategoryItem(
                              label: category,
                              isSelected: category == selectedCategory,
                              onTap: () {
                                ref
                                        .read(fileCategoryProvider.notifier)
                                        .category =
                                    category;
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 右侧内容区
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 路径：设备__分类
                      _PathBreadcrumb(
                        device: selectedDevice ?? '本机',
                        category: selectedCategory,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = _calcCrossAxisCount(
                              constraints.maxWidth,
                            );
                            return GridView.builder(
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1,
                                  ),
                              itemCount: files.length,
                              itemBuilder: (context, index) =>
                                  FileListItem(file: files[index]),
                            );
                          },
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

  int _calcCrossAxisCount(double width) {
    if (width > 1200) return 8;
    if (width > 900) return 6;
    if (width > 600) return 4;
    return 3;
  }
}

// ---------------------------------------------------------------------------
// 手机端文件浏览器
// ---------------------------------------------------------------------------

class _MobileFileBrowser extends ConsumerWidget {
  const _MobileFileBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(fileListProvider);
    final selectedCategory = ref.watch(fileCategoryProvider);
    const categories = ['图片', '视频', '文本', 'Word', 'PPT'];
    final selectedDevice = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(previouslyConnectedDevicesProvider);
    final colors = AppColorScheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('文件管理', style: TextStyle(color: colors.textPrimary)),
            const SizedBox(width: 12),
            // 设备下拉框
            SizedBox(
              width: 140,
              child: GlassDropdownField<String>(
                value: selectedDevice ?? '本机',
                prefixIcon: Icons.computer,
                items: [
                  DropdownMenuItem<String>(
                    value: '本机',
                    child: Text(
                      '本机',
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    ),
                  ),
                  ...devices.map(
                    (d) => DropdownMenuItem<String>(
                      value: d.name,
                      child: Text(
                        d.name,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textPrimary,
                        ),
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
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 分类筛选
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: categories.map((category) {
                  final isSelected = category == selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: category,
                      isSelected: isSelected,
                      onTap: () {
                        ref.read(fileCategoryProvider.notifier).category =
                            category;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: files.length,
                itemBuilder: (context, index) =>
                    FileListItem(file: files[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 组件
// ---------------------------------------------------------------------------

/// 侧边栏设备项
class _SidebarDeviceItem extends StatefulWidget {
  final String name;
  final bool isSelected;

  const _SidebarDeviceItem({required this.name, required this.isSelected});

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
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
        // Stack: 背景层在下，图标+文字在上，避免被白色覆盖
        child: Stack(
          children: [
            // 背景层：选中蓝色 / 悬浮白色 / 无则透明（填满整个区域）
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? colors.primaryWithAlpha(0.1)
                      : showHover
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            // 内容层：图标 + 文字（带内边距，与胶囊边缘保持间距）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.computer, size: 20, color: colors.iconActive),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 侧边栏分类项（胶囊样式）
class _SidebarCategoryItem extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarCategoryItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
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
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
          // Stack: 背景层在下，图标+文字在上，避免被白色覆盖
          child: Stack(
            children: [
              // 背景层：选中蓝色 / 悬浮白色 / 无则透明（填满整个区域）
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? colors.primaryWithAlpha(0.12)
                        : showHover
                        ? (isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              // 内容层：图标 + 文字（带内边距，与胶囊边缘保持间距）
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isSelected ? Icons.folder : Icons.folder_outlined,
                      size: 18,
                      color: widget.isSelected
                          ? colors.iconActive
                          : colors.iconSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.isSelected
                            ? colors.iconActive
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
    );
  }
}

/// 路径面包屑：设备__分类
class _PathBreadcrumb extends StatelessWidget {
  final String device;
  final String category;

  const _PathBreadcrumb({required this.device, required this.category});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.computer, size: 16, color: colors.iconSecondary),
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
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryWithAlpha(0.12) : colors.glassBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colors.primaryWithAlpha(0.3)
                : colors.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? colors.iconActive : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
