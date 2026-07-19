import '../../core/utils/redactor.dart';

/// 带标签的临时码提取结果；标签用于反哺卡片分类（如取件码 → 取件）。
class LabeledSecret {
  const LabeledSecret(this.label, this.code);
  final String label;
  final String code;
}

/// 标题、地点、临时码、运单号提取。
class FieldExtractor {
  const FieldExtractor();

  static final _locationLabel = RegExp(
    r'(?:地点|地址|会场|教室|门店|取件柜|考场|位置|网点|驿站地址)\s*[:：]?\s*([^\n，。;；]{2,30})',
  );
  static final _codeLabel = RegExp(
    r'(取件码|取餐码|取货码|自提码|提货码|兑换码|门禁码|入场码|核销码|验证码|邀请码|临时密码|房号|柜号)'
    r'\s*[:：]?\s*([A-Za-z0-9\-]{3,12})',
  );

  /// 快递运单号：有明确标签时允许更长的字母数字串（如 SF 开头 15 位）。
  static final _waybillLabel = RegExp(
    r'(?:运单号|快递单号|物流单号|快递编号)\s*[:：]?\s*([A-Za-z0-9]{8,22})',
  );
  static final _timeish = RegExp(
    r'\d{1,2}[点时:：]|\d{1,2}\s*月|周[一二三四五六日天]|截止|时间',
  );
  static const _badTitles = {'通知', '公告', '提示', '温馨提示', '重要通知'};

  /// 标题：优先第一条语义完整、非纯标签的行。
  String extractTitle(List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_badTitles.contains(line)) continue; // “通知”两字不当标题
      if (_timeish.hasMatch(line) && line.length < 8) continue;
      if (line.length < 2) continue;
      // 去掉行内标签前缀
      final cleaned = line
          .replaceFirst(RegExp(r'^【?(通知|公告)】?[:：]?'), '')
          .trim();
      if (cleaned.length >= 2) {
        return cleaned.length > 30 ? cleaned.substring(0, 30) : cleaned;
      }
    }
    return '未命名卡片';
  }

  String? extractLocation(String fullText) {
    final m = _locationLabel.firstMatch(fullText);
    if (m == null) return null;
    var loc = m[1]!.trim();
    // 截断可能混入的下一个标签
    final cut = loc.indexOf(RegExp(r'(入场码|取件码|验证码|时间|电话)'));
    if (cut > 0) loc = loc.substring(0, cut).trim();
    return loc.isEmpty ? null : loc;
  }

  /// 临时码：必须有标签引导，避免把手机号/身份证误判为验证码。
  /// 返回标签供分类参考；无命中时回退到运单号提取。
  LabeledSecret? extractLabeledSecret(String fullText) {
    final m = _codeLabel.firstMatch(fullText);
    if (m != null) {
      final code = m[2]!;
      // 排除疑似手机号/证件号
      if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(code) && code.length < 15) {
        return LabeledSecret(m[1]!, code);
      }
    }
    final w = _waybillLabel.firstMatch(fullText);
    if (w != null) {
      final number = w[1]!;
      // 18 位纯数字可能是证件号，运单号场景仍需标签且不以 1 开头的手机号形态。
      if (!RegExp(r'^\d{17}[\dXx]$').hasMatch(number)) {
        return LabeledSecret('运单号', number);
      }
    }
    return null;
  }

  /// 兼容入口：只要码值。
  String? extractSecretCode(String fullText) =>
      extractLabeledSecret(fullText)?.code;

  /// 高风险信息检测（身份证/银行卡）→ 提示不建议保存。
  bool containsHighRiskInfo(String fullText) =>
      Redactor.containsHighRiskInfo(fullText);
}
