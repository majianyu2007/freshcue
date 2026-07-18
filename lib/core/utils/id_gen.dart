import 'dart:math';

/// 简单 ID 生成器：时间无关的随机 128-bit hex。
/// 沙箱文件名也用它，保证不可预测（隐私要求 §19.3）。
class IdGen {
  IdGen._();

  static final Random _rng = Random.secure();

  static String newId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
