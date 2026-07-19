import '../enums/enums.dart';
import 'field_extractor.dart';

/// 生活场景决策树：对全部场景分支打分取最高，命中不足时回退到
/// 截止事项/便签/临时信息等通用分支。
///
/// 分支顺序即同分时的优先级，用于解决常见冲突：例如“医院预约”优先
/// 归入就医而不是普通活动；“水费缴费截止”优先归入账单而不是泛化截止。
class CategoryClassifier {
  const CategoryClassifier();

  static const _branches = <_DecisionBranch>[
    _DecisionBranch('快递取件', CardCategory.pickup, {
      '取件码': 3.0,
      '取餐码': 3.0,
      '取货码': 3.0,
      '自提码': 3.0,
      '取件': 2.5,
      '取餐': 2.5,
      '柜号': 2.0,
      '提货': 2.0,
      '快递': 1.5,
      '驿站': 2.0,
      '外卖': 1.5,
      '丰巢': 2.5,
      '菜鸟': 2.0,
      '运单号': 2.5,
      '快递单号': 2.5,
      '物流': 1.5,
      '面单': 2.0,
      '包裹': 1.5,
      '自提': 2.0,
      '顺丰': 1.5,
      '圆通': 1.2,
      '中通': 1.2,
      '申通': 1.2,
      '韵达': 1.2,
      '极兔': 1.2,
      '京东物流': 1.5,
    }),
    _DecisionBranch('出行住宿', CardCategory.ticket, {
      '车次': 3.0,
      '航班': 3.0,
      '检票': 3.0,
      '座位': 2.0,
      '影厅': 2.5,
      '电影票': 2.5,
      '登机': 3.0,
      '值机': 2.5,
      '高铁': 2.0,
      '火车': 2.0,
      '演出': 1.5,
      '门票': 2.0,
      '发车': 2.5,
      '起飞': 2.5,
      '候车': 1.5,
      '入住': 2.0,
      '退房': 2.0,
      '酒店': 1.5,
      '民宿': 1.5,
    }),
    _DecisionBranch('就医用药', CardCategory.healthcare, {
      '医院': 2.5,
      '就诊': 3.0,
      '复诊': 3.0,
      '挂号': 3.0,
      '门诊': 2.5,
      '体检': 2.5,
      '疫苗': 2.5,
      '服药': 3.0,
      '用药': 2.5,
      '药品': 2.0,
      '处方': 2.0,
    }),
    _DecisionBranch('学习考试', CardCategory.study, {
      '考试': 2.0,
      '开考': 2.5,
      '课程': 2.5,
      '上课': 2.5,
      '作业': 2.0,
      '答辩': 2.5,
      '成绩': 1.5,
      '选课': 2.0,
      '考场': 2.0,
      '教室': 1.5,
    }),
    _DecisionBranch('账单缴费', CardCategory.bill, {
      '账单': 2.5,
      '缴费': 3.0,
      '还款': 3.0,
      '水费': 2.5,
      '电费': 2.5,
      '燃气费': 2.5,
      '物业费': 2.5,
      '信用卡': 2.5,
      '房租': 2.5,
      '话费': 2.0,
    }),
    _DecisionBranch('续费续期', CardCategory.renewal, {
      '续费': 3.0,
      '续期': 3.0,
      '会员到期': 3.0,
      '订阅到期': 3.0,
      '证件到期': 3.0,
      '保险到期': 3.0,
      '保修到期': 3.0,
      '年检': 2.5,
      '有效期': 1.5,
    }),
    _DecisionBranch('优惠兑换', CardCategory.coupon, {
      '优惠券': 3.0,
      '兑换券': 3.0,
      '代金券': 3.0,
      '核销码': 2.5,
      '兑换码': 2.5,
      '优惠码': 2.5,
      '券到期': 2.5,
      '使用期限': 2.0,
    }),
    _DecisionBranch('活动安排', CardCategory.event, {
      '活动': 2.0,
      '会议': 2.0,
      '讲座': 2.0,
      '面试': 2.0,
      '预约': 1.5,
      '报名': 1.5,
      '体验日': 2.0,
      '开幕': 1.5,
      '培训': 1.5,
      '展览': 1.5,
      '聚会': 2.0,
      '直播': 1.5,
      '开播': 2.0,
      '停水': 2.5,
      '停电': 2.5,
      '停气': 2.5,
      '停暖': 2.5,
      '维修通知': 2.0,
      '开抢': 2.0,
      '秒杀': 2.0,
    }),
    _DecisionBranch('待办截止', CardCategory.deadline, {
      '报名截止': 2.0,
      '提交': 2.0,
      '申报': 2.0,
      '缴费截止': 2.5,
      '截止日期': 2.0,
      'deadline': 2.0,
      '逾期': 1.5,
      '最后期限': 2.5,
      '尾款': 2.5,
      '退货截止': 3.0,
      '退款截止': 3.0,
    }),
    _DecisionBranch('临时凭证', CardCategory.temporarySecret, {
      '验证码': 3.0,
      '门禁码': 3.0,
      'Wi-Fi': 2.5,
      'WiFi': 2.5,
      'wifi': 2.5,
      '临时密码': 3.0,
      '密码': 1.5,
      '口令': 2.0,
      '邀请码': 2.0,
    }),
    _DecisionBranch('随手记', CardCategory.note, {
      '便签': 2.5,
      '备忘': 2.5,
      '待办': 2.0,
      '清单': 2.0,
      '记一下': 2.5,
      '别忘': 2.0,
      '记得': 1.5,
      '提醒自己': 2.5,
    }),
  ];

  /// 临时码标签 → 分类提示；只在文字信号不足时兜底。
  static const _secretLabelHints = <String, CardCategory>{
    '取件码': CardCategory.pickup,
    '取餐码': CardCategory.pickup,
    '取货码': CardCategory.pickup,
    '自提码': CardCategory.pickup,
    '提货码': CardCategory.pickup,
    '运单号': CardCategory.pickup,
    '兑换码': CardCategory.coupon,
    '核销码': CardCategory.coupon,
    '门禁码': CardCategory.temporarySecret,
    '验证码': CardCategory.temporarySecret,
    '临时密码': CardCategory.temporarySecret,
  };

  CategoryScores classify(
    String title,
    String fullText, {
    LabeledSecret? secret,
  }) {
    _DecisionBranch? best;
    var bestScore = 0.0;
    var bestHits = const <String>[];
    for (final branch in _branches) {
      var score = 0.0;
      final hit = <String>[];
      branch.signals.forEach((word, weight) {
        if (title.contains(word)) {
          score += weight * 1.5;
          hit.add(word);
        } else if (fullText.contains(word)) {
          score += weight;
          hit.add(word);
        }
      });
      // 分支顺序即同分优先级：严格大于才替换。
      if (score >= 1.5 && score > bestScore) {
        best = branch;
        bestScore = score;
        bestHits = hit;
      }
    }
    if (best != null) {
      return CategoryScores(
        best.category,
        (bestScore / (bestScore + 1.5)).clamp(0.0, 1.0),
        '图里出现了「${bestHits.take(3).join('、')}」，按${best.label}整理',
      );
    }
    // 文字信号不足，但识别到带标签的码 → 用标签兜底。
    final hinted = secret == null ? null : _secretLabelHints[secret.label];
    if (hinted != null) {
      return CategoryScores(hinted, 0.6, '根据「${secret!.label}」判断的类型');
    }
    return const CategoryScores(
      CardCategory.generic,
      0.3,
      '没有找到明显的场景特征，先按临时信息保存',
    );
  }
}

class _DecisionBranch {
  const _DecisionBranch(this.label, this.category, this.signals);

  final String label;
  final CardCategory category;
  final Map<String, double> signals;
}

class CategoryScores {
  const CategoryScores(this.category, this.confidence, this.explanation);
  final CardCategory category;
  final double confidence;
  final String explanation;
}
