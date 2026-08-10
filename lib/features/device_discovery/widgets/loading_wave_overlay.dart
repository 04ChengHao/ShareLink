import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// 连接中波浪动画叠加层
class LoadingWaveOverlay extends StatefulWidget {
  final Widget child;
  final bool active;

  const LoadingWaveOverlay({
    super.key,
    required this.child,
    required this.active,
  });

  @override
  State<LoadingWaveOverlay> createState() => _LoadingWaveOverlayState();
}

class _LoadingWaveOverlayState extends State<LoadingWaveOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant LoadingWaveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _ctrl.repeat();
    } else if (!widget.active && oldWidget.active) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final dx = _ctrl.value * 3 - 1; // -1.0 → 2.0
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(dx - 0.5, 0),
                        end: Alignment(dx + 0.5, 0),
                        colors: [
                          AppColors.primary.withValues(alpha: 0.0),
                          AppColors.primary.withValues(alpha: 0.12),
                          AppColors.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
