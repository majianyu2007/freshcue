import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/core/utils/id_gen.dart';
import 'package:freshcue/core/utils/redactor.dart';
import 'package:freshcue/domain/entities/reminder.dart';
import 'package:freshcue/domain/entities/temporal_card.dart';
import 'package:freshcue/domain/enums/enums.dart';
import 'package:freshcue/domain/services/freshness_policy.dart';
import 'package:freshcue/domain/services/reminder_policy.dart';

void main() {
  final now = DateTime(2026, 7, 18, 10, 0);

  TemporalCard card({
    DateTime? deadline,
    DateTime? start,
    DateTime? end,
    DateTime? expiry,
    CardCategory category = CardCategory.event,
    bool sensitive = false,
  }) =>
      TemporalCard(
        id: 'c1',
        title: '测试卡片',
        category: category,
        status: CardStatus.active,
        deadlineAt: deadline,
        eventStartAt: start,
        eventEndAt: end,
        expiresAt: expiry,
        isSensitive: sensitive,
        createdAt: now,
        updatedAt: now,
      );

  group('FreshnessPolicy 状态边界', () {
    const policy = FreshnessPolicy();

    test('距离 >24h → fresh', () {
      final c = card(start: now.add(const Duration(days: 3)));
      expect(policy.evaluate(c, now), Freshness.fresh);
    });
    test('恰好 24h → upcoming', () {
      final c = card(start: now.add(const Duration(hours: 24)));
      expect(policy.evaluate(c, now), Freshness.upcoming);
    });
    test('2h 内 → urgent', () {
      final c = card(start: now.add(const Duration(minutes: 90)));
      expect(policy.evaluate(c, now), Freshness.urgent);
    });
    test('过了失效时间 → expired', () {
      final c = card(expiry: now.subtract(const Duration(minutes: 1)));
      expect(policy.evaluate(c, now), Freshness.expired);
    });
    test('全部关键时间已过 → expired', () {
      final c = card(start: now.subtract(const Duration(hours: 5)));
      expect(policy.evaluate(c, now), Freshness.expired);
    });
    test('无任何时间 → fresh', () {
      expect(policy.evaluate(card(), now), Freshness.fresh);
    });
    test('下一关键时间取最早未来项', () {
      final c = card(
        deadline: now.add(const Duration(days: 2)),
        start: now.add(const Duration(days: 7)),
      );
      expect(c.nextKeyTime(now)!.$1, TemporalRole.deadline);
      expect(policy.describeNext(c, now), contains('截止'));
      expect(policy.describeNext(c, now), contains('2 天'));
    });
  });

  group('ReminderPolicy', () {
    const policy = ReminderPolicy();
    String nid() => IdGen.newId();

    test('event 默认模板展开（1天/1小时/10分钟 + 截止2项）', () {
      final c = card(
        start: now.add(const Duration(days: 10)),
        deadline: now.add(const Duration(days: 5)),
      );
      final plans = policy.defaultPlans(c, nid);
      expect(plans.length, 5);
      final r = policy.expand(c, plans, now, nid);
      expect(r.instances.length, 5);
    });

    test('跳过已过去的提醒，不影响其他实例', () {
      final c = card(start: now.add(const Duration(hours: 5)));
      final plans = policy.defaultPlans(c, nid); // 提前1天已不可能
      final r = policy.expand(c, plans, now, nid);
      expect(r.instances.length, 2); // 1小时 + 10分钟
      expect(r.notes.join(), contains('已跳过'));
    });

    test('同一触发时间去重', () {
      final c = card(start: now.add(const Duration(days: 2)));
      final plans = [
        ReminderPlan(id: nid(), cardId: 'c1', anchorRole: TemporalRole.eventStart, offsetMinutes: 60),
        ReminderPlan(id: nid(), cardId: 'c1', anchorRole: TemporalRole.eventStart, offsetMinutes: 60),
      ];
      expect(policy.expand(c, plans, now, nid).instances.length, 1);
    });

    test('非紧急提醒落入安静时段被调整并说明', () {
      // 开始时间 23:30，提前 1 天触发 → 23:30 处于安静时段。
      final c = card(start: DateTime(2026, 7, 25, 23, 30));
      final plans = [
        ReminderPlan(id: nid(), cardId: 'c1', anchorRole: TemporalRole.eventStart, offsetMinutes: 1440),
      ];
      final r = policy.expand(c, plans, now, nid);
      expect(r.instances.single.triggerAt.hour, 7);
      expect(r.notes.join(), contains('安静时段'));
    });

    test('紧急提醒（提前<12h）不受安静时段影响', () {
      final c = card(start: DateTime(2026, 7, 19, 0, 30));
      final plans = [
        ReminderPlan(id: nid(), cardId: 'c1', anchorRole: TemporalRole.eventStart, offsetMinutes: 30),
      ];
      final r = policy.expand(c, plans, now, nid);
      expect(r.instances.single.triggerAt, DateTime(2026, 7, 19, 0, 0));
    });

    test('temporarySecret 模板不响铃且锁屏隐藏', () {
      final c = card(
        category: CardCategory.temporarySecret,
        expiry: now.add(const Duration(hours: 2)),
        sensitive: true,
      );
      final plans = policy.defaultPlans(c, nid);
      expect(plans.single.sound, isFalse);
      expect(plans.single.hideOnLockScreen, isTrue);
    });

    test('snooze 创建新实例并记录来源', () {
      final src = ReminderInstance(
        id: 'i1', cardId: 'c1', planId: 'p1',
        triggerAt: now, status: ReminderStatus.fired,
        createdAt: now, updatedAt: now,
      );
      final s = policy.snooze(src, const Duration(minutes: 10), now, nid);
      expect(s.snoozedFromInstanceId, 'i1');
      expect(s.triggerAt, now.add(const Duration(minutes: 10)));
    });

    test('plan 描述可读', () {
      final p = ReminderPlan(
        id: 'p', cardId: 'c', anchorRole: TemporalRole.deadline, offsetMinutes: 1440,
      );
      expect(p.describe(), '截止前 1 天');
    });
  });

  group('敏感文本遮罩', () {
    test('手机号脱敏', () {
      expect(Redactor.redact('联系 13812345678'), isNot(contains('13812345678')));
    });
    test('身份证脱敏', () {
      expect(
        Redactor.redact('号码110101199003077578'),
        isNot(contains('199003077578')),
      );
    });
    test('URL query 脱敏', () {
      expect(
        Redactor.redact('https://x.com/a?token=secret123'),
        isNot(contains('secret123')),
      );
    });
    test('秘密值遮罩保留首尾', () {
      expect(Redactor.maskSecret('A7281'), 'A•••1');
      expect(Redactor.maskSecret('42'), '••');
    });
  });
}
