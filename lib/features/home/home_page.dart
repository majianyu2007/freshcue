import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/entities/temporal_card.dart';
import '../../domain/enums/enums.dart';
import '../import/import_flow.dart';
import 'card_tile.dart';

enum HomeFilter { all, expiring, undated }

/// 首页：时效箱。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onOpenCard,
  });

  final AppController controller;
  final void Function(String cardId) onOpenCard;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeFilter filter = HomeFilter.all;

  List<TemporalCard> get _filtered {
    final now = widget.controller.clock.now();
    final cards = widget.controller.activeCards;
    return switch (filter) {
      HomeFilter.all => cards,
      HomeFilter.expiring =>
        cards
            .where(
              (c) =>
                  widget.controller.freshness.evaluate(c, now) !=
                  Freshness.fresh,
            )
            .toList(),
      HomeFilter.undated => cards.where((c) => c.keyTimes.isEmpty).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cards = _filtered;
    final now = widget.controller.clock.now();
    final urgentCount = widget.controller.activeCards
        .where(
          (card) =>
              widget.controller.freshness.evaluate(card, now) ==
              Freshness.urgent,
        )
        .length;
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          toolbarHeight: 82,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('截期', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 3),
              Text(
                urgentCount == 0 ? '今天没有紧急事项' : '$urgentCount 件事需要尽快处理',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: urgentCount == 0
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : AppTheme.urgentColor,
                ),
              ),
            ],
          ),
          floating: true,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '收下截图，记住时间',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '图片只在本机识别，确认后再创建提醒。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ImportAction(
                          icon: Icons.add_a_photo_outlined,
                          label: '拍一张',
                          primary: true,
                          onTap: () => startImportFlow(
                            context,
                            widget.controller,
                            initialChoice: 'camera',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ImportAction(
                          icon: Icons.photo_library_outlined,
                          label: '选图片',
                          onTap: () => startImportFlow(
                            context,
                            widget.controller,
                            initialChoice: 'gallery',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ImportAction(
                          icon: Icons.more_horiz,
                          label: '更多',
                          onTap: () =>
                              startImportFlow(context, widget.controller),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 42,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                for (final entry in const [
                  (HomeFilter.all, '全部'),
                  (HomeFilter.expiring, '快到期'),
                  (HomeFilter.undated, '待补时间'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: filter == entry.$1,
                      onSelected: (_) => setState(() => filter = entry.$1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (cards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(controller: widget.controller),
          )
        else
          SliverList.builder(
            itemCount: cards.length,
            itemBuilder: (context, i) => CardTile(
              controller: widget.controller,
              card: cards[i],
              onTap: () => widget.onOpenCard(cards[i].id),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ImportAction extends StatelessWidget {
  const _ImportAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: primary
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Column(
          children: [
            Icon(
              icon,
              size: 21,
              color: primary
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: primary
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule_send_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('还没有时效卡片', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '在聊天、浏览器或图库里看到含时间的截图时，\n'
            '通过系统分享发送给 FreshCue，\n'
            '或点击上方“导入截图”。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              await controller.importDemo();
              if (context.mounted) {
                await openDraftReview(context, controller);
              }
            },
            child: const Text('用演示样例试一试'),
          ),
        ],
      ),
    ),
  );
}
