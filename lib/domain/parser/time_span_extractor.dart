/// 时间 span 提取：只负责从文本中定位日期/时间表达并解析出原始成分，
/// 不做语义角色判断（角色由 RoleClassifier 负责）。
library;

/// span 种类。
enum SpanKind {
  absoluteDateTime, // 2026年7月25日 14:00 / 2026-07-25 14:00
  monthDay, // 7月25日（下午2点）/ 7/25 14:00
  relativeDay, // 今天/今晚/明天/后天 (+时刻)
  weekday, // 本周五 18:00 / 下周一下午
  timeRange, // 14:00-16:30
  dateRange, // 7月20日至7月25日
  timeOnly, // 18:00（独立时刻，需与邻近日期合并）
}

/// 提取出的原始时间 span（尚未锚定为绝对时间）。
class TimeSpan {
  TimeSpan({
    required this.kind,
    required this.start,
    required this.end,
    required this.text,
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.dayPeriod,
    this.relativeDays,
    this.weekOffset,
    this.weekdayIndex,
    this.endMonth,
    this.endDay,
    this.endHour,
    this.endMinute,
    this.hasExplicitTime = false,
  });

  final SpanKind kind;
  final int start;
  final int end;
  final String text;
  final int? year;
  final int? month;
  final int? day;
  final int? hour;
  final int? minute;

  /// 上午/下午/晚上/中午/凌晨。
  final String? dayPeriod;

  /// 0=今天，1=明天，2=后天。
  final int? relativeDays;

  /// 0=本周，1=下周。
  final int? weekOffset;

  /// 1=周一 ... 7=周日。
  final int? weekdayIndex;

  // 区间结束成分。
  final int? endMonth;
  final int? endDay;
  final int? endHour;
  final int? endMinute;

  final bool hasExplicitTime;

  bool overlaps(TimeSpan other) => start < other.end && other.start < end;
}

class TimeSpanExtractor {
  // 按优先级排列：先匹配信息量大的组合表达，占用后短表达不再重复匹配。
  static final _patterns = <(SpanKind, RegExp)>[
    // 2026年7月25日 14:00 / 2026年7月25日下午2点 / 截止到...18时
    (
      SpanKind.absoluteDateTime,
      RegExp(
        r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?'
        r'(?:\s*(?:\(|（)?(?:周|星期)[一二三四五六日天](?:\)|）)?)?'
        r'(?:\s*(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})[点时:：](\d{1,2})?分?'
        r'(?:\s*[-—–~至到]\s*(\d{1,2})[点时:：](\d{1,2})?分?)?)?',
      ),
    ),
    // 2026-07-25 14:00 / 2026/07/25 14:00 / 2026.07.25
    (
      SpanKind.absoluteDateTime,
      RegExp(
        r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})'
        r'(?:\s+(\d{1,2}):(\d{2}))?',
      ),
    ),
    // 7月20日至7月25日 / 7月20日-7月25日
    (
      SpanKind.dateRange,
      RegExp(
        r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?\s*[至到~\-—–]\s*'
        r'(?:(\d{1,2})\s*月\s*)?(\d{1,2})\s*[日号]?',
      ),
    ),
    // 7月25日下午2点 / 7月25日 14:00 / 7月20日18时 / 7月31日
    (
      SpanKind.monthDay,
      RegExp(
        r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?'
        r'(?:\s*(?:\(|（)?(?:周|星期)[一二三四五六日天](?:\)|）)?)?'
        r'(?:\s*(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})[点时:：](\d{1,2})?分?'
        r'(?:\s*[-—–~至到]\s*(\d{1,2})[点时:：](\d{1,2})?分?)?)?',
      ),
    ),
    // 7/25 14:00（斜杠月日必须带时刻，避免把分数/编号误判为日期）
    (SpanKind.monthDay, RegExp(r'(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})')),
    // 今晚8点 / 明天下午3点 / 后天上午9:30 / 今天
    (
      SpanKind.relativeDay,
      RegExp(
        r'(今天|今日|今晚|明天|明晚|后天)'
        r'(?:\s*(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})[点时:：](\d{1,2})?分?)?',
      ),
    ),
    // 本周五 18:00 / 下周一下午3点 / 下周一下午 / 周五18:00
    (
      SpanKind.weekday,
      RegExp(
        r'(本|这|下)?(?:周|星期)([一二三四五六日天])'
        r'(?:\s*(上午|下午|晚上|中午|凌晨)?\s*(?:(\d{1,2})[点时:：](\d{1,2})?分?)?)?',
      ),
    ),
    // 14:00-16:30
    (
      SpanKind.timeRange,
      RegExp(r'(\d{1,2}):(\d{2})\s*[-—–~至到]\s*(\d{1,2}):(\d{2})'),
    ),
    // 独立时刻 18:00（需上下文中邻近日期才有意义）
    (SpanKind.timeOnly, RegExp(r'(\d{1,2}):(\d{2})')),
  ];

  /// 提取全部不重叠 span，按出现位置排序。
  List<TimeSpan> extract(String text) {
    final spans = <TimeSpan>[];
    for (final (kind, regex) in _patterns) {
      for (final m in regex.allMatches(text)) {
        final candidate = _build(kind, m);
        if (candidate == null) continue;
        if (spans.any((s) => s.overlaps(candidate))) continue;
        spans.add(candidate);
      }
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    return spans;
  }

  TimeSpan? _build(SpanKind kind, RegExpMatch m) {
    int? p(String? s) => s == null ? null : int.tryParse(s);
    switch (kind) {
      case SpanKind.absoluteDateTime:
        if (m.pattern.pattern.contains('年')) {
          final hour = p(m[5]);
          final month = p(m[2])!;
          final day = p(m[3])!;
          if (!_validMonthDay(month, day)) return null;
          return TimeSpan(
            kind: kind,
            start: m.start,
            end: m.end,
            text: m[0]!,
            year: p(m[1]),
            month: month,
            day: day,
            dayPeriod: m[4],
            hour: hour,
            minute: p(m[6]),
            endHour: p(m[7]),
            endMinute: p(m[8]),
            hasExplicitTime: hour != null,
          );
        }
        final month = p(m[2])!;
        final day = p(m[3])!;
        if (!_validMonthDay(month, day)) return null;
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          year: p(m[1]),
          month: month,
          day: day,
          hour: p(m[4]),
          minute: p(m[5]),
          hasExplicitTime: m[4] != null,
        );
      case SpanKind.dateRange:
        final sm = p(m[1])!;
        final sd = p(m[2])!;
        final em = p(m[3]) ?? sm;
        final ed = p(m[4])!;
        if (!_validMonthDay(sm, sd) || !_validMonthDay(em, ed)) return null;
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          month: sm,
          day: sd,
          endMonth: em,
          endDay: ed,
        );
      case SpanKind.monthDay:
        if (m.pattern.pattern.contains('月')) {
          final month = p(m[1])!;
          final day = p(m[2])!;
          if (!_validMonthDay(month, day)) return null;
          final hour = p(m[4]);
          return TimeSpan(
            kind: kind,
            start: m.start,
            end: m.end,
            text: m[0]!,
            month: month,
            day: day,
            dayPeriod: m[3],
            hour: hour,
            minute: p(m[5]),
            endHour: p(m[6]),
            endMinute: p(m[7]),
            hasExplicitTime: hour != null,
          );
        }
        final month = p(m[1])!;
        final day = p(m[2])!;
        if (!_validMonthDay(month, day)) return null;
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          month: month,
          day: day,
          hour: p(m[3]),
          minute: p(m[4]),
          hasExplicitTime: true,
        );
      case SpanKind.relativeDay:
        final word = m[1]!;
        final rel = switch (word) {
          '今天' || '今日' || '今晚' => 0,
          '明天' || '明晚' => 1,
          '后天' => 2,
          _ => 0,
        };
        var period = m[2];
        if ((word == '今晚' || word == '明晚') && period == null) period = '晚上';
        final hour = p(m[3]);
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          relativeDays: rel,
          dayPeriod: period,
          hour: hour,
          minute: p(m[4]),
          hasExplicitTime: hour != null,
        );
      case SpanKind.weekday:
        const map = {
          '一': 1,
          '二': 2,
          '三': 3,
          '四': 4,
          '五': 5,
          '六': 6,
          '日': 7,
          '天': 7,
        };
        final hour = p(m[4]);
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          weekOffset: m[1] == '下' ? 1 : 0,
          weekdayIndex: map[m[2]]!,
          dayPeriod: m[3],
          hour: hour,
          minute: p(m[5]),
          hasExplicitTime: hour != null,
        );
      case SpanKind.timeRange:
        final h1 = p(m[1])!, mi1 = p(m[2])!, h2 = p(m[3])!, mi2 = p(m[4])!;
        if (h1 > 23 || h2 > 23 || mi1 > 59 || mi2 > 59) return null;
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          hour: h1,
          minute: mi1,
          endHour: h2,
          endMinute: mi2,
          hasExplicitTime: true,
        );
      case SpanKind.timeOnly:
        final h = p(m[1])!, mi = p(m[2])!;
        if (h > 23 || mi > 59) return null;
        return TimeSpan(
          kind: kind,
          start: m.start,
          end: m.end,
          text: m[0]!,
          hour: h,
          minute: mi,
          hasExplicitTime: true,
        );
    }
  }

  static bool _validMonthDay(int month, int day) =>
      month >= 1 && month <= 12 && day >= 1 && day <= 31;
}
