import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/domain/entities/source_asset.dart';
import 'package:freshcue/domain/enums/enums.dart';
import 'package:freshcue/domain/parser/date_normalizer.dart';
import 'package:freshcue/domain/parser/screenshot_parser.dart';
import 'package:freshcue/domain/parser/time_span_extractor.dart';

/// 时间解析引擎测试。锚点统一为 2026-07-18 10:00（周六）。
void main() {
  final anchor = DateTime(2026, 7, 18, 10, 0);
  final extractor = TimeSpanExtractor();
  const normalizer = DateNormalizer();
  final parser = ScreenshotParser();

  DateTime? norm(String text) {
    final spans = extractor.extract(text);
    if (spans.isEmpty) return null;
    return normalizer.normalize(spans.first, anchor)?.dateTime;
  }

  NormalizedTime? normFull(String text) {
    final spans = extractor.extract(text);
    if (spans.isEmpty) return null;
    return normalizer.normalize(spans.first, anchor);
  }

  group('span 提取与归一化：绝对日期', () {
    test('2026年7月25日 14:00', () {
      expect(norm('2026年7月25日 14:00'), DateTime(2026, 7, 25, 14, 0));
    });
    test('2026-07-25 14:00', () {
      expect(norm('2026-07-25 14:00'), DateTime(2026, 7, 25, 14, 0));
    });
    test('2026/07/25 14:00', () {
      expect(norm('2026/07/25 14:00'), DateTime(2026, 7, 25, 14, 0));
    });
    test('2026.07.25 无时刻', () {
      expect(norm('2026.07.25'), DateTime(2026, 7, 25));
    });
    test('2026年7月25日（无时刻）', () {
      expect(norm('2026年7月25日'), DateTime(2026, 7, 25));
    });
    test('2026年7月25日下午2点', () {
      expect(norm('2026年7月25日下午2点'), DateTime(2026, 7, 25, 14, 0));
    });
    test('2026年12月1日晚上8点30分', () {
      expect(norm('2026年12月1日晚上8点30分'), DateTime(2026, 12, 1, 20, 30));
    });
    test('带星期：2026年7月25日（周六）14:00', () {
      expect(norm('2026年7月25日（周六）14:00'), DateTime(2026, 7, 25, 14, 0));
    });
    test('非法日期 2026年13月40日 不产生候选', () {
      expect(norm('编号2026年13月40日'), isNull);
    });
    test('历史绝对日期标记 requiresConfirmation', () {
      final r = normFull('2025年1月1日 10:00')!;
      expect(r.requiresConfirmation, isTrue);
    });
  });

  group('月日 + 年份推断', () {
    test('7月25日下午2点 → 今年未来', () {
      expect(norm('7月25日下午2点'), DateTime(2026, 7, 25, 14, 0));
    });
    test('7/25 14:00', () {
      expect(norm('7/25 14:00'), DateTime(2026, 7, 25, 14, 0));
    });
    test('7月20日18时', () {
      expect(norm('截止到7月20日18时'), DateTime(2026, 7, 20, 18, 0));
    });
    test('未来跨年：1月2日（锚点7月）→ 2027 年且需确认', () {
      final r = normFull('1月2日开始')!;
      expect(r.dateTime, DateTime(2027, 1, 2));
      expect(r.requiresConfirmation, isTrue);
      expect(r.explanation, contains('2027'));
    });
    test('12月31日导入，1月2日开始（跨年场景）', () {
      final dec31 = DateTime(2026, 12, 31, 20, 0);
      final spans = extractor.extract('1月2日开始');
      final r = normalizer.normalize(spans.first, dec31)!;
      expect(r.dateTime.year, 2027);
      expect(r.dateTime.month, 1);
      expect(r.dateTime.day, 2);
    });
    test('刚过去的日期（≤60天）保留当年并要求确认，不自动滚下一年', () {
      final r = normFull('7月10日 14:00')!;
      expect(r.dateTime, DateTime(2026, 7, 10, 14, 0));
      expect(r.requiresConfirmation, isTrue);
      expect(r.explanation, contains('历史'));
    });
    test('闰年：2028年2月29日合法', () {
      expect(norm('2028年2月29日'), DateTime(2028, 2, 29));
    });
    test('2月29日无年份 → 最近合法闰年 2028', () {
      final r = normFull('2月29日')!;
      expect(r.dateTime.year, 2028);
      expect(r.dateTime.month, 2);
      expect(r.dateTime.day, 29);
    });
    test('无年份推断解释可读', () {
      final r = normFull('7月25日 14:00')!;
      expect(r.explanation, contains('2026'));
    });
  });

  group('相对日期（锚定导入时间）', () {
    test('今晚8点 → 当天 20:00', () {
      expect(norm('今晚8点'), DateTime(2026, 7, 18, 20, 0));
    });
    test('明天下午3点', () {
      expect(norm('明天下午3点'), DateTime(2026, 7, 19, 15, 0));
    });
    test('后天上午9:30', () {
      expect(norm('后天上午9:30'), DateTime(2026, 7, 20, 9, 30));
    });
    test('今天中午12点', () {
      expect(norm('今天中午12点'), DateTime(2026, 7, 18, 12, 0));
    });
    test('明晚9点', () {
      expect(norm('明晚9点'), DateTime(2026, 7, 19, 21, 0));
    });
    test('明天（无时刻）→ 默认上午9点且需确认', () {
      final r = normFull('明天交材料')!;
      expect(r.dateTime, DateTime(2026, 7, 19, 9, 0));
      expect(r.requiresConfirmation, isTrue);
    });
    test('相对日期解释包含锚点', () {
      final r = normFull('明天下午3点')!;
      expect(r.explanation, contains('7月18日'));
    });
  });

  group('星期表达', () {
    // 2026-07-18 是周六。
    test('本周五18:00 → 已过去，保留并要求确认', () {
      final r = normFull('本周五 18:00 截止')!;
      expect(r.dateTime, DateTime(2026, 7, 17, 18, 0));
      expect(r.requiresConfirmation, isTrue);
    });
    test('下周一下午 → 7月20日 14:00 默认时刻', () {
      final r = normFull('下周一下午')!;
      expect(r.dateTime, DateTime(2026, 7, 20, 14, 0));
      expect(r.requiresConfirmation, isTrue);
    });
    test('下周三 09:00', () {
      expect(norm('下周三 9点'), DateTime(2026, 7, 22, 9, 0));
    });
    test('周日晚上8点（本周）', () {
      expect(norm('周日晚上8点'), DateTime(2026, 7, 19, 20, 0));
    });
  });

  group('区间表达', () {
    test('14:00-16:30 → 起止时刻', () {
      final r = normFull('14:00-16:30')!;
      expect(r.dateTime.hour, 14);
      expect(r.endDateTime!.hour, 16);
      expect(r.endDateTime!.minute, 30);
    });
    test('7月20日至7月25日', () {
      final r = normFull('7月20日至7月25日')!;
      expect(r.dateTime, DateTime(2026, 7, 20));
      expect(r.endDateTime, DateTime(2026, 7, 25, 23, 59));
    });
    test('7月20日-25日（省略月份）', () {
      final r = normFull('7月20日-25日')!;
      expect(r.endDateTime!.day, 25);
      expect(r.endDateTime!.month, 7);
    });
    test('日期+时间段：7月25日 14:00—16:30', () {
      final draft = parser.parseText('活动时间：7月25日 14:00—16:30', anchor);
      final starts = draft.candidates
          .where((c) => c.normalizedDateTime!.day == 25)
          .toList();
      expect(starts, isNotEmpty);
    });
  });

  group('时间角色分类', () {
    ParsedDraft p(String text) => parser.parseText(text, anchor);

    test('报名截止 → deadline', () {
      final d = p('报名截止：7月20日 18:00');
      expect(d.candidates.single.role, TemporalRole.deadline);
    });
    test('活动时间 → eventStart', () {
      final d = p('活动时间：7月25日 14:00');
      expect(d.candidates.single.role, TemporalRole.eventStart);
    });
    test('一图两时间：报名截止7月20日，活动时间7月25日14:00', () {
      final d = p('报名截止7月20日，活动时间7月25日14:00');
      expect(d.candidates.length, 2);
      expect(d.candidates[0].role, TemporalRole.deadline);
      expect(d.candidates[1].role, TemporalRole.eventStart);
      expect(d.suggestedAnchors[TemporalRole.deadline], isNotNull);
      expect(
        d.suggestedAnchors[TemporalRole.eventStart],
        DateTime(2026, 7, 25, 14, 0),
      );
    });
    test('发布时间被识别且不进入锚点：发布于7月1日，7月8日开会', () {
      final d = p('发布于7月1日，7月8日开会');
      final publish = d.candidates.firstWhere(
        (c) => c.role == TemporalRole.publishTime,
      );
      expect(publish.rawText, contains('7月1日'));
      final meeting = d.candidates.firstWhere(
        (c) => c.role == TemporalRole.eventStart,
      );
      expect(meeting.normalizedDateTime!.day, 8);
      expect(d.suggestedAnchors.containsKey(TemporalRole.publishTime), isFalse);
      expect(d.suggestedAnchors[TemporalRole.eventStart]!.day, 8);
    });
    test('有效期至 → expiry', () {
      final d = p('有效期至7月31日');
      expect(d.candidates.single.role, TemporalRole.expiry);
    });
    test('快递免费保管至 → expiry 并生成失效锚点', () {
      final d = p('取件码 6-2-8519\n免费保管至 7月21日 18:00\n超时收取保管费');
      expect(d.candidates.single.role, TemporalRole.expiry);
      expect(
        d.suggestedAnchors[TemporalRole.expiry],
        DateTime(2026, 7, 21, 18, 0),
      );
    });
    test('截止到7月20日18时 → deadline', () {
      final d = p('截止到7月20日18时');
      expect(d.candidates.single.role, TemporalRole.deadline);
      expect(
        d.candidates.single.normalizedDateTime,
        DateTime(2026, 7, 20, 18, 0),
      );
    });
    test('发车 → departure', () {
      final d = p('G102次 7月20日 08:15发车');
      expect(d.candidates.single.role, TemporalRole.departure);
    });
    test('结束 → eventEnd', () {
      final d = p('展览7月30日 17:00结束');
      expect(d.candidates.single.role, TemporalRole.eventEnd);
    });
    test('无关键词 → unknown 且需确认', () {
      final d = p('7月26日 10:00');
      expect(d.candidates.single.role, TemporalRole.unknown);
      expect(d.candidates.single.requiresConfirmation, isTrue);
    });
    test('deadline 无时刻 → 归一化为 23:59', () {
      final d = p('提交截止：7月22日');
      expect(
        d.candidates.single.normalizedDateTime,
        DateTime(2026, 7, 22, 23, 59),
      );
    });
  });

  group('聚合与去重', () {
    test('同一时间被 OCR 重复两次只保留一个候选', () {
      final d = parser.parseText('报名截止7月20日 18:00\n报名截止7月20日 18:00', anchor);
      expect(d.candidates.length, 1);
    });
    test('候选按时间升序排列', () {
      final d = parser.parseText('活动时间7月25日14:00\n报名截止7月20日18:00', anchor);
      expect(d.candidates.first.role, TemporalRole.deadline);
    });
  });

  test('同一张长截图按留白拆成多条时效信息', () {
    final blocks = [
      const OcrBlock(
        id: 'a1',
        text: '音乐节门票',
        left: 0.08,
        top: 0.08,
        right: 0.7,
        bottom: 0.12,
        lineIndex: 0,
      ),
      const OcrBlock(
        id: 'a2',
        text: '7月25日 19:30入场',
        left: 0.08,
        top: 0.14,
        right: 0.8,
        bottom: 0.18,
        lineIndex: 1,
      ),
      const OcrBlock(
        id: 'b1',
        text: '快递取件通知',
        left: 0.08,
        top: 0.48,
        right: 0.7,
        bottom: 0.52,
        lineIndex: 2,
      ),
      const OcrBlock(
        id: 'b2',
        text: '请于7月22日18:00前取件',
        left: 0.08,
        top: 0.54,
        right: 0.85,
        bottom: 0.58,
        lineIndex: 3,
      ),
    ];

    final drafts = parser.parseCandidates(blocks: blocks, anchor: anchor);

    expect(drafts, hasLength(2));
    expect(
      drafts.map((draft) => draft.category),
      contains(CardCategory.ticket),
    );
    expect(
      drafts.map((draft) => draft.category),
      contains(CardCategory.pickup),
    );
  });

  group('卡片分类', () {
    CardCategory cat(String text) => parser.parseText(text, anchor).category;

    test('取件码 → pickup', () {
      expect(cat('菜鸟驿站 取件码 8-2-3009 今晚8点前取件'), CardCategory.pickup);
    });
    test('会议 → event', () {
      expect(cat('项目评审会议 7月25日14:00 会议室A'), CardCategory.event);
    });
    test('车次检票 → ticket', () {
      expect(cat('G102次 检票口B12 7月20日08:15发车 座位05车12F'), CardCategory.ticket);
    });
    test('医院复诊优先于普通预约 → healthcare', () {
      expect(cat('市人民医院复诊预约 7月25日14:00'), CardCategory.healthcare);
    });
    test('课程考试 → study', () {
      expect(cat('高等数学期末考试 7月25日14:00 考场A301'), CardCategory.study);
    });
    test('生活账单缴费 → bill', () {
      expect(cat('本月电费缴费截止 7月25日'), CardCategory.bill);
    });
    test('会员和证件到期 → renewal', () {
      expect(cat('视频会员到期：7月31日，请及时续费'), CardCategory.renewal);
      expect(cat('驾驶证年检 8月12日到期'), CardCategory.renewal);
    });
    test('优惠券兑换 → coupon', () {
      expect(cat('咖啡兑换券 7月31日到期 核销码 A7261'), CardCategory.coupon);
    });
    test('验证码 → temporarySecret 且敏感', () {
      final d = parser.parseText('您的验证码：392018，10分钟内有效', anchor);
      expect(d.category, CardCategory.temporarySecret);
      expect(d.isSensitive, isTrue);
    });
    test('仅截止语义 → deadline', () {
      expect(cat('材料提交截止：7月22日'), CardCategory.deadline);
    });
    test('随手记语义 → note', () {
      expect(cat('记得7月26日 10:00那件事'), CardCategory.note);
      expect(cat('备忘：周三去拿证件'), CardCategory.note);
    });
    test('无信号 → generic', () {
      expect(cat('7月26日 10:00 那件事'), CardCategory.generic);
    });
    test('快递面单运单号 → pickup 并提取单号', () {
      final d = parser.parseText(
        '顺丰速运\n运单号 SF1390881712345\n预计7月20日送达',
        anchor,
      );
      expect(d.category, CardCategory.pickup);
      expect(d.secretValue, 'SF1390881712345');
    });
    test('无场景关键词但有取件码标签 → pickup 兜底', () {
      final d = parser.parseText('8-2-3009 已到站\n取件码：3009', anchor);
      expect(d.category, CardCategory.pickup);
    });
    test('酒店入住退房 → ticket 且时间角色正确', () {
      final d = parser.parseText(
        '已订民宿\n入住：7月20日 14:00\n退房：7月22日 12:00',
        anchor,
      );
      expect(d.category, CardCategory.ticket);
      expect(
        d.suggestedAnchors[TemporalRole.eventStart],
        DateTime(2026, 7, 20, 14, 0),
      );
      expect(
        d.suggestedAnchors[TemporalRole.deadline],
        DateTime(2026, 7, 22, 12, 0),
      );
    });
    test('预售尾款 → deadline 角色', () {
      final d = parser.parseText('预售订单\n尾款支付截止 7月20日 22:00', anchor);
      expect(
        d.suggestedAnchors[TemporalRole.deadline],
        DateTime(2026, 7, 20, 22, 0),
      );
    });

    test('生活场景决策解释可读', () {
      final d = parser.parseText('医院复诊 7月25日14:00', anchor);
      expect(d.categoryExplanation, contains('就医'));
      expect(d.categoryExplanation, contains('复诊'));
    });
  });

  group('相对时长（验证码等临时信息）', () {
    test('10分钟内有效 → 导入时间 + 10 分钟的失效锚点', () {
      final d = parser.parseText('您的验证码：392018，10分钟内有效', anchor);
      expect(
        d.suggestedAnchors[TemporalRole.expiry],
        anchor.add(const Duration(minutes: 10)),
      );
      expect(d.category, CardCategory.temporarySecret);
    });
    test('30分钟内完成支付', () {
      final d = parser.parseText('订单已提交，请在30分钟内完成支付', anchor);
      expect(
        d.suggestedAnchors[TemporalRole.expiry],
        anchor.add(const Duration(minutes: 30)),
      );
    });
    test('有效期3天', () {
      final d = parser.parseText('临时门禁码 8842\n有效期3天', anchor);
      expect(
        d.suggestedAnchors[TemporalRole.expiry],
        anchor.add(const Duration(days: 3)),
      );
    });
    test('48小时内取件', () {
      final d = parser.parseText('包裹已到驿站，请在48小时内取件', anchor);
      expect(
        d.suggestedAnchors[TemporalRole.expiry],
        anchor.add(const Duration(hours: 48)),
      );
      expect(d.category, CardCategory.pickup);
    });
  });

  group('字段提取', () {
    test('标题不取“通知”二字', () {
      final d = parser.parseText('通知\n校园创新体验日\n活动时间：7月25日14:00', anchor);
      expect(d.title, '校园创新体验日');
    });
    test('地点提取', () {
      final d = parser.parseText('讲座\n地点：大学生活动中心 201\n7月25日14:00', anchor);
      expect(d.location, contains('大学生活动中心'));
    });
    test('入场码提取', () {
      final d = parser.parseText('入场码：A7281\n7月25日14:00', anchor);
      expect(d.secretValue, 'A7281');
    });
    test('手机号不误判为验证码', () {
      final d = parser.parseText('联系电话 13812345678', anchor);
      expect(d.secretValue, isNull);
    });
    test('身份证号触发高风险提示', () {
      final d = parser.parseText('身份证号 110101199003077578', anchor);
      expect(d.highRisk, isTrue);
      expect(d.warnings.join(), contains('不要保存'));
    });
  });

  group('边界与降级', () {
    test('无日期只有验证码 → 无候选 + 警告', () {
      final d = parser.parseText('门禁码：4471', anchor);
      expect(d.candidates, isEmpty);
      expect(d.warnings.join(), contains('没有认出时间'));
      expect(d.secretValue, '4471');
    });
    test('已过期历史通知：全部候选需确认', () {
      final d = parser.parseText('2025年3月1日 10:00 讲座', anchor);
      expect(d.candidates.single.requiresConfirmation, isTrue);
    });
    test('低置信度乱码夹杂日期仍可提取', () {
      final d = parser.parseText('◆◇x8!! 7月25日 14:00 §§乱码abc', anchor);
      expect(d.candidates, isNotEmpty);
      expect(d.candidates.single.normalizedDateTime!.day, 25);
    });
    test('空文本不崩溃', () {
      final d = parser.parseText('', anchor);
      expect(d.candidates, isEmpty);
      expect(d.title, '未命名卡片');
    });
    test('完整通知样例解析', () {
      final d = parser.parseText(
        '校园创新体验日\n报名截止：7月20日 18:00\n活动时间：7月25日 14:00—16:30\n'
        '地点：大学生活动中心 201\n入场码：A7281',
        anchor,
      );
      expect(d.title, '校园创新体验日');
      expect(
        d.suggestedAnchors[TemporalRole.deadline],
        DateTime(2026, 7, 20, 18, 0),
      );
      expect(
        d.suggestedAnchors[TemporalRole.eventStart],
        DateTime(2026, 7, 25, 14, 0),
      );
      expect(
        d.suggestedAnchors[TemporalRole.eventEnd],
        DateTime(2026, 7, 25, 16, 30),
      );
      expect(d.location, contains('201'));
      expect(d.secretValue, 'A7281');
      expect(d.category, CardCategory.event);
    });
  });
}
