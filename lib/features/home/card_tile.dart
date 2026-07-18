import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/utils/redactor.dart';
import '../../domain/entities/temporal_card.dart';

/// 卡片列表项：分类图标、标题、下一关键时间语义、状态、缩略图。
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.controller,
    required this.card,
    required this.onTap,
  });

  final AppController controller;
  final TemporalCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = controller.clock.now();
    final freshness = controller.freshness.evaluate(card, now);
    final color =
        AppTheme.freshnessColor(freshness, Theme.of(context).brightness);
    final subtitle = controller.freshness.describeNext(card, now);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(AppTheme.categoryIcon(card.category),
                  size: 28, color: Theme.of(context).colorScheme.primary,),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(AppTheme.freshnessIcon(freshness),
                            size: 15, color: color,),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (card.location != null || card.secretValue != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          card.secretValue != null
                              ? '码 ${Redactor.maskSecret(card.secretValue!)}'
                              : card.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusChip(label: freshness.label, color: color),
                  const SizedBox(height: 6),
                  _Thumb(controller: controller, card: card),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.controller, required this.card});
  final AppController controller;
  final TemporalCard card;

  @override
  Widget build(BuildContext context) {
    if (card.sourceAssetId == null) return const SizedBox(width: 36, height: 36);
    return FutureBuilder(
      future: controller.assets.findById(card.sourceAssetId!),
      builder: (context, snap) {
        final path = snap.data?.thumbnailPath ?? snap.data?.sandboxPath;
        if (path == null || !File(path).existsSync()) {
          return const SizedBox(width: 36, height: 36);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            width: 36, height: 36, fit: BoxFit.cover, cacheWidth: 72,
          ),
        );
      },
    );
  }
}

/// Mock 能力横幅（Debug 专用）。
class MockBanner extends StatelessWidget {
  const MockBanner({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.amber.shade700,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined, size: 14, color: Colors.black87),
              SizedBox(width: 6),
              Text(
                '模拟能力模式：OCR/提醒为 Mock，未连接鸿蒙系统能力',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
        ),
      );
}
