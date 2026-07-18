import '../core/clock/clock.dart';
import '../core/errors/app_failure.dart';
import '../core/logging/app_log.dart';
import '../core/utils/id_gen.dart';
import '../core/utils/redactor.dart';
import '../domain/entities/reminder.dart';
import '../domain/entities/temporal_card.dart';
import '../domain/enums/enums.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/reminder_policy.dart';
import '../platform/gateways.dart';
import 'database/image_asset_service.dart';

/// 应用服务：卡片全生命周期编排。
/// 数据库是提醒意图的事实来源，系统 Reminder Agent 是执行层。
class CardService {
  CardService({
    required this.cards,
    required this.assets,
    required this.ocrBlocks,
    required this.reminders,
    required this.reminderGateway,
    required this.assetService,
    required this.clock,
    this.policy = const ReminderPolicy(),
  });

  final CardRepository cards;
  final AssetRepository assets;
  final OcrBlockRepository ocrBlocks;
  final ReminderRepository reminders;
  final ReminderGateway reminderGateway;
  final ImageAssetService assetService;
  final Clock clock;
  final ReminderPolicy policy;

  /// 确认草稿：保存卡片 + 计划 + 实例，并调度系统提醒。
  /// 返回调度失败的实例数（>0 时 UI 显示可恢复错误，不假装全部成功）。
  Future<int> confirmCard(
    TemporalCard card,
    List<ReminderPlan> plans, {
    List<ReminderInstance>? precomputedInstances,
  }) async {
    final now = clock.now();
    final confirmed = card.copyWith(
      status: CardStatus.active,
      confirmedAt: now,
      updatedAt: now,
    );
    try {
      await cards.save(confirmed);
      await reminders.savePlans(card.id, plans);
    } catch (e) {
      throw AppFailure(
        FailureCode.databaseWriteFailed, debugDetail: e.runtimeType.toString(),
      );
    }
    final instances = precomputedInstances ??
        policy.expand(confirmed, plans, now, IdGen.newId).instances;
    return _scheduleAll(confirmed, instances);
  }

  /// 编辑关键时间后：取消旧提醒 → 重新展开 → 原子化重建。
  Future<int> rebuildReminders(TemporalCard card) async {
    final now = clock.now();
    await _cancelAllPlatform(card.id);
    final plans = await reminders.plansByCard(card.id);
    final instances = policy.expand(card, plans, now, IdGen.newId).instances;
    await cards.save(card.copyWith(updatedAt: now));
    return _scheduleAll(card, instances);
  }

  Future<int> _scheduleAll(
    TemporalCard card,
    List<ReminderInstance> instances,
  ) async {
    var failures = 0;
    final saved = <ReminderInstance>[];
    for (final inst in instances) {
      try {
        final available = await reminderGateway.isAvailable();
        if (!available) {
          throw const AppFailure(FailureCode.reminderScheduleFailed,
              debugDetail: 'gateway unavailable',);
        }
        final pid = await reminderGateway.scheduleCalendarReminder(
          _payloadFor(card, inst),
        );
        saved.add(inst.copyWith(platformReminderId: pid));
      } on AppFailure catch (f) {
        failures++;
        AppLog.w('reminder', '调度失败: ${f.code.name}');
        saved.add(
          inst.copyWith(
            status: ReminderStatus.failed,
            failureReason: f.code.name,
          ),
        );
      }
    }
    await reminders.replaceInstances(card.id, saved);
    return failures;
  }

  ReminderPayload _payloadFor(TemporalCard card, ReminderInstance inst) {
    final next = card.nextKeyTime(inst.triggerAt);
    final semantic = next == null ? '' : '（${next.$1.label}）';
    // 敏感内容遮罩：正文不携带 secretValue 原文。
    final body = card.isSensitive
        ? '${card.title}$semantic 内容已隐藏'
        : '${card.title}$semantic'
            '${card.location == null ? '' : ' @${card.location}'}';
    return ReminderPayload(
      instanceId: inst.id,
      cardId: card.id,
      title: card.isSensitive ? 'FreshCue 提醒' : card.title,
      body: Redactor.redact(body),
      triggerAt: inst.triggerAt,
      hideContentOnLockScreen: card.isSensitive,
    );
  }

  Future<void> _cancelAllPlatform(String cardId) async {
    for (final inst in await reminders.instancesByCard(cardId)) {
      final pid = inst.platformReminderId;
      if (pid != null && inst.status == ReminderStatus.scheduled) {
        try {
          await reminderGateway.cancelReminder(pid);
        } on AppFailure catch (f) {
          AppLog.w('reminder', '取消失败: ${f.code.name}');
        }
      }
    }
  }

  Future<void> complete(String cardId) => _setStatus(cardId, CardStatus.completed);

  Future<void> archive(String cardId) => _setStatus(cardId, CardStatus.archived);

  /// 恢复为 active（过期箱），调用方随后应引导用户重设时间。
  Future<void> restore(String cardId) => _setStatus(cardId, CardStatus.active);

  Future<void> _setStatus(String cardId, CardStatus status) async {
    final card = await cards.findById(cardId);
    if (card == null) throw const AppFailure(FailureCode.cardNotFound);
    if (status != CardStatus.active) await _cancelAllPlatform(cardId);
    await cards.save(card.copyWith(status: status, updatedAt: clock.now()));
  }

  /// 删除：先取消系统提醒 → 删数据库关联 → 删沙箱图片。
  Future<void> deleteCard(String cardId) async {
    final card = await cards.findById(cardId);
    if (card == null) return;
    await _cancelAllPlatform(cardId);
    await reminders.deleteByCard(cardId);
    await ocrBlocks.deleteByCard(cardId);
    final assetId = card.sourceAssetId;
    await cards.delete(cardId);
    if (assetId != null) {
      final asset = await assets.findById(assetId);
      if (asset != null) {
        await assets.delete(assetId);
        assetService.deleteFiles(asset); // 只删沙箱副本，不碰图库
      }
    }
  }

  /// 通知行为处理（同一行为只执行一次由桥接层保证）。
  Future<void> handleAction(ReminderActionEvent e) async {
    switch (e.action) {
      case ReminderActionType.complete:
        await complete(e.cardId);
      case ReminderActionType.snooze10m:
        await _snooze(e, const Duration(minutes: 10));
      case ReminderActionType.snooze1h:
        await _snooze(e, const Duration(hours: 1));
      case ReminderActionType.viewSource:
      case ReminderActionType.opened:
        break; // 路由层负责跳转
    }
  }

  Future<void> _snooze(ReminderActionEvent e, Duration delay) async {
    final card = await cards.findById(e.cardId);
    if (card == null) return;
    final all = await reminders.instancesByCard(e.cardId);
    final src = all.where((i) => i.id == e.instanceId).firstOrNull;
    if (src == null) return;
    final now = clock.now();
    await reminders.saveInstance(
      src.copyWith(status: ReminderStatus.fired, updatedAt: now),
    );
    var snoozed = policy.snooze(src, delay, now, IdGen.newId);
    try {
      final pid = await reminderGateway
          .scheduleCalendarReminder(_payloadFor(card, snoozed));
      snoozed = snoozed.copyWith(platformReminderId: pid);
    } on AppFailure catch (f) {
      snoozed = snoozed.copyWith(
        status: ReminderStatus.failed, failureReason: f.code.name,
      );
    }
    await reminders.saveInstance(snoozed);
  }

  /// 启动 reconciliation：
  /// 1) 清理已过期但仍标记 scheduled 的实例；
  /// 2) 检查未来实例是否有平台 ID，缺失则补建。
  Future<void> reconcile() async {
    final now = clock.now();
    final scheduled = await reminders.allScheduledInstances();
    for (final inst in scheduled) {
      if (!inst.triggerAt.isAfter(now)) {
        await reminders.saveInstance(
          inst.copyWith(status: ReminderStatus.fired, updatedAt: now),
        );
        continue;
      }
      if (inst.platformReminderId == null) {
        final card = await cards.findById(inst.cardId);
        if (card == null || card.status != CardStatus.active) continue;
        try {
          final pid = await reminderGateway
              .scheduleCalendarReminder(_payloadFor(card, inst));
          await reminders.saveInstance(
            inst.copyWith(platformReminderId: pid, updatedAt: now),
          );
        } on AppFailure catch (f) {
          AppLog.w('reconcile', '补建提醒失败: ${f.code.name}');
        }
      }
    }
  }
}
