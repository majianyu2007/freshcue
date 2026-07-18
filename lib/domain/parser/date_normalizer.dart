import 'time_span_extractor.dart';

/// 归一化结果：锚定后的绝对时间及解释。
class NormalizedTime {
  const NormalizedTime({
    required this.dateTime,
    required this.confidence,
    this.endDateTime,
    this.hasExplicitTime = false,
    this.requiresConfirmation = false,
    this.explanation = '',
  });

  final DateTime dateTime;
  final DateTime? endDateTime;
  final bool hasExplicitTime;
  final bool requiresConfirmation;
  final String explanation;
  final double confidence;
}

/// 将 TimeSpan 锚定到 [anchor]（截图导入时间，本地时区）并归一化为绝对时间。
///
/// 年份推断规则（§14.3）：
/// - 无年份时优先推断为相对锚点最近且合理的未来日期；
/// - 跨年推断需要确认页突出显示；
/// - 候选日期已过去且在 [historicalToleranceDays] 内 → 视为可能的历史截图，
///   保留当年并标记 requiresConfirmation，不自动滚到下一年。
class DateNormalizer {
  const DateNormalizer({this.historicalToleranceDays = 60});

  final int historicalToleranceDays;

  NormalizedTime? normalize(TimeSpan span, DateTime anchor) {
    switch (span.kind) {
      case SpanKind.absoluteDateTime:
      case SpanKind.monthDay:
        return _normalizeDate(span, anchor);
      case SpanKind.dateRange:
        return _normalizeDateRange(span, anchor);
      case SpanKind.relativeDay:
        return _normalizeRelative(span, anchor);
      case SpanKind.weekday:
        return _normalizeWeekday(span, anchor);
      case SpanKind.timeRange:
        return _normalizeTimeRange(span, anchor);
      case SpanKind.timeOnly:
        // 独立时刻默认锚定当天；由聚合层尝试与邻近日期合并。
        final t = DateTime(
          anchor.year,
          anchor.month,
          anchor.day,
          span.hour!,
          span.minute ?? 0,
        );
        return NormalizedTime(
          dateTime: t,
          hasExplicitTime: true,
          confidence: 0.4,
          requiresConfirmation: true,
          explanation: '仅识别到时刻，默认按导入当天理解，请确认日期',
        );
    }
  }

  NormalizedTime? _normalizeDate(TimeSpan span, DateTime anchor) {
    final (hour, minute) = _resolveClock(span, defaultHour: 0);
    DateTime? endOf(DateTime dt) => span.endHour == null
        ? null
        : DateTime(
            dt.year,
            dt.month,
            dt.day,
            span.endHour!,
            span.endMinute ?? 0,
          );
    if (span.year != null) {
      if (!_isValidDate(span.year!, span.month!, span.day!)) return null;
      final dt = DateTime(span.year!, span.month!, span.day!, hour, minute);
      return NormalizedTime(
        dateTime: dt,
        endDateTime: endOf(dt),
        hasExplicitTime: span.hasExplicitTime,
        confidence: 0.95,
        requiresConfirmation: dt.isBefore(anchor),
        explanation: dt.isBefore(anchor) ? '该时间早于导入时间，可能是历史截图' : '',
      );
    }
    final inferred = _inferYear(
      span.month!,
      span.day!,
      hour,
      minute,
      anchor,
      hasExplicitTime: span.hasExplicitTime,
    );
    if (inferred == null || span.endHour == null) return inferred;
    return NormalizedTime(
      dateTime: inferred.dateTime,
      endDateTime: endOf(inferred.dateTime),
      hasExplicitTime: inferred.hasExplicitTime,
      confidence: inferred.confidence,
      requiresConfirmation: inferred.requiresConfirmation,
      explanation: inferred.explanation,
    );
  }

  NormalizedTime? _normalizeDateRange(TimeSpan span, DateTime anchor) {
    final start = _inferYear(
      span.month!,
      span.day!,
      0,
      0,
      anchor,
      hasExplicitTime: false,
    );
    if (start == null) return null;
    var end = DateTime(
      start.dateTime.year,
      span.endMonth!,
      span.endDay!,
      23,
      59,
    );
    if (end.isBefore(start.dateTime)) {
      end = DateTime(
        start.dateTime.year + 1,
        span.endMonth!,
        span.endDay!,
        23,
        59,
      );
    }
    return NormalizedTime(
      dateTime: start.dateTime,
      endDateTime: end,
      hasExplicitTime: false,
      confidence: start.confidence,
      requiresConfirmation: start.requiresConfirmation,
      explanation: start.explanation,
    );
  }

  NormalizedTime _normalizeRelative(TimeSpan span, DateTime anchor) {
    final (hour, minute) = _resolveClock(span);
    final day = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).add(Duration(days: span.relativeDays!));
    final dt = DateTime(day.year, day.month, day.day, hour, minute);
    return NormalizedTime(
      dateTime: dt,
      hasExplicitTime: span.hasExplicitTime,
      confidence: span.hasExplicitTime ? 0.9 : 0.6,
      requiresConfirmation: !span.hasExplicitTime,
      explanation: '相对日期按截图导入时间（${anchor.month}月${anchor.day}日）锚定',
    );
  }

  NormalizedTime _normalizeWeekday(TimeSpan span, DateTime anchor) {
    final (hour, minute) = _resolveClock(span);
    final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
    var delta = span.weekdayIndex! - anchorDay.weekday;
    delta += 7 * span.weekOffset!;
    var requiresConfirmation = !span.hasExplicitTime;
    var explanation = '按截图导入时间所在周锚定';
    if (span.weekOffset == 0 && delta < 0) {
      // “本周X”已过去：不自动移到下周，让用户确认。
      requiresConfirmation = true;
      explanation = '“本周”对应日期已过去，请确认';
    }
    final day = anchorDay.add(Duration(days: delta));
    return NormalizedTime(
      dateTime: DateTime(day.year, day.month, day.day, hour, minute),
      hasExplicitTime: span.hasExplicitTime,
      confidence: span.hasExplicitTime ? 0.85 : 0.55,
      requiresConfirmation: requiresConfirmation,
      explanation: explanation,
    );
  }

  NormalizedTime _normalizeTimeRange(TimeSpan span, DateTime anchor) {
    final start = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
      span.hour!,
      span.minute!,
    );
    final end = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
      span.endHour!,
      span.endMinute!,
    );
    return NormalizedTime(
      dateTime: start,
      endDateTime: end,
      hasExplicitTime: true,
      confidence: 0.5,
      requiresConfirmation: true,
      explanation: '时间段未指明日期，默认按导入当天理解，请确认日期',
    );
  }

  NormalizedTime? _inferYear(
    int month,
    int day,
    int hour,
    int minute,
    DateTime anchor, {
    required bool hasExplicitTime,
  }) {
    // 2月29日等：找最近的合法年份（处理闰年）。
    var year = anchor.year;
    while (!_isValidDate(year, month, day)) {
      year++;
      if (year > anchor.year + 8) return null;
    }
    var dt = DateTime(year, month, day, hour, minute);

    if (dt.isBefore(anchor)) {
      final daysPast = anchor.difference(dt).inDays;
      if (daysPast <= historicalToleranceDays) {
        // 可能是历史截图：保留当年，标记确认。
        return NormalizedTime(
          dateTime: dt,
          hasExplicitTime: hasExplicitTime,
          confidence: 0.5,
          requiresConfirmation: true,
          explanation: '截图未包含年份，该日期已过去，可能是历史信息，请确认年份',
        );
      }
      // 推断为下一年最近未来（跨年，需突出显示）。
      var nextYear = year + 1;
      while (!_isValidDate(nextYear, month, day)) {
        nextYear++;
        if (nextYear > anchor.year + 8) return null;
      }
      dt = DateTime(nextYear, month, day, hour, minute);
      return NormalizedTime(
        dateTime: dt,
        hasExplicitTime: hasExplicitTime,
        confidence: 0.7,
        requiresConfirmation: true,
        explanation: '截图未包含年份，已按最近未来日期推断为 $nextYear 年（跨年），请确认',
      );
    }
    final crossYear = dt.year != anchor.year;
    return NormalizedTime(
      dateTime: dt,
      hasExplicitTime: hasExplicitTime,
      confidence: 0.85,
      requiresConfirmation: crossYear,
      explanation: crossYear
          ? '截图未包含年份，已按最近未来日期推断为 ${dt.year} 年（跨年），请确认'
          : '截图未包含年份，按 ${dt.year} 年理解',
    );
  }

  /// 解析时刻，处理 上午/下午/晚上/中午/凌晨。
  /// [defaultHour]：无任何时刻线索时的缺省小时（日期类为 0，口语相对日为 9）。
  (int, int) _resolveClock(TimeSpan span, {int defaultHour = 9}) {
    var hour =
        span.hour ??
        (span.dayPeriod != null
            ? _defaultHourFor(span.dayPeriod)
            : defaultHour);
    final minute = span.minute ?? 0;
    final period = span.dayPeriod;
    if (period != null && span.hour != null && hour < 12) {
      switch (period) {
        case '下午' when hour != 12:
        case '晚上' when hour != 12:
          hour += 12;
        case '中午' when hour < 11:
          hour += 12;
      }
    }
    return (hour, minute);
  }

  static int _defaultHourFor(String? period) => switch (period) {
    '上午' => 9,
    '中午' => 12,
    '下午' => 14,
    '晚上' => 20,
    '凌晨' => 1,
    _ => 9,
  };

  static bool _isValidDate(int y, int m, int d) {
    final dt = DateTime(y, m, d);
    return dt.year == y && dt.month == m && dt.day == d;
  }
}
