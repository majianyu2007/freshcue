/// 可注入时钟。领域逻辑禁止直接调用 [DateTime.now]，
/// 一律通过 [Clock] 获取当前时间，以便测试冻结时间。
abstract interface class Clock {
  DateTime now();
}

/// 真实系统时钟。
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// 测试/演示用固定或可推进时钟。
class FixedClock implements Clock {
  FixedClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  set now(DateTime value) => _now = value;

  void advance(Duration d) => _now = _now.add(d);
}
