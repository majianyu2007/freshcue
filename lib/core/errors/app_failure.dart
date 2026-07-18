/// 统一失败类型。所有平台调用与数据操作错误映射到稳定错误码，
/// UI 依据 [code] 展示中文文案与可恢复动作。
enum FailureCode {
  imageReadFailed,
  imageFormatUnsupported,
  imageTooLarge,
  ocrUnavailable,
  ocrTimeout,
  ocrFailed,
  noTextFound,
  noTimeFound,
  databaseWriteFailed,
  notificationPermissionDenied,
  reminderScheduleFailed,
  storageFull,
  shareUriExpired,
  cardNotFound,
  cancelled,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.code, {this.debugDetail, this.recoverable = true});

  final FailureCode code;

  /// 脱敏后的技术信息，仅用于诊断页；不得包含 OCR 全文/验证码/敏感路径。
  final String? debugDetail;
  final bool recoverable;

  /// 面向用户的中文说明。
  String get userMessage => switch (code) {
    FailureCode.imageReadFailed => '无法读取这张图片，请重试或换一张。',
    FailureCode.imageFormatUnsupported => '暂不支持该图片格式。',
    FailureCode.imageTooLarge => '图片过大，请裁剪后重试。',
    FailureCode.ocrUnavailable => '本机文字识别能力不可用，可手动输入内容。',
    FailureCode.ocrTimeout => '文字识别超时，可重试或手动输入。',
    FailureCode.ocrFailed => '文字识别失败，可重试或手动输入。',
    FailureCode.noTextFound => '没有识别到文字，可手动输入内容。',
    FailureCode.noTimeFound => '没有识别到时间，可手动设定保鲜期。',
    FailureCode.databaseWriteFailed => '保存失败，请重试。',
    FailureCode.notificationPermissionDenied => '通知权限未开启，卡片已保存但不会提醒。可前往系统设置开启。',
    FailureCode.reminderScheduleFailed => '系统提醒创建失败，卡片已保存。',
    FailureCode.storageFull => '存储空间不足，无法保存图片。',
    FailureCode.shareUriExpired => '分享的图片已失效，请重新分享。',
    FailureCode.cardNotFound => '卡片不存在或已被删除。',
    FailureCode.cancelled => '操作已取消。',
    FailureCode.unknown => '出现未知问题，请重试。',
  };

  @override
  String toString() =>
      'AppFailure(${code.name}${debugDetail == null ? '' : ', $debugDetail'})';
}
