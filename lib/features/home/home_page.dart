import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
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
      HomeFilter.expiring => cards
          .where((c) =>
              widget.controller.freshness.evaluate(c, now) != Freshness.fresh,)
          .toList(),
      HomeFilter.undated => cards.where((c) => c.keyTimes.isEmpty).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cards = _filtered;
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('截期 FreshCue'),
              Text(
                '截图里的时间，交给我盯着',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          toolbarHeight: 72,
          floating: true,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('导入截图'),
              onPressed: () => startImportFlow(context, widget.controller),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<HomeFilter>(
              segments: const [
                ButtonSegment(value: HomeFilter.all, label: Text('全部')),
                ButtonSegment(value: HomeFilter.expiring, label: Text('即将到期')),
                ButtonSegment(value: HomeFilter.undated, label: Text('无日期')),
              ],
              selected: {filter},
              onSelectionChanged: (s) => setState(() => filter = s.first),
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
              Icon(Icons.schedule_send_outlined,
                  size: 56, color: Theme.of(context).colorScheme.primary,),
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
