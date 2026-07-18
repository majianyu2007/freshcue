import 'package:flutter/services.dart';

import '../core/logging/app_log.dart';

/// 单个 Kit 的能力状态（来自原生 handshake，缺字段安全降级）。
class KitCapability {
  const KitCapability({
    required this.compiled,
    required this.available,
    this.reason = '',
  });

  factory KitCapability.fromMap(Object? raw) {
    if (raw is! Map) {
      return const KitCapability(
        compiled: false,
        available: false,
        reason: 'missing',
      );
    }
    return KitCapability(
      compiled: raw['compiled'] == true,
      available: raw['available'] == true,
      reason: raw['reason'] is String ? raw['reason'] as String : '',
    );
  }

  /// compiled=插件已编进当前 HAP；available=当前设备/权限允许使用。
  final bool compiled;
  final bool available;
  final String reason;

  /// reason 机器码 → 中文（UI 用）。
  String get reasonLabel => switch (reason) {
    'not_compiled' => '未编译进当前构建',
    'feature_disabled' => '实验开关未启用',
    'permission_denied' => '权限未授予',
    'device_unsupported' => '设备不支持',
    'missing' => '原生未上报',
    '' => '',
    _ => reason,
  };
}

/// 原生能力握手快照。
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.bridged,
    required this.platform,
    required this.apiVersion,
    required this.bridgeVersion,
    required this.filesDir,
    required this.kits,
  });

  /// 桥接不存在（桌面/测试环境）时的空快照。
  const PlatformCapabilities.unbridged()
    : bridged = false,
      platform = 'none',
      apiVersion = 0,
      bridgeVersion = 0,
      filesDir = null,
      kits = const {};

  factory PlatformCapabilities.fromMap(Map<Object?, Object?> m) {
    final rawKits = m['kits'];
    return PlatformCapabilities(
      bridged: true,
      platform: m['platform'] is String ? m['platform']! as String : 'unknown',
      apiVersion: m['apiVersion'] is int ? m['apiVersion']! as int : 0,
      bridgeVersion: m['bridgeVersion'] is int ? m['bridgeVersion']! as int : 0,
      filesDir: m['filesDir'] is String ? m['filesDir'] as String? : null,
      kits: {
        if (rawKits is Map)
          for (final e in rawKits.entries)
            if (e.key is String)
              e.key! as String: KitCapability.fromMap(e.value),
      },
    );
  }

  final bool bridged;
  final String platform;
  final int apiVersion;
  final int bridgeVersion;
  final String? filesDir;
  final Map<String, KitCapability> kits;

  bool get isOhos => bridged && platform == 'ohos';

  KitCapability kit(String name) =>
      kits[name] ??
      const KitCapability(compiled: false, available: false, reason: 'missing');
}

/// 握手服务：ping + getCapabilities。桥接缺席时返回 unbridged 快照（默认安全行为）。
class CapabilityService {
  static const _channel = MethodChannel('freshcue/capabilities');

  Future<PlatformCapabilities> fetch() async {
    try {
      final pong = await _channel.invokeMethod<String>('ping');
      if (pong != 'pong') return const PlatformCapabilities.unbridged();
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getCapabilities',
      );
      if (raw == null) return const PlatformCapabilities.unbridged();
      return PlatformCapabilities.fromMap(raw);
    } on MissingPluginException {
      return const PlatformCapabilities.unbridged();
    } on PlatformException catch (e) {
      AppLog.w('capabilities', '握手失败: ${e.code}');
      return const PlatformCapabilities.unbridged();
    }
  }
}
