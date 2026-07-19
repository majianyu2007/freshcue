import '../enums/enums.dart';

/// 时间角色分类器：基于关键词距离衰减评分，可解释。
/// 正则只负责 span 定位（TimeSpanExtractor），语义在这里独立完成。
class RoleClassifier {
  const RoleClassifier({this.windowSize = 14});

  /// 候选前后上下文窗口长度（字符）。
  final int windowSize;

  static const _keywords = <TemporalRole, Map<String, double>>{
    TemporalRole.deadline: {
      '报名截止': 3.0,
      '提交截止': 3.0,
      '缴费截止': 3.0,
      '申报截止': 3.0,
      '截止': 2.5,
      '截至': 2.5,
      '最后期限': 2.5,
      '逾期': 1.5,
      '之前提交': 2.0,
      '报名': 1.2,
      '提交': 1.2,
      '申报': 1.2,
    },
    TemporalRole.eventStart: {
      '活动时间': 3.0,
      '会议时间': 3.0,
      '考试时间': 3.0,
      '开考': 2.5,
      '开始': 2.0,
      '开场': 2.0,
      '举行': 2.0,
      '召开': 2.0,
      '开会': 2.5,
      '讲座': 1.5,
      '面试': 2.0,
      '预约': 1.5,
      '上课': 1.5,
      '活动': 1.2,
      '会议': 1.2,
    },
    TemporalRole.eventEnd: {'结束': 2.5, '闭馆': 2.5, '散场': 2.5, '截止入场': 2.0},
    TemporalRole.departure: {
      '发车': 3.0,
      '起飞': 3.0,
      '出发': 2.5,
      '检票': 2.5,
      '登机': 2.5,
      '开车时间': 3.0,
      '航班': 1.5,
      '车次': 1.5,
    },
    TemporalRole.expiry: {
      '有效期至': 3.5,
      '免费保管至': 3.5,
      '有效期': 3.0,
      '保管截止': 3.0,
      '保管至': 3.0,
      '失效': 3.0,
      '过期': 3.0,
      '兑换截止': 3.0,
      '领取截止': 3.0,
      '到期': 2.5,
      '免费保管': 2.0,
      '有效': 1.0,
    },
    TemporalRole.publishTime: {
      '发布于': 3.5,
      '发布时间': 3.5,
      '发布': 2.5,
      '通知时间': 2.5,
      '更新时间': 3.0,
      '更新于': 3.0,
      '发表': 2.0,
      '发出': 1.5,
    },
  };

  /// 对 [fullText] 中 [spanStart..spanEnd] 的时间候选评分。
  /// 返回全部角色得分（降序）；调用方保留 top 与 alternatives。
  RoleScores classify(String fullText, int spanStart, int spanEnd) {
    final beforeStart = (spanStart - windowSize).clamp(0, fullText.length);
    final before = fullText.substring(beforeStart, spanStart);
    final after = fullText.substring(
      spanEnd,
      (spanEnd + windowSize).clamp(0, fullText.length),
    );

    final scores = <TemporalRole, double>{};
    _keywords.forEach((role, words) {
      // 每侧只取最强命中，避免“发布/发布于”这类嵌套关键词重复计分。
      var beforeBest = 0.0;
      var afterBest = 0.0;
      words.forEach((word, weight) {
        // 前文：关键词结束位置距 span 越近权重越高。
        var idx = before.lastIndexOf(word);
        if (idx >= 0) {
          final dist = before.length - (idx + word.length);
          final s = weight * _decay(dist);
          if (s > beforeBest) beforeBest = s;
        }
        // 后文：权重略降（如“7月25日开始”）。
        idx = after.indexOf(word);
        if (idx >= 0) {
          final s = weight * _decay(idx) * 0.8;
          if (s > afterBest) afterBest = s;
        }
      });
      final score = beforeBest + afterBest;
      if (score > 0) scores[role] = score;
    });

    if (scores.isEmpty) {
      return const RoleScores(TemporalRole.unknown, 0.0, {});
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    // 归一化到 0~1 的启发式置信度：与次高分差距越大越自信。
    final second = sorted.length > 1 ? sorted[1].value : 0.0;
    final confidence =
        ((top.value / (top.value + second)) * (top.value / (top.value + 1.5)))
            .clamp(0.0, 1.0);
    final alternatives = <TemporalRole, double>{
      for (final e in sorted.skip(1)) e.key: e.value,
    };
    return RoleScores(top.key, confidence, alternatives);
  }

  static double _decay(int distance) => 1.0 / (1.0 + distance * 0.35);
}

class RoleScores {
  const RoleScores(this.role, this.confidence, this.alternatives);
  final TemporalRole role;
  final double confidence;
  final Map<TemporalRole, double> alternatives;
}
