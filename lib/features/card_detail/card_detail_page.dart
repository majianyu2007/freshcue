import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/redactor.dart';
import '../../domain/entities/temporal_card.dart';
import '../../domain/enums/enums.dart';

/// 详情页：原图证据、字段、提醒时间线、操作。
class CardDetailPage extends StatefulWidget {
  const CardDetailPage({
    super.key,
    required this.controller,
    required this.cardId,
  });

  final AppController controller;
  final String cardId;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  bool secretRevealed = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TemporalCard?>(
      future: widget.controller.cards.findById(widget.cardId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final card = snap.data;
        if (card == null) {
          // 深链目标已删除 → 安全失败。
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('卡片不存在或已被删除')),
          );
        }
        return _build(context, card);
      },
    );
  }

  Widget _build(BuildContext context, TemporalCard card) {
    final now = widget.controller.clock.now();
    final freshness = widget.controller.freshness.evaluate(card, now);
    final color = AppTheme.freshnessColor(
      freshness,
      Theme.of(context).brightness,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(v, card),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'archive', child: Text('归档')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(AppTheme.categoryIcon(card.category), color: color),
              const SizedBox(width: 8),
              Text(card.category.label),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${card.status.label} · ${freshness.label}',
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.controller.freshness.describeNext(card, now),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
          const SizedBox(height: 16),
          _sourceImage(card),
          const SizedBox(height: 16),
          if (card.location != null)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(card.location!),
              contentPadding: EdgeInsets.zero,
            ),
          if (card.secretValue != null)
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(
                secretRevealed
                    ? card.secretValue!
                    : Redactor.maskSecret(card.secretValue!),
                style: const TextStyle(letterSpacing: 2),
              ),
              trailing: IconButton(
                icon: Icon(
                  secretRevealed ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => secretRevealed = !secretRevealed),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          const Divider(height: 32),
          Text('关键时间', style: Theme.of(context).textTheme.titleMedium),
          for (final (role, at) in card.keyTimes)
            ListTile(
              leading: Icon(
                at.isAfter(now) ? Icons.schedule : Icons.check,
                color: at.isAfter(now) ? null : Theme.of(context).disabledColor,
              ),
              title: Text('${role.label} ${formatDateTime(at)}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          const SizedBox(height: 8),
          Text('提醒时间线', style: Theme.of(context).textTheme.titleMedium),
          _reminderTimeline(card, now),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                  onPressed: card.status == CardStatus.active
                      ? () async {
                          await widget.controller.completeCard(card.id);
                          if (context.mounted) Navigator.pop(context);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('改时间'),
                  onPressed: () => _editTime(card),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _liveViewButton(card, now),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sourceImage(TemporalCard card) {
    if (card.sourceAssetId == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder(
      future: widget.controller.assets.findById(card.sourceAssetId!),
      builder: (context, snap) {
        final path = snap.data?.sandboxPath;
        if (path == null || !File(path).existsSync()) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }

  Widget _reminderTimeline(TemporalCard card, DateTime now) => FutureBuilder(
    future: widget.controller.reminders.instancesByCard(card.id),
    builder: (context, snap) {
      final instances = snap.data ?? const [];
      if (instances.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('未启用提醒'),
        );
      }
      return Column(
        children: [
          for (final i in instances)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (i.status) {
                  ReminderStatus.scheduled =>
                    Icons.notifications_active_outlined,
                  ReminderStatus.fired => Icons.notifications_none,
                  ReminderStatus.snoozed => Icons.snooze,
                  ReminderStatus.cancelled => Icons.notifications_off_outlined,
                  ReminderStatus.failed => Icons.error_outline,
                },
                color: i.status == ReminderStatus.failed
                    ? AppTheme.urgentColor
                    : null,
              ),
              title: Text(formatDateTime(i.triggerAt)),
              subtitle: i.status == ReminderStatus.failed
                  ? Text('创建失败：${i.failureReason ?? '未知'}')
                  : null,
              trailing: Text(switch (i.status) {
                ReminderStatus.scheduled => '已调度',
                ReminderStatus.fired => '已触发',
                ReminderStatus.snoozed => '已延后',
                ReminderStatus.cancelled => '已取消',
                ReminderStatus.failed => '失败',
              }),
            ),
        ],
      );
    },
  );

  Widget _liveViewButton(TemporalCard card, DateTime now) {
    // 只在 pickup/ticket/短时 event 且有未来关键时间时提供入口。
    final eligible = switch (card.category) {
      CardCategory.pickup || CardCategory.ticket => true,
      CardCategory.event => true,
      _ => false,
    };
    final next = card.nextKeyTime(now);
    if (!eligible || next == null || card.status != CardStatus.active) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.timelapse),
      label: const Text('开启实况胶囊（实验能力）'),
      onPressed: () async {
        final lv = widget.controller.liveView;
        try {
          if (!await lv.isSupported() || !await lv.hasEntitlement()) {
            throw const AppFailure(FailureCode.liveViewNotEntitled);
          }
          if (!await lv.isEnabledByUser()) {
            throw const AppFailure(FailureCode.liveViewDisabled);
          }
          await lv.startCountdown(
            cardId: card.id,
            title: card.title,
            targetAt: next.$2,
            scene: card.category.name,
          );
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('实况胶囊已开启（实验能力）')));
          }
        } on AppFailure catch (f) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(f.userMessage)));
          }
        }
      },
    );
  }

  Future<void> _editTime(TemporalCard card) async {
    final now = widget.controller.clock.now();
    final next = card.nextKeyTime(now) ?? card.keyTimes.firstOrNull;
    final base = next?.$2 ?? now;
    final role = next?.$1 ?? TemporalRole.expiry;
    final date = await showDatePicker(
      context: context,
      initialDate: base.isAfter(now) ? base : now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    final newAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final updated = switch (role) {
      TemporalRole.deadline => card.copyWith(deadlineAt: newAt),
      TemporalRole.eventStart => card.copyWith(eventStartAt: newAt),
      TemporalRole.eventEnd => card.copyWith(eventEndAt: newAt),
      TemporalRole.expiry => card.copyWith(expiresAt: newAt),
      _ => card.copyWith(expiresAt: newAt),
    };
    final failures = await widget.controller.updateCardTimes(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures > 0 ? '时间已更新，$failures 条提醒重建失败' : '时间已更新，提醒已重建',
          ),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _onMenu(String action, TemporalCard card) async {
    switch (action) {
      case 'archive':
        await widget.controller.archiveCard(card.id);
        if (mounted) Navigator.pop(context);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除卡片？'),
            content: const Text(
              '将删除：卡片、提醒计划、系统提醒、OCR 数据和应用内图片副本。\n'
              '不会影响你图库中的原始截图。',
            ),
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
        );
        if (ok == true) {
          await widget.controller.deleteCard(card.id);
          if (mounted) Navigator.pop(context);
        }
    }
  }
}
