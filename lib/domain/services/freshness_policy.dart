import '../entities/temporal_card.dart';
import '../enums/enums.dart';

/// 根据当前时间计算界面派生状态。不写库，避免状态漂移。
class FreshnessPolicy {
  const FreshnessPolicy({
    this.upcomingWindow = const Duration(hours: 24),
    this.urgentWindow = const Duration(hours: 2),
  });

  final Duration upcomingWindow;
  final Duration urgentWindow;

  Freshness evaluate(TemporalCard card, DateTime now) {
    final expiry = card.effectiveExpiry;
    if (expiry != null && !expiry.isAfter(now)) return Freshness.expired;

    final next = card.nextKeyTime(now);
    if (next == null) {
      // 有关键时间但全部过去 → 过期；完全无时间 → 按新鲜处理。
      return card.keyTimes.isEmpty ? Freshness.fresh : Freshness.expired;
    }
    final remaining = next.$2.difference(now);
    if (remaining <= urgentWindow) return Freshness.urgent;
    if (remaining <= upcomingWindow) return Freshness.upcoming;
    return Freshness.fresh;
  }

  /// 首页副标题，如“报名截止还有 2 天”。
  String describeNext(TemporalCard card, DateTime now) {
    final next = card.nextKeyTime(now);
    if (next == null) {
      final expiry = card.effectiveExpiry;
      if (expiry != null && !expiry.isAfter(now)) return '已过期';
      return '无关键时间';
    }
    final (role, at) = next;
    final d = at.difference(now);
    final String rel;
    if (d.inDays >= 1) {
      rel = '还有 ${d.inDays} 天';
    } else if (d.inHours >= 1) {
      rel = '还有 ${d.inHours} 小时';
    } else if (d.inMinutes >= 1) {
      rel = '还有 ${d.inMinutes} 分钟';
    } else {
      rel = '即将到达';
    }
    return '${role.label}$rel';
  }
}
