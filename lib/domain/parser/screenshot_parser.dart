import '../../core/utils/id_gen.dart';
import '../entities/source_asset.dart';
import '../enums/enums.dart';
import 'category_classifier.dart';
import 'date_normalizer.dart';
import 'field_extractor.dart';
import 'role_classifier.dart';
import 'time_span_extractor.dart';

/// 解析结果草稿：进入确认页前的全部结构化信息。
class ParsedDraft {
  const ParsedDraft({
    required this.title,
    required this.category,
    required this.categoryExplanation,
    required this.candidates,
    required this.confidenceScore,
    this.location,
    this.secretValue,
    this.isSensitive = false,
    this.highRisk = false,
    this.warnings = const [],
    this.cleanedText = '',
  });

  final String title;
  final CardCategory category;
  final String categoryExplanation;
  final String? location;
  final String? secretValue;
  final bool isSensitive;

  /// 检出身份证/银行卡等高风险信息 → UI 提示不建议保存。
  final bool highRisk;
  final List<TemporalCandidate> candidates;

  /// 启发式总分（0~1），非统计学概率。
  final double confidenceScore;
  final List<String> warnings;
  final String cleanedText;

  /// 建议的卡片锚点（排除 publishTime / unknown）。
  Map<TemporalRole, DateTime> get suggestedAnchors {
    final map = <TemporalRole, DateTime>{};
    for (final c in candidates) {
      final dt = c.normalizedDateTime;
      if (dt == null) continue;
      if (c.role == TemporalRole.publishTime || c.role == TemporalRole.unknown) {
        continue;
      }
      map.putIfAbsent(c.role, () => dt);
      if (c.endDateTime != null && c.role == TemporalRole.eventStart) {
        map.putIfAbsent(TemporalRole.eventEnd, () => c.endDateTime!);
      }
    }
    return map;
  }
}

/// 解析流水线编排：OCR blocks → 清洗 → span → 归一化 → 角色 → 聚合 → 草稿。
class ScreenshotParser {
  ScreenshotParser({
    TimeSpanExtractor? spanExtractor,
    DateNormalizer? normalizer,
    RoleClassifier? roleClassifier,
    CategoryClassifier? categoryClassifier,
    FieldExtractor? fieldExtractor,
  })  : _spans = spanExtractor ?? TimeSpanExtractor(),
        _normalizer = normalizer ?? const DateNormalizer(),
        _roles = roleClassifier ?? const RoleClassifier(),
        _categories = categoryClassifier ?? const CategoryClassifier(),
        _fields = fieldExtractor ?? const FieldExtractor();

  final TimeSpanExtractor _spans;
  final DateNormalizer _normalizer;
  final RoleClassifier _roles;
  final CategoryClassifier _categories;
  final FieldExtractor _fields;

  /// [anchor] 必须是截图导入/拍摄时间，不得使用“稍后打开详情页”的时间。
  ParsedDraft parse({
    required List<OcrBlock> blocks,
    required DateTime anchor,
  }) {
    // 1. 清洗与阅读顺序恢复：按 lineIndex/top 排序后拼接。
    final ordered = List.of(blocks)
      ..sort((a, b) {
        final byLine = a.lineIndex.compareTo(b.lineIndex);
        return byLine != 0 ? byLine : a.left.compareTo(b.left);
      });
    final lines = <String>[];
    final lineBlockIds = <List<String>>[];
    final blockRanges = <(int, int, String)>[]; // start,end,blockId in fullText
    final buf = StringBuffer();
    for (final b in ordered) {
      final text = _clean(b.text);
      if (text.isEmpty) continue;
      final start = buf.length;
      buf.write(text);
      blockRanges.add((start, buf.length, b.id));
      buf.write('\n');
      lines.add(text);
      lineBlockIds.add([b.id]);
    }
    final fullText = buf.toString();

    // 2. span 提取。
    var spans = _spans.extract(fullText);
    // 独立时刻在存在带日期表达时视为噪音（多为区间/重复），丢弃。
    final hasDated = spans.any((s) => s.kind != SpanKind.timeOnly);
    if (hasDated) {
      spans = spans.where((s) => s.kind != SpanKind.timeOnly).toList();
    }

    // 3~5. 归一化 + 上下文 + 角色分类。
    final warnings = <String>[];
    final candidates = <TemporalCandidate>[];
    for (final span in spans) {
      final norm = _normalizer.normalize(span, anchor);
      if (norm == null) continue;
      final roleScores = _roles.classify(fullText, span.start, span.end);

      var role = roleScores.role;
      var roleConf = roleScores.confidence;
      // 无关键词的区间/纯时间表达默认按活动开始理解。
      if (role == TemporalRole.unknown &&
          (span.kind == SpanKind.timeRange || span.endHour != null)) {
        role = TemporalRole.eventStart;
        roleConf = 0.4;
      }

      final ctxBefore = fullText.substring(
        (span.start - 14).clamp(0, fullText.length), span.start,
      );
      final ctxAfter = fullText.substring(
        span.end, (span.end + 14).clamp(0, fullText.length),
      );
      final evidence = [
        for (final (s, e, id) in blockRanges)
          if (span.start < e && s < span.end) id,
      ];

      candidates.add(
        TemporalCandidate(
          id: IdGen.newId(),
          rawText: span.text,
          normalizedDateTime: norm.dateTime,
          endDateTime: norm.endDateTime,
          startOffset: span.start,
          endOffset: span.end,
          role: role,
          roleConfidence: roleConf,
          dateConfidence: norm.confidence,
          contextBefore: ctxBefore,
          contextAfter: ctxAfter,
          evidenceBlockIds: evidence,
          requiresConfirmation:
              norm.requiresConfirmation || roleConf < 0.45,
          explanation: norm.explanation,
          alternativeRoles: roleScores.alternatives,
        ),
      );
    }

    // 6. 聚合：同一角色同一归一化时间去重（OCR 重复识别）。
    final deduped = <TemporalCandidate>[];
    for (final c in candidates) {
      final dup = deduped.any(
        (d) =>
            d.normalizedDateTime == c.normalizedDateTime &&
            d.role == c.role &&
            d.endDateTime == c.endDateTime,
      );
      if (!dup) deduped.add(c);
    }

    // 截止/失效类日期若无明确时刻，调整为当日 23:59 并解释。
    final adjusted = deduped.map((c) {
      final dt = c.normalizedDateTime;
      if (dt == null) return c;
      final isEndOfDayRole =
          c.role == TemporalRole.deadline || c.role == TemporalRole.expiry;
      if (isEndOfDayRole && dt.hour == 0 && dt.minute == 0 && !_hasExplicitMidnight(c.rawText)) {
        return c.copyWith(
          normalizedDateTime: DateTime(dt.year, dt.month, dt.day, 23, 59),
          explanation: '${c.explanation.isEmpty ? '' : '${c.explanation}；'}未写明时刻，按当日 23:59 理解',
        );
      }
      return c;
    }).toList()
      ..sort((a, b) {
        final ad = a.normalizedDateTime, bd = b.normalizedDateTime;
        if (ad == null || bd == null) return 0;
        return ad.compareTo(bd);
      });

    // 7. 字段提取。
    final title = _fields.extractTitle(lines);
    final location = _fields.extractLocation(fullText);
    final secret = _fields.extractSecretCode(fullText);
    final highRisk = _fields.containsHighRiskInfo(fullText);

    // 8. 卡片分类。
    final cat = _categories.classify(title, fullText);
    var category = cat.category;
    // 只有截止时间且无其他强信号时归为 deadline。
    if (category == CardCategory.generic &&
        adjusted.isNotEmpty &&
        adjusted.every((c) => c.role == TemporalRole.deadline)) {
      category = CardCategory.deadline;
    }

    if (adjusted.isEmpty) {
      warnings.add('未识别到时间，可手动设定保鲜期');
    }
    if (highRisk) {
      warnings.add('检测到疑似证件号/银行卡号，不建议保存此类信息');
    }

    // 9. 总置信度：各环节启发式分数加权组合。
    final dateConf = adjusted.isEmpty
        ? 0.0
        : adjusted.map((c) => c.dateConfidence).reduce((a, b) => a + b) /
            adjusted.length;
    final roleConf = adjusted.isEmpty
        ? 0.0
        : adjusted.map((c) => c.roleConfidence).reduce((a, b) => a + b) /
            adjusted.length;
    final confidence =
        (dateConf * 0.4 + roleConf * 0.3 + cat.confidence * 0.2 + 0.1)
            .clamp(0.0, 1.0);

    return ParsedDraft(
      title: title,
      category: category,
      categoryExplanation: cat.explanation,
      location: location,
      secretValue: secret,
      isSensitive: secret != null || category == CardCategory.temporarySecret,
      highRisk: highRisk,
      candidates: adjusted,
      confidenceScore: confidence,
      warnings: warnings,
      cleanedText: fullText,
    );
  }

  /// 便捷入口：无坐标的纯文本（手动输入降级）。
  ParsedDraft parseText(String text, DateTime anchor) {
    final lines = text.split('\n');
    var i = 0;
    final blocks = [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          OcrBlock(
            id: 'manual-${i++}',
            text: line.trim(),
            left: 0, top: i / lines.length, right: 1, bottom: (i + 1) / lines.length,
            confidence: 1.0,
            lineIndex: i,
          ),
    ];
    return parse(blocks: blocks, anchor: anchor);
  }

  static String _clean(String s) => s
      .replaceAll(RegExp(r'[\u{FEFF}\u{200B}]', unicode: true), '')
      .replaceAll('：', '：') // 全角冒号保留
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _hasExplicitMidnight(String raw) =>
      raw.contains('0点') || raw.contains('00:00') || raw.contains('0时');
}
