import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../home/card_tile.dart';

/// 过期箱：按过期时间倒序，可恢复或删除应用副本。
class ArchivePage extends StatelessWidget {
  const ArchivePage({
    super.key,
    required this.controller,
    required this.onOpenCard,
  });

  final AppController controller;
  final void Function(String cardId) onOpenCard;

  @override
  Widget build(BuildContext context) {
    final expired = controller.expiredCards;
    final done = controller.doneCards;
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('过期箱'), floating: true),
        if (expired.isEmpty && done.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('过期或完成的卡片会自动收纳到这里')),
          ),
        if (expired.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('已过期'),
            ),
          ),
          SliverList.builder(
            itemCount: expired.length,
            itemBuilder: (context, i) => Dismissible(
              key: ValueKey(expired[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 28),
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Icon(Icons.delete_outline),
              ),
              confirmDismiss: (_) => _confirmDelete(context),
              onDismissed: (_) => controller.deleteCard(expired[i].id),
              child: Column(
                children: [
                  CardTile(
                    controller: controller,
                    card: expired[i],
                    onTap: () => onOpenCard(expired[i].id),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: TextButton(
                        onPressed: () async {
                          await controller.restoreCard(expired[i].id);
                          if (context.mounted) {
                            onOpenCard(expired[i].id); // 引导重设时间
                          }
                        },
                        child: const Text('恢复并重设时间'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (done.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('已完成/已归档'),
            ),
          ),
          SliverList.builder(
            itemCount: done.length,
            itemBuilder: (context, i) => CardTile(
              controller: controller,
              card: done[i],
              onTap: () => onOpenCard(done[i].id),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除应用内副本？'),
          content: const Text('不会影响你图库中的原始截图。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}
