import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 带显示/隐藏切换和一键清除的密码输入框
///
/// 使用稳定的 [TextEditingController] 避免 rebuild 时重建控制器导致
/// 光标重置、输入丢失等问题。
class PasswordInputField extends StatefulWidget {
  /// 初始密码值
  final String value;

  /// 提示语
  final String hintText;

  /// 值变化回调
  final ValueChanged<String> onChanged;

  const PasswordInputField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = '请输入连接密码',
  });

  @override
  State<PasswordInputField> createState() => _PasswordInputFieldState();
}

class _PasswordInputFieldState extends State<PasswordInputField> {
  late final TextEditingController _controller;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant PasswordInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化时同步（例如程序化清空），但避免覆盖用户正在输入的内容
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: _controller,
      obscureText: _obscured,
      // 确保使用主题字体，避免中文提示语字重不一致
      style: theme.textTheme.bodyLarge,
      // 限制 6 位，只允许字母和数字
      maxLength: 6,
      keyboardType: TextInputType.visiblePassword,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
      ],
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
        counterText: '',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 一键清除
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.cancel, size: 18),
                tooltip: '清除',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
                splashRadius: 16,
              ),
            // 显示/隐藏切换
            IconButton(
              icon: Icon(
                _obscured
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              tooltip: _obscured ? '显示密码' : '隐藏密码',
              onPressed: () {
                setState(() {
                  _obscured = !_obscured;
                });
              },
              splashRadius: 16,
            ),
          ],
        ),
      ),
      onChanged: (value) {
        // 过滤后同步
        widget.onChanged(value);
      },
    );
  }
}
