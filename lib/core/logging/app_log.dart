import 'package:flutter/foundation.dart';

import '../utils/redactor.dart';

/// 应用内日志。所有消息先脱敏再输出；Release 仅保留 warning 以上，
/// 且不输出 OCR 全文、验证码或图片路径。
class AppLog {
  AppLog._();

  static final List<String> recentErrors = <String>[];

  static void d(String tag, String message) {
    if (kDebugMode) debugPrint('[$tag] ${Redactor.redact(message)}');
  }

  static void w(String tag, String message) {
    final m = '[$tag] ${Redactor.redact(message)}';
    if (kDebugMode) debugPrint('WARN $m');
    _remember('W $m');
  }

  static void e(String tag, String message, [Object? error]) {
    final m = '[$tag] ${Redactor.redact(message)}'
        '${error == null ? '' : ' (${error.runtimeType})'}';
    if (kDebugMode) debugPrint('ERROR $m');
    _remember('E $m');
  }

  static void _remember(String m) {
    recentErrors.add(m);
    if (recentErrors.length > 50) recentErrors.removeAt(0);
  }
}
