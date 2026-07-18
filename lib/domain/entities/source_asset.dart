import '../enums/enums.dart';

/// 导入到应用沙箱的图片资产。
class SourceAsset {
  const SourceAsset({
    required this.id,
    required this.sandboxPath,
    required this.mimeType,
    required this.sha256,
    required this.importSource,
    required this.importedAt,
    this.originalDisplayName,
    this.thumbnailPath,
    this.width = 0,
    this.height = 0,
    this.sizeBytes = 0,
  });

  final String id;
  final String? originalDisplayName;
  final String sandboxPath;
  final String? thumbnailPath;
  final String mimeType;
  final int width;
  final int height;
  final int sizeBytes;
  final String sha256;
  final ImportSource importSource;
  final DateTime importedAt;
}

/// OCR 识别出的文本块，坐标归一化到 0~1。
class OcrBlock {
  const OcrBlock({
    required this.id,
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
    required this.lineIndex,
    this.cardId,
    this.readingOrder = 0,
  });

  final String id;
  final String? cardId;
  final String text;
  final double left, top, right, bottom;
  final double confidence;
  final int lineIndex;
  final int readingOrder;
}

/// 从文本中提取出的时间候选。
class TemporalCandidate {
  const TemporalCandidate({
    required this.id,
    required this.rawText,
    required this.role,
    required this.roleConfidence,
    required this.dateConfidence,
    this.normalizedDateTime,
    this.endDateTime,
    this.startOffset = 0,
    this.endOffset = 0,
    this.contextBefore = '',
    this.contextAfter = '',
    this.evidenceBlockIds = const [],
    this.requiresConfirmation = false,
    this.explanation = '',
    this.alternativeRoles = const {},
  });

  final String id;
  final String rawText;
  final DateTime? normalizedDateTime;

  /// 区间表达（如 14:00-16:30、7月20日至25日）的结束时间。
  final DateTime? endDateTime;
  final int startOffset;
  final int endOffset;
  final TemporalRole role;
  final double roleConfidence;
  final double dateConfidence;
  final String contextBefore;
  final String contextAfter;
  final List<String> evidenceBlockIds;
  final bool requiresConfirmation;

  /// 可解释原因，例如“截图未包含年份，按最近未来推断为 2027 年”。
  final String explanation;

  /// 冲突时保留的其他候选角色及分数。
  final Map<TemporalRole, double> alternativeRoles;

  TemporalCandidate copyWith({
    TemporalRole? role,
    double? roleConfidence,
    DateTime? normalizedDateTime,
    bool? requiresConfirmation,
    String? explanation,
    Map<TemporalRole, double>? alternativeRoles,
  }) =>
      TemporalCandidate(
        id: id,
        rawText: rawText,
        normalizedDateTime: normalizedDateTime ?? this.normalizedDateTime,
        endDateTime: endDateTime,
        startOffset: startOffset,
        endOffset: endOffset,
        role: role ?? this.role,
        roleConfidence: roleConfidence ?? this.roleConfidence,
        dateConfidence: dateConfidence,
        contextBefore: contextBefore,
        contextAfter: contextAfter,
        evidenceBlockIds: evidenceBlockIds,
        requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
        explanation: explanation ?? this.explanation,
        alternativeRoles: alternativeRoles ?? this.alternativeRoles,
      );
}
