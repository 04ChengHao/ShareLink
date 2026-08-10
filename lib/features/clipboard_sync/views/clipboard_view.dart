import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/clipboard_provider.dart';
import '../widgets/clipboard_card.dart';

class ClipboardView extends ConsumerWidget {
  const ClipboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(clipboardHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('剪贴板'),
        actions: [
          Switch(
            value: ref.watch(clipboardAutoSyncProvider),
            onChanged: (value) {
              ref.read(clipboardAutoSyncProvider.notifier).enabled = value;
            },
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(child: Text('暂无剪贴板记录'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                return ClipboardCard(item: history[index]);
              },
            ),
    );
  }
}
