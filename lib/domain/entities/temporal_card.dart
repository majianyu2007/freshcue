import '../enums/enums.dart';

/// 时效卡片：产品核心领域对象。
class TemporalCard {
  const TemporalCard({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourceAssetId,
    this.rawOcrText,
    this.summary,
    this.location,
    this.secretValue,
    this.eventStartAt,
    this.eventEndAt,
    this.deadlineAt,
    this.expiresAt,
    this.capturedAt,
    this.confirmedAt,
    this.overallConfidence = 1.0,
    this.isSensitive = false,
    this.notes,
  });

  final String id;
  final String title;
  final CardCategory category;
  final CardStatus status;
  final String? sourceAssetId;
  final String? rawOcrText;
  final String? summary;
  final String? location;

  /// 敏感值（验证码等）；用户界面直接显示，日志仍不得记录。
  final String? secretValue;
  final DateTime? eventStartAt;
  final DateTime? eventEndAt;
  final DateTime? deadlineAt;
  final DateTime? expiresAt;
  final DateTime? capturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;

  /// 启发式置信度分数（0~1），不是统计学概率。
  final double overallConfidence;
  final bool isSensitive;
  final String? notes;

  /// 按角色取锚点时间。
  DateTime? anchorFor(TemporalRole role) => switch (role) {
    TemporalRole.eventStart => eventStartAt,
    TemporalRole.eventEnd => eventEndAt,
    TemporalRole.deadline => deadlineAt,
    TemporalRole.departure => eventStartAt,
    TemporalRole.expiry => expiresAt,
    _ => null,
  };

  /// 所有已设定的关键时间（升序）。
  List<(TemporalRole, DateTime)> get keyTimes {
    final list = <(TemporalRole, DateTime)>[
      if (deadlineAt != null) (TemporalRole.deadline, deadlineAt!),
      if (eventStartAt != null) (TemporalRole.eventStart, eventStartAt!),
      if (eventEndAt != null) (TemporalRole.eventEnd, eventEndAt!),
      if (expiresAt != null) (TemporalRole.expiry, expiresAt!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  /// 相对 [now] 的下一个关键时间；全部已过去时返回 null。
  (TemporalRole, DateTime)? nextKeyTime(DateTime now) {
    for (final kt in keyTimes) {
      if (kt.$2.isAfter(now)) return kt;
    }
    return null;
  }

  /// 最终失效时间：显式 expiresAt，否则最后一个关键时间。
  DateTime? get effectiveExpiry {
    if (expiresAt != null) return expiresAt;
    final times = keyTimes;
    return times.isEmpty ? null : times.last.$2;
  }

  TemporalCard copyWith({
    String? title,
    CardCategory? category,
    CardStatus? status,
    String? sourceAssetId,
    String? rawOcrText,
    String? summary,
    Object? location = _sentinel,
    Object? secretValue = _sentinel,
    Object? eventStartAt = _sentinel,
    Object? eventEndAt = _sentinel,
    Object? deadlineAt = _sentinel,
    Object? expiresAt = _sentinel,
    DateTime? capturedAt,
    DateTime? updatedAt,
    DateTime? confirmedAt,
    double? overallConfidence,
    bool? isSensitive,
    String? notes,
  }) => TemporalCard(
    id: id,
    title: title ?? this.title,
    category: category ?? this.category,
    status: status ?? this.status,
    sourceAssetId: sourceAssetId ?? this.sourceAssetId,
    rawOcrText: rawOcrText ?? this.rawOcrText,
    summary: summary ?? this.summary,
    location: location == _sentinel ? this.location : location as String?,
    secretValue: secretValue == _sentinel
        ? this.secretValue
        : secretValue as String?,
    eventStartAt: eventStartAt == _sentinel
        ? this.eventStartAt
        : eventStartAt as DateTime?,
    eventEndAt: eventEndAt == _sentinel
        ? this.eventEndAt
        : eventEndAt as DateTime?,
    deadlineAt: deadlineAt == _sentinel
        ? this.deadlineAt
        : deadlineAt as DateTime?,
    expiresAt: expiresAt == _sentinel ? this.expiresAt : expiresAt as DateTime?,
    capturedAt: capturedAt ?? this.capturedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    overallConfidence: overallConfidence ?? this.overallConfidence,
    isSensitive: isSensitive ?? this.isSensitive,
    notes: notes ?? this.notes,
  );

  static const _sentinel = Object();
}
