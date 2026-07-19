/// 卡片分类。
enum CardCategory {
  pickup('取件/取餐'),
  event('活动/会议'),
  ticket('票务/出行'),
  deadline('截止事项'),
  temporarySecret('临时码'),
  generic('临时信息');

  const CardCategory(this.label);
  final String label;

  static CardCategory fromName(String name) => CardCategory.values.firstWhere(
    (c) => c.name == name,
    orElse: () => CardCategory.generic,
  );
}

/// 持久化状态（数据库中的事实状态）。
enum CardStatus {
  draft('待确认'),
  active('生效中'),
  completed('已完成'),
  archived('已归档');

  const CardStatus(this.label);
  final String label;

  static CardStatus fromName(String name) => CardStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => CardStatus.draft,
  );
}

/// 界面派生状态，由 FreshnessPolicy 根据当前时间计算，不落库。
enum Freshness {
  fresh('新鲜'),
  upcoming('临近'),
  urgent('紧急'),
  expired('已过期');

  const Freshness(this.label);
  final String label;
}

/// 时间语义角色。
enum TemporalRole {
  eventStart('活动开始'),
  eventEnd('活动结束'),
  deadline('截止'),
  departure('出发'),
  expiry('失效'),
  publishTime('发布时间'),
  unknown('未知');

  const TemporalRole(this.label);
  final String label;

  static TemporalRole fromName(String name) => TemporalRole.values.firstWhere(
    (r) => r.name == name,
    orElse: () => TemporalRole.unknown,
  );
}

/// 图片导入来源。
enum ImportSource { share, gallery, camera, demo }

/// 提醒实例状态。
enum ReminderStatus { scheduled, fired, snoozed, cancelled, failed }
