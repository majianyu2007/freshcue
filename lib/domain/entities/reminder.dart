import '../enums/enums.dart';

/// 提醒意图：例如“活动开始前 60 分钟提醒”。
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.cardId,
    required this.anchorRole,
    required this.offsetMinutes,
    this.enabled = true,
    this.sound = true,
    this.vibration = true,
    this.hideOnLockScreen = false,
  });

  final String id;
  final String cardId;

  /// 锚点角色；offsetMinutes 为 0 表示准时，正数表示提前 N 分钟。
  final TemporalRole anchorRole;
  final int offsetMinutes;
  final bool enabled;
  final bool sound;
  final bool vibration;
  final bool hideOnLockScreen;

  /// 中文描述，如“截止前 1 天”。
  String describe() {
    final anchor = anchorRole.label;
    if (offsetMinutes == 0) return '$anchor准时';
    if (offsetMinutes % 1440 == 0) return '$anchor前 ${offsetMinutes ~/ 1440} 天';
    if (offsetMinutes % 60 == 0) return '$anchor前 ${offsetMinutes ~/ 60} 小时';
    return '$anchor前 $offsetMinutes 分钟';
  }
}

/// 提醒实例：解析出的绝对触发时间与平台提醒 ID。
class ReminderInstance {
  const ReminderInstance({
    required this.id,
    required this.cardId,
    required this.planId,
    required this.triggerAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.platformReminderId,
    this.failureReason,
    this.snoozedFromInstanceId,
  });

  final String id;
  final String cardId;
  final String planId;
  final DateTime triggerAt;
  final int? platformReminderId;
  final ReminderStatus status;

  /// 平台调用失败原因（脱敏），供诊断页查看。
  final String? failureReason;

  /// 延后提醒的来源实例。
  final String? snoozedFromInstanceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReminderInstance copyWith({
    int? platformReminderId,
    ReminderStatus? status,
    String? failureReason,
    DateTime? updatedAt,
  }) =>
      ReminderInstance(
        id: id,
        cardId: cardId,
        planId: planId,
        triggerAt: triggerAt,
        platformReminderId: platformReminderId ?? this.platformReminderId,
        status: status ?? this.status,
        failureReason: failureReason ?? this.failureReason,
        snoozedFromInstanceId: snoozedFromInstanceId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
