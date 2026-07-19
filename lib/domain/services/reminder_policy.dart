import '../entities/reminder.dart';
import '../entities/temporal_card.dart';
import '../enums/enums.dart';

/// 提醒策略：默认模板、实例展开、去重、跳过过去、安静时段调整。
class ReminderPolicy {
  const ReminderPolicy({
    this.quietHoursEnabled = true,
    this.quietStartHour = 23,
    this.quietEndHour = 7,
    this.frequency = ReminderFrequency.standard,
  });

  final bool quietHoursEnabled;
  final int quietStartHour;
  final int quietEndHour;
  final ReminderFrequency frequency;

  /// 按分类生成默认提醒意图（分钟提前量；0=准时）。
  List<ReminderPlan> defaultPlans(TemporalCard card, String Function() newId) {
    final plans = <ReminderPlan>[];
    void add(TemporalRole role, int offset, {bool sound = true}) {
      if (card.anchorFor(role) == null) return;
      plans.add(
        ReminderPlan(
          id: newId(),
          cardId: card.id,
          anchorRole: role,
          offsetMinutes: offset,
          sound: sound,
          hideOnLockScreen: card.isSensitive,
        ),
      );
    }

    switch (card.category) {
      case CardCategory.pickup:
        add(TemporalRole.expiry, 30);
      case CardCategory.event:
        add(TemporalRole.eventStart, 1440);
        add(TemporalRole.eventStart, 60);
        add(TemporalRole.eventStart, 10);
        add(TemporalRole.deadline, 1440);
        add(TemporalRole.deadline, 120);
      case CardCategory.study:
        add(TemporalRole.eventStart, 1440);
        add(TemporalRole.eventStart, 60);
        add(TemporalRole.eventStart, 10);
        add(TemporalRole.deadline, 1440);
        add(TemporalRole.deadline, 120);
      case CardCategory.healthcare:
        add(TemporalRole.eventStart, 1440);
        add(TemporalRole.eventStart, 60);
        add(TemporalRole.expiry, 1440);
      case CardCategory.ticket:
        add(TemporalRole.eventStart, 1440);
        add(TemporalRole.eventStart, 120);
        add(TemporalRole.eventStart, 30);
      case CardCategory.bill:
        add(TemporalRole.deadline, 4320);
        add(TemporalRole.deadline, 1440);
        add(TemporalRole.deadline, 120);
      case CardCategory.renewal:
        add(TemporalRole.expiry, 10080);
        add(TemporalRole.expiry, 1440);
      case CardCategory.coupon:
        add(TemporalRole.expiry, 1440);
        add(TemporalRole.expiry, 120);
      case CardCategory.deadline:
        add(TemporalRole.deadline, 1440);
        add(TemporalRole.deadline, 120);
        add(TemporalRole.deadline, 15);
      case CardCategory.temporarySecret:
        // 不响铃，仅到期前静默提醒。
        add(TemporalRole.expiry, 30, sound: false);
      case CardCategory.generic:
        add(TemporalRole.expiry, 60);
    }
    return _applyFrequency(plans);
  }

  List<ReminderPlan> _applyFrequency(List<ReminderPlan> plans) {
    if (frequency == ReminderFrequency.thorough || plans.length <= 1) {
      return plans;
    }
    final byRole = <TemporalRole, List<ReminderPlan>>{};
    for (final plan in plans) {
      byRole.putIfAbsent(plan.anchorRole, () => []).add(plan);
    }
    return [
      for (final group in byRole.values)
        if (frequency == ReminderFrequency.light)
          group.last
        else if (group.length <= 2)
          ...group
        else ...[
          group.first,
          group.last,
        ],
    ];
  }

  /// 将意图展开为绝对触发时间的实例。
  ///
  /// 规则：跳过已过去的时间（不影响其他实例）；同一触发时间去重；
  /// 非紧急提醒（提前量 >= 12 小时）落入安静时段时移出并记录说明。
  ExpansionResult expand(
    TemporalCard card,
    List<ReminderPlan> plans,
    DateTime now,
    String Function() newId,
  ) {
    final instances = <ReminderInstance>[];
    final notes = <String>[];
    final seen = <DateTime>{};

    for (final plan in plans.where((p) => p.enabled)) {
      final anchor = card.anchorFor(plan.anchorRole);
      if (anchor == null) continue;
      var trigger = anchor.subtract(Duration(minutes: plan.offsetMinutes));

      final urgent = plan.offsetMinutes < 720;
      if (!urgent && _inQuietHours(trigger)) {
        final adjusted = _shiftOutOfQuietHours(trigger);
        notes.add(
          '「${plan.describe()}」原定 ${_fmt(trigger)} 处于安静时段，已调整为 ${_fmt(adjusted)}',
        );
        trigger = adjusted;
      }

      if (!trigger.isAfter(now)) {
        notes.add('「${plan.describe()}」时间已过，已跳过');
        continue;
      }
      if (!seen.add(trigger)) continue; // 去重

      instances.add(
        ReminderInstance(
          id: newId(),
          cardId: card.id,
          planId: plan.id,
          triggerAt: trigger,
          status: ReminderStatus.scheduled,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    instances.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    return ExpansionResult(instances, notes);
  }

  /// 延后提醒：基于来源实例创建新实例。
  ReminderInstance snooze(
    ReminderInstance source,
    Duration delay,
    DateTime now,
    String Function() newId,
  ) => ReminderInstance(
    id: newId(),
    cardId: source.cardId,
    planId: source.planId,
    triggerAt: now.add(delay),
    status: ReminderStatus.scheduled,
    snoozedFromInstanceId: source.id,
    createdAt: now,
    updatedAt: now,
  );

  bool _inQuietHours(DateTime t) =>
      quietHoursEnabled && (t.hour >= quietStartHour || t.hour < quietEndHour);

  DateTime _shiftOutOfQuietHours(DateTime t) {
    // 移动到安静时段结束（次日或当日 07:00）。
    final day = t.hour >= quietStartHour ? t.add(const Duration(days: 1)) : t;
    return DateTime(day.year, day.month, day.day, quietEndHour);
  }

  static String _fmt(DateTime t) =>
      '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class ExpansionResult {
  const ExpansionResult(this.instances, this.notes);
  final List<ReminderInstance> instances;

  /// 需要在确认页向用户说明的调整（安静时段、跳过项）。
  final List<String> notes;
}
