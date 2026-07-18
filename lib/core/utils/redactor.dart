/// 脱敏工具：日志与崩溃信息中的敏感文本处理。
/// 规则见 docs/privacy-design.md。
class Redactor {
  Redactor._();

  static final _phone = RegExp(r'1[3-9]\d{9}');
  static final _idCard = RegExp(r'\d{17}[\dXx]|\d{15}');
  static final _bankCard = RegExp(r'\b\d{16,19}\b');
  static final _urlQuery = RegExp(r'(\?)[^\s]*');

  /// 对自由文本脱敏：手机号、身份证、银行卡、URL query。
  static String redact(String input) {
    var s = input;
    s = s.replaceAllMapped(_idCard, (m) => _mask(m[0]!, keep: 3));
    s = s.replaceAllMapped(_bankCard, (m) => _mask(m[0]!, keep: 4));
    s = s.replaceAllMapped(_phone, (m) => _mask(m[0]!, keep: 3));
    s = s.replaceAllMapped(_urlQuery, (m) => '?«redacted»');
    return s;
  }

  /// 遮罩秘密值（验证码等）：只留首字符，如 `A***1` → `A•••`。
  static String maskSecret(String secret) {
    if (secret.isEmpty) return secret;
    if (secret.length <= 2) return '••';
    return '${secret[0]}•••${secret[secret.length - 1]}';
  }

  static String _mask(String s, {required int keep}) {
    if (s.length <= keep) return '•' * s.length;
    return s.substring(0, keep) + '•' * (s.length - keep);
  }

  /// 检测高风险敏感内容（身份证/银行卡），用于导入时提示不建议保存。
  static bool containsHighRiskInfo(String text) =>
      _idCard.hasMatch(text) || _bankCard.hasMatch(text);
}
