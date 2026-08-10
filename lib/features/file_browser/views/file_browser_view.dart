import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart' show AppColorScheme, AppColors;
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/device_icon_utils.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/glass_dropdown.dart';
import '../../../shared/widgets/neuomorphic_style.dart';
import '../../../shared/widgets/segmented_tab.dart';
import '../../device_discovery/models/device.dart';
import '../models/file_category.dart';
import '../models/file_item.dart';
import '../providers/file_browser_provider.dart';
import '../widgets/add_category_drawer.dart';
import '../widgets/add_category_sheet.dart';
import '../widgets/file_list_item.dart';

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
        // 右侧：排序方向切换按钮
        GestureDetector(
          onTap: () => ref.read(sortAscendingProvider.notifier).toggle(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sortAscending
                  ? colors.primaryWithAlpha(0.15)
                  : colors.inputBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sortAscending
                    ? colors.primaryWithAlpha(0.5)
                    : colors.inputBorder,
              ),
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
                      ? colors.iconActive
                      : colors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  sortAscending ? '正序' : '倒序',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sortAscending
                        ? colors.iconActive
                        : colors.textSecondary,
                  ),
                ),
              ],
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
                onRemoveCategory: (name) {
                  ref.read(customCategoriesProvider.notifier).removeCategory(name);
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
class _FileContentArea extends StatelessWidget {
  final bool timelineGroup;
  final bool extensionGroup;
  final bool showFileName;
  final int crossAxisCount;
  final List<FileItem> files;
  final List<TimelineGroup> timelineGroups;
  final List<ExtensionGroup> extensionGroups;
  final List<NestedTimelineGroup> nestedGroups;

  const _FileContentArea({
    required this.timelineGroup,
    required this.extensionGroup,
    required this.showFileName,
    required this.crossAxisCount,
    required this.files,
    required this.timelineGroups,
    required this.extensionGroups,
    required this.nestedGroups,
  });

  @override
  Widget build(BuildContext context) {
    // 时间轴 + 后缀嵌套分组（时间轴优先）
    if (timelineGroup && extensionGroup) {
      return _TimelineExtensionView(
        groups: nestedGroups,
        showFileName: showFileName,
        crossAxisCount: crossAxisCount,
      );
    }
    // 仅时间轴分组
    if (timelineGroup) {
      return _TimelineView(
        groups: timelineGroups,
        showFileName: showFileName,
        crossAxisCount: crossAxisCount,
      );
    }
    // 仅后缀分组
    if (extensionGroup) {
      return _ExtensionView(
        groups: extensionGroups,
        showFileName: showFileName,
        crossAxisCount: crossAxisCount,
      );
    }
    // 平铺模式
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = _calcCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: files.length,
          itemBuilder: (context, index) => FileListItem(
            file: files[index],
            showFileName: showFileName,
          ),
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
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAddCategory,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        AppStrings.addCategory,
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.inputBorder),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isCustomSelected) ...[
                  const SizedBox(width: 8),
                  SizedBox(
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
    final colors = AppColorScheme.of(context);

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
                  SegmentedTabItem(value: CategoryDisplayMode.dropdown, icon: Icons.arrow_drop_down_circle),
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
                onRemoveCategory: (name) {
                  ref.read(customCategoriesProvider.notifier).removeCategory(name);
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
                onRemoveCategory: (name) {
                  ref.read(customCategoriesProvider.notifier).removeCategory(name);
                },
              ),
            // 筛选条件栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const _FilterBar(),
            ),
            // 文件内容区
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
  final ValueChanged<String> onRemoveCategory;

  const _MobileDropdownCategoryBar({
    required this.categories,
    required this.selectedCategory,
    required this.onTap,
    required this.onAddCategory,
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
          OutlinedButton(
            onPressed: onAddCategory,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.iconActive,
              side: BorderSide(color: colors.inputBorder),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(44, 44),
            ),
            child: const Icon(Icons.add, size: 20),
          ),
          if (isCustomSelected) ...[
            const SizedBox(width: 8),
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
  final ValueChanged<String> onRemoveCategory;

  const _MobileListCategoryBar({
    required this.categories,
    required this.selectedCategory,
    required this.onTap,
    required this.onAddCategory,
    required this.onRemoveCategory,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
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
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onAddCategory,
                    icon: Icon(Icons.add, size: 18, color: colors.iconActive),
                    label: Text(
                      AppStrings.addCategory,
                      style: TextStyle(fontSize: 13, color: colors.iconActive),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.iconActive,
                      side: BorderSide(color: colors.inputBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              if (isCustomSelected)
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

  const _TimelineView({
    required this.groups,
    required this.showFileName,
    required this.crossAxisCount,
  });

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    return Row(
      children: [
        // 文件列表（隐藏原生滚动条）
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
              itemCount: widget.groups.length,
            itemBuilder: (context, groupIndex) {
              final group = widget.groups[groupIndex];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间标签
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.primaryWithAlpha(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            group.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.iconActive,
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
                  // 文件网格
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: widget.crossAxisCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 2,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: group.files.length,
                    itemBuilder: (context, index) => FileListItem(
                      file: group.files[index],
                      showFileName: widget.showFileName,
                    ),
                  ),
                ],
              );
            },
          ),
          ),
        ),
        // 右侧时间轴进度条（3/4 高度）
        _TimelineScrollbar(
          groups: widget.groups,
          scrollController: _scrollController,
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

  const _ExtensionView({
    required this.groups,
    required this.showFileName,
    required this.crossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: groups.length,
        itemBuilder: (context, groupIndex) {
          final group = groups[groupIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primaryWithAlpha(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        group.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.iconActive,
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
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: group.files.length,
                itemBuilder: (context, index) => FileListItem(
                  file: group.files[index],
                  showFileName: showFileName,
                ),
              ),
            ],
          );
        },
      ),
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

  const _TimelineExtensionView({
    required this.groups,
    required this.showFileName,
    required this.crossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: groups.length,
        itemBuilder: (context, groupIndex) {
          final group = groups[groupIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 时间轴分组标题
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primaryWithAlpha(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        group.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.iconActive,
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
              // 后缀子分组
              for (final extGroup in group.extensionGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
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
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: extGroup.files.length,
                  itemBuilder: (context, index) => FileListItem(
                    file: extGroup.files[index],
                    showFileName: showFileName,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 右侧时间轴胶囊进度条
class _TimelineScrollbar extends StatefulWidget {
  final List<TimelineGroup> groups;
  final ScrollController scrollController;

  const _TimelineScrollbar({
    required this.groups,
    required this.scrollController,
  });

  @override
  State<_TimelineScrollbar> createState() => _TimelineScrollbarState();
}

class _TimelineScrollbarState extends State<_TimelineScrollbar> {
  double _scrollFraction = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller.hasClients && controller.position.maxScrollExtent > 0) {
      setState(() {
        _scrollFraction = controller.offset / controller.position.maxScrollExtent;
      });
    }
  }

  String get _currentLabel {
    if (widget.groups.isEmpty) return '';
    final index = widget.groups.length > 1
        ? (_scrollFraction * (widget.groups.length - 1)).round()
        : 0;
    return widget.groups[index.clamp(0, widget.groups.length - 1)].label;
  }

  void _onDragUpdate(double localY, double totalHeight) {
    final fraction = (localY / totalHeight).clamp(0.0, 1.0);
    final controller = widget.scrollController;
    if (controller.hasClients && controller.position.maxScrollExtent > 0) {
      controller.jumpTo(fraction * controller.position.maxScrollExtent);
    }
  }

  void _jumpToNearestGroup(double localY, double totalHeight) {
    final fraction = (localY / totalHeight).clamp(0.0, 1.0);
    if (widget.groups.isEmpty) return;
    final index = widget.groups.length > 1
        ? (fraction * (widget.groups.length - 1)).round()
        : 0;
    final clampedIndex = index.clamp(0, widget.groups.length - 1);
    final controller = widget.scrollController;
    if (controller.hasClients && controller.position.maxScrollExtent > 0) {
      final targetFraction = widget.groups.length > 1
          ? clampedIndex / (widget.groups.length - 1)
          : 0.0;
      controller.animateTo(
        targetFraction * controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        // 视觉轨道高度为可用空间的 3/4，触摸区域与视觉一致
        final visualHeight = trackHeight * 0.75;

        const containerWidth = 40.0;
        const trackWidth = 6.0;
        final trackLeft = (containerWidth - trackWidth) / 2;

        final thumbWidth = _isDragging ? 30.0 : 20.0;
        final thumbHeight = _isDragging ? 52.0 : 36.0;
        final thumbLeft = (containerWidth - thumbWidth) / 2;
        final thumbY = (_scrollFraction * (visualHeight - thumbHeight))
            .clamp(0.0, visualHeight - thumbHeight);

        return SizedBox(
          width: containerWidth,
          height: trackHeight,
          child: Center(
            child: SizedBox(
              width: containerWidth,
              height: visualHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  _jumpToNearestGroup(details.localPosition.dy, visualHeight);
                },
                onVerticalDragStart: (_) => setState(() => _isDragging = true),
                onVerticalDragUpdate: (details) {
                  _onDragUpdate(details.localPosition.dy, visualHeight);
                },
                onVerticalDragEnd: (_) => setState(() => _isDragging = false),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 轨道（始终居中）
                    Positioned(
                      left: trackLeft,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: trackWidth,
                        decoration: BoxDecoration(
                          color: colors.inputBg,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 拖拽时日期提示
                    if (_isDragging)
                      Positioned(
                        left: -56,
                        top: thumbY + thumbHeight / 2 - 14,
                        child: Container(
                          width: 52,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _currentLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // 胶囊滑块
                    Positioned(
                      left: thumbLeft,
                      top: thumbY,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        width: thumbWidth,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? AppColors.primary
                              : colors.primaryWithAlpha(0.35),
                          borderRadius:
                              BorderRadius.circular(thumbWidth / 2),
                          boxShadow: _isDragging
                              ? [
                                  BoxShadow(
                                    color:
                                        colors.primaryWithAlpha(0.35),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    spreadRadius: 0,
                                  ),
                                ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.compress,
                            size: _isDragging ? 20 : 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: widget.isSelected
                      ? colors.iconActive
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
                          ? colors.iconActive
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
            child: widget.compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: 18,
                        color: widget.isSelected
                            ? colors.iconActive
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
                              ? colors.iconActive
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
                            ? colors.iconActive
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
                                ? colors.iconActive
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
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryWithAlpha(0.12) : colors.glassBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colors.primaryWithAlpha(0.3)
                : colors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? colors.iconActive : colors.iconSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? colors.iconActive : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
