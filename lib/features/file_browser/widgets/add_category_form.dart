import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/glass_switch.dart';
import '../models/file_category.dart';
import '../providers/file_browser_provider.dart';

/// 常见文件后缀名
const commonFileExtensions = [
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic',
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'rmvb', 'ts',
  'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma',
  'txt', 'md', 'log', 'rtf', 'doc', 'docx', 'pdf',
  'xls', 'xlsx', 'csv',
  'ppt', 'pptx',
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2',
  'dart', 'java', 'kt', 'py', 'js', 'ts', 'html', 'css',
  'json', 'xml', 'yaml', 'yml', 'go', 'rs', 'rb', 'php', 'sh',
  'c', 'cpp', 'h',
  'apk', 'exe', 'dmg', 'iso',
];

/// 可选分类图标
const categoryIcons = [
  Icons.image, Icons.video_file, Icons.audio_file, Icons.description,
  Icons.table_chart, Icons.slideshow, Icons.picture_as_pdf,
  Icons.folder_zip, Icons.code, Icons.android, Icons.folder,
  Icons.photo_library, Icons.movie, Icons.music_note, Icons.book,
  Icons.archive, Icons.insert_drive_file, Icons.folder_open,
  Icons.work, Icons.school, Icons.business, Icons.home,
  Icons.star, Icons.favorite, Icons.lightbulb, Icons.flight,
  Icons.shopping_bag, Icons.sports, Icons.restaurant, Icons.pets,
  Icons.computer, Icons.phone, Icons.tablet, Icons.watch,
  Icons.camera, Icons.headphones, Icons.gamepad, Icons.newspaper,
];

/// 添加分类表单（桌面抽屉和手机弹窗共用）
class AddCategoryForm extends ConsumerStatefulWidget {
  /// 保存成功回调，传入分类名称
  final void Function(String name)? onSaved;

  const AddCategoryForm({super.key, this.onSaved});

  @override
  ConsumerState<AddCategoryForm> createState() => _AddCategoryFormState();
}

class _AddCategoryFormState extends ConsumerState<AddCategoryForm> {
  final _nameController = TextEditingController();
  IconData _selectedIcon = Icons.folder;
  final List<String> _selectedTypes = [];
  bool _selectAll = false;
  final _typeInputController = TextEditingController();
  final _iconLayerLink = LayerLink();
  final _typeLayerLink = LayerLink();
  OverlayEntry? _iconOverlay;
  OverlayEntry? _typeOverlay;
  bool _showTypeSuggestions = false;

  @override
  void dispose() {
    _nameController.dispose();
    _typeInputController.dispose();
    _iconOverlay?.remove();
    _typeOverlay?.remove();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final category = FileCategory(
      name: name,
      icon: _selectedIcon,
      fileTypes: _selectAll ? const [] : List.from(_selectedTypes),
      selectAll: _selectAll,
    );

    ref.read(customCategoriesProvider.notifier).addCategory(category);
    widget.onSaved?.call(name);
  }

  void _toggleIconPicker() {
    if (_iconOverlay != null) {
      _iconOverlay?.remove();
      _iconOverlay = null;
      return;
    }

    _iconOverlay = OverlayEntry(
      builder: (context) => _IconPickerOverlay(
        layerLink: _iconLayerLink,
        selectedIcon: _selectedIcon,
        isMobile: PlatformUtils.isMobile,
        onSelect: (icon) {
          setState(() => _selectedIcon = icon);
          _iconOverlay?.remove();
          _iconOverlay = null;
        },
        onDismiss: () {
          _iconOverlay?.remove();
          _iconOverlay = null;
        },
      ),
    );
    Overlay.of(context).insert(_iconOverlay!);
  }

  void _toggleTypePicker() {
    if (_showTypeSuggestions) {
      _typeOverlay?.remove();
      _typeOverlay = null;
      setState(() => _showTypeSuggestions = false);
      return;
    }

    setState(() => _showTypeSuggestions = true);
    _typeOverlay = OverlayEntry(
      builder: (context) => _FileTypePickerOverlay(
        layerLink: _typeLayerLink,
        selectedTypes: _selectedTypes,
        searchText: _typeInputController.text,
        isMobile: PlatformUtils.isMobile,
        onSelect: (ext) {
          setState(() {
            if (!_selectedTypes.contains(ext)) {
              _selectedTypes.add(ext);
            }
            _typeInputController.clear();
          });
          _typeOverlay?.remove();
          _typeOverlay = null;
          setState(() => _showTypeSuggestions = false);
        },
        onDismiss: () {
          _typeOverlay?.remove();
          _typeOverlay = null;
          setState(() => _showTypeSuggestions = false);
        },
      ),
    );
    Overlay.of(context).insert(_typeOverlay!);
  }

  void _addCustomType() {
    final text = _typeInputController.text.trim().toLowerCase();
    if (text.isNotEmpty && !_selectedTypes.contains(text)) {
      setState(() {
        _selectedTypes.add(text);
        _typeInputController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分类名称
        Text(
          AppStrings.categoryName,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          maxLength: 5,
          decoration: InputDecoration(
            hintText: '请输入分类名称（最多5个字）',
            hintStyle: TextStyle(color: colors.textHint),
            filled: true,
            fillColor: colors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          style: TextStyle(color: colors.textPrimary),
        ),
        const SizedBox(height: 20),

        // 分类图标
        Text(
          AppStrings.categoryIcon,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _iconLayerLink,
          child: GestureDetector(
            onTap: _toggleIconPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.inputBorder),
              ),
              child: Row(
                children: [
                  Icon(_selectedIcon, size: 22, color: colors.iconActive),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '点击选择图标',
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: colors.iconSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 全选开关
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.inputBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.selectAllFiles,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      AppStrings.selectAllFilesSub,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GlassSwitch(
                value: _selectAll,
                onChanged: (v) => setState(() => _selectAll = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 文件类型选择（全选开启时禁用）
        if (!_selectAll) ...[
          Text(
            AppStrings.fileType,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          CompositedTransformTarget(
            link: _typeLayerLink,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _typeInputController,
                    onTap: _toggleTypePicker,
                    onChanged: (value) {
                      if (_typeOverlay != null) {
                        _typeOverlay?.remove();
                        _typeOverlay = null;
                        setState(() => _showTypeSuggestions = false);
                      }
                      _toggleTypePicker();
                    },
                    decoration: InputDecoration(
                      hintText: AppStrings.fileTypeHint,
                      hintStyle: TextStyle(color: colors.textHint),
                      filled: true,
                      fillColor: colors.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.inputBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: _addCustomType,
                      ),
                    ),
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          // 已选文件类型 chips
          if (_selectedTypes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedTypes.map((ext) {
                return Chip(
                  label: Text(
                    '.$ext',
                    style: TextStyle(fontSize: 12, color: colors.textPrimary),
                  ),
                  deleteIcon: Icon(Icons.close, size: 16, color: colors.iconSecondary),
                  onDeleted: () {
                    setState(() => _selectedTypes.remove(ext));
                  },
                  backgroundColor: colors.inputBg,
                  side: BorderSide(color: colors.inputBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ],

        const SizedBox(height: 24),

        // 保存按钮
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(AppStrings.saveCategory),
          ),
        ),
      ],
    );
  }
}

/// 图标选择器浮层
class _IconPickerOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final IconData selectedIcon;
  final bool isMobile;
  final ValueChanged<IconData> onSelect;
  final VoidCallback onDismiss;

  const _IconPickerOverlay({
    required this.layerLink,
    required this.selectedIcon,
    required this.isMobile,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    // 手机端向上显示，桌面端向下显示
    final targetAnchor = isMobile ? Alignment.topLeft : Alignment.bottomLeft;
    final followerAnchor = isMobile ? Alignment.bottomLeft : Alignment.topLeft;
    final offset = isMobile ? const Offset(0, -8) : const Offset(0, 8);

    return Stack(
      children: [
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        CompositedTransformFollower(
          link: layerLink,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: offset,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: colors.cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: categoryIcons.length,
                  itemBuilder: (context, index) {
                    final icon = categoryIcons[index];
                    final isSelected = icon == selectedIcon;
                    return GestureDetector(
                      onTap: () => onSelect(icon),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.primaryWithAlpha(0.12)
                              : colors.inputBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? colors.primaryWithAlpha(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 22,
                          color: isSelected
                              ? colors.iconActive
                              : colors.iconSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 文件类型选择器浮层
class _FileTypePickerOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final List<String> selectedTypes;
  final String searchText;
  final bool isMobile;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  const _FileTypePickerOverlay({
    required this.layerLink,
    required this.selectedTypes,
    required this.searchText,
    required this.isMobile,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final targetAnchor = isMobile ? Alignment.topLeft : Alignment.bottomLeft;
    final followerAnchor = isMobile ? Alignment.bottomLeft : Alignment.topLeft;
    final offset = isMobile ? const Offset(0, -8) : const Offset(0, 8);

    final filtered = commonFileExtensions
        .where((ext) =>
            ext.toLowerCase().contains(searchText.toLowerCase()) &&
            !selectedTypes.contains(ext))
        .toList();

    return Stack(
      children: [
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        CompositedTransformFollower(
          link: layerLink,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: offset,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: colors.cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '无匹配结果，可直接输入后点击 + 添加',
                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final ext = filtered[index];
                          return InkWell(
                            onTap: () => onSelect(ext),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.primaryWithAlpha(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '.$ext',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: colors.iconActive,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
