import '../enums/enums.dart';

/// 生活场景决策树：先识别专用场景，再回退到通用事件/截止/临时信息。
///
/// 分支顺序用于解决常见冲突，例如“医院预约”优先归入就医，而不是普通活动；
/// “水费缴费截止”优先归入账单，而不是泛化截止事项。
class CategoryClassifier {
  const CategoryClassifier();

  static const _branches = <_DecisionBranch>[
    _DecisionBranch('生活服务', CardCategory.pickup, {
      '取件码': 3.0,
      '取餐码': 3.0,
      '取件': 2.5,
      '取餐': 2.5,
      '柜号': 2.0,
      '提货': 2.0,
      '快递': 1.5,
      '驿站': 2.0,
      '外卖': 1.5,
      '丰巢': 2.5,
      '菜鸟': 2.0,
    }),
    _DecisionBranch('出行票务', CardCategory.ticket, {
      '车次': 3.0,
      '航班': 3.0,
      '检票': 3.0,
      '座位': 2.0,
      '影厅': 2.5,
      '电影票': 2.5,
      '登机': 3.0,
      '高铁': 2.0,
      '火车': 2.0,
      '演出': 1.5,
      '门票': 2.0,
      '发车': 2.5,
      '起飞': 2.5,
    }),
    _DecisionBranch('健康医疗', CardCategory.healthcare, {
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
    _DecisionBranch('活动日程', CardCategory.event, {
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
    }),
    _DecisionBranch('任务截止', CardCategory.deadline, {
      '报名截止': 2.0,
      '提交': 2.0,
      '申报': 2.0,
      '缴费截止': 2.5,
      '截止日期': 2.0,
      'deadline': 2.0,
      '逾期': 1.5,
      '最后期限': 2.5,
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
  ];

  CategoryScores classify(String title, String fullText) {
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
      if (score >= 1.5) {
        return CategoryScores(
          branch.category,
          (score / (score + 1.5)).clamp(0.0, 1.0),
          '决策路径：${branch.label}；命中：${hit.join('、')}',
        );
      }
    }
    return const CategoryScores(
      CardCategory.generic,
      0.3,
      '决策路径：未命中专用场景，归为临时信息',
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
