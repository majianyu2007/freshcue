import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/logging/app_log.dart';
import '../../core/utils/redactor.dart';
import '../../data/database/app_schema.dart';
import '../../platform/capabilities.dart';

/// 诊断页：仅供开发构建查看平台能力与脱敏错误。
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('诊断')),
      body: ListView(
        children: [
          _handshakeSection(context),
          const Divider(),
          ListTile(
            title: const Text('文字识别'),
            subtitle: Text(
              controller.ocrModelStatus.ready
                  ? '${controller.ocrModelStatus.provider.label} 已就绪'
                  : '未安装可用识别组件',
            ),
            trailing: Icon(
              controller.ocrModelStatus.ready
                  ? Icons.check_circle
                  : Icons.cancel,
              color: controller.ocrModelStatus.ready
                  ? Colors.green
                  : Colors.grey,
            ),
          ),
          _cap(
            '代理提醒接口（Reminder Agent）',
            controller.reminderGateway.isAvailable(),
            subtitle: '接口存在不代表未签名模拟器拥有发布资格',
          ),
          ListTile(
            title: const Text('平台模式'),
            trailing: Text(
              controller.usingMockPlatform ? '模拟能力（Mock）' : '真实桥接',
              style: TextStyle(
                color: controller.usingMockPlatform
                    ? Colors.amber.shade800
                    : null,
              ),
            ),
          ),
          ListTile(
            title: const Text('数据库 schema 版本'),
            trailing: Text('v${AppSchema.version}'),
          ),
          const Divider(),
          const Padding(padding: EdgeInsets.all(16), child: Text('最近平台错误（脱敏）')),
          if (AppLog.recentErrors.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('无'),
            )
          else
            for (final e in AppLog.recentErrors.reversed.take(20))
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Text(
                  Redactor.redact(e),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 原生能力握手：显示 platform/apiVersion 与每个 Kit 的 compiled/available/reason。
  Widget _handshakeSection(BuildContext context) {
    final caps = controller.capabilities;
    if (!caps.bridged) {
      return const ListTile(
        title: Text('原生能力握手'),
        subtitle: Text('未桥接（桌面开发/测试环境）'),
        trailing: Icon(Icons.link_off, color: Colors.grey),
      );
    }
    const names = {
      'ocr': 'OCR',
      'share': '分享接收',
      'harmonyShare': '碰一碰 / 隔空分享',
      'reminders': '代理提醒',
      'liveActivity': '实况窗',
      'forms': '服务卡片',
      'database': '数据库',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('原生能力握手'),
          subtitle: Text(
            '${caps.platform} · API ${caps.apiVersion} · bridge v${caps.bridgeVersion}',
          ),
          trailing: const Icon(Icons.link, color: Colors.green),
        ),
        for (final e in names.entries)
          _kitRow(
            e.value,
            e.key == 'ocr'
                ? KitCapability(
                    compiled: caps.kit(e.key).compiled,
                    available: controller.ocrModelStatus.ready,
                    provider: controller.ocrModelStatus.provider,
                    reason: controller.ocrModelStatus.ready
                        ? ''
                        : caps.kit(e.key).reason,
                  )
                : caps.kit(e.key),
          ),
      ],
    );
  }

  Widget _kitRow(String label, KitCapability kit) {
    final compiled = kit.compiled;
    final available = kit.available;
    final reason = kit.reasonLabel;
    final detail = label == 'OCR' ? kit.provider.label : reason;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label)),
          _tag('编译', compiled, Colors.indigo),
          const SizedBox(width: 6),
          _tag('可用', available, Colors.green),
          const SizedBox(width: 8),
          if (detail.isNotEmpty)
            Expanded(
              child: Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String text, bool on, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: on
          ? color.withValues(alpha: 0.14)
          : Colors.grey.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$text${on ? '✓' : '✕'}',
      style: TextStyle(fontSize: 11, color: on ? color : Colors.grey),
    ),
  );

  Widget _cap(String name, Future<bool> check, {String? subtitle}) =>
      FutureBuilder<bool>(
        future: check,
        builder: (context, snap) => ListTile(
          title: Text(name),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: snap.connectionState != ConnectionState.done
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  snap.data == true ? Icons.check_circle : Icons.cancel,
                  color: snap.data == true ? Colors.green : Colors.grey,
                ),
        ),
      );
}
