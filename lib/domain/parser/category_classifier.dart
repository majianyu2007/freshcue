import '../enums/enums.dart';

/// 卡片类型分类器：标题与全文关键词计分，输出解释。
class CategoryClassifier {
  const CategoryClassifier();

  static const _keywords = <CardCategory, Map<String, double>>{
    CardCategory.pickup: {
      '取件码': 3.0, '取餐码': 3.0, '取件': 2.5, '取餐': 2.5, '柜号': 2.0,
      '提货': 2.0, '核销码': 2.5, '快递': 1.5, '驿站': 2.0, '外卖': 1.5,
    },
    CardCategory.event: {
      '活动': 2.0, '会议': 2.0, '考试': 2.0, '讲座': 2.0, '面试': 2.0,
      '预约': 1.5, '报名': 1.5, '体验日': 2.0, '开幕': 1.5, '培训': 1.5,
    },
    CardCategory.ticket: {
      '车次': 3.0, '航班': 3.0, '检票': 3.0, '座位': 2.0, '影厅': 2.5,
      '开场': 1.5, '登机': 3.0, '高铁': 2.0, '演出': 1.5, '票': 1.0,
    },
    CardCategory.deadline: {
      '报名截止': 2.0, '提交': 2.0, '申报': 2.0, '缴费截止': 2.5,
      '截止日期': 2.0, 'deadline': 2.0, '逾期': 1.5,
    },
    CardCategory.temporarySecret: {
      '验证码': 3.0, '门禁码': 3.0, 'Wi-Fi': 2.5, 'WiFi': 2.5, 'wifi': 2.5,
      '临时密码': 3.0, '密码': 1.5, '口令': 2.0, '邀请码': 2.0,
    },
  };

  CategoryScores classify(String title, String fullText) {
    final scores = <CardCategory, double>{};
    final reasons = <CardCategory, List<String>>{};
    _keywords.forEach((cat, words) {
      var score = 0.0;
      final hit = <String>[];
      words.forEach((word, weight) {
        if (title.contains(word)) {
          score += weight * 1.5; // 标题命中权重更高
          hit.add(word);
        } else if (fullText.contains(word)) {
          score += weight;
          hit.add(word);
        }
      });
      if (score > 0) {
        scores[cat] = score;
        reasons[cat] = hit;
      }
    });

    if (scores.isEmpty) {
      return const CategoryScores(CardCategory.generic, 0.3, '未命中分类关键词，归为通用临时信息');
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    if (top.value < 1.5) {
      return CategoryScores(
        CardCategory.generic,
        0.4,
        '分类信号较弱（${reasons[top.key]!.join('、')}），归为通用临时信息',
      );
    }
    final second = sorted.length > 1 ? sorted[1].value : 0.0;
    final confidence =
        (top.value / (top.value + second + 1.0)).clamp(0.0, 1.0);
    return CategoryScores(
      top.key,
      confidence,
      '命中关键词：${reasons[top.key]!.join('、')}',
    );
  }
}

class CategoryScores {
  const CategoryScores(this.category, this.confidence, this.explanation);
  final CardCategory category;
  final double confidence;
  final String explanation;
}
