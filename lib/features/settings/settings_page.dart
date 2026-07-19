import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../platform/gateways.dart';
import '../diagnostics/diagnostics_page.dart';

/// 设置页。诊断页 Debug 直接可见；Release 连续点 7 次版本号打开。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _versionTaps = 0;

  Future<void> _chooseOcrSource() async {
    final source = await showModalBottomSheet<OcrDownloadSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('选择下载线路'),
              subtitle: Text('所有线路都会进行完整性校验'),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('GitHub'),
              subtitle: const Text('适合能够直接访问 GitHub 的网络'),
              onTap: () => Navigator.pop(context, OcrDownloadSource.github),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('国内加速'),
              subtitle: const Text('通过 ghproxy.net 下载'),
              onTap: () => Navigator.pop(context, OcrDownloadSource.ghproxy),
            ),
            ListTile(
              leading: const Icon(Icons.bolt),
              title: const Text('备用加速'),
              subtitle: const Text('通过 ghfast.top 下载'),
              onTap: () => Navigator.pop(context, OcrDownloadSource.fastly),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      await widget.controller.downloadOcrModels(source);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('离线识别组件已安装')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载失败，请切换线路后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('设置'), floating: true),
        SliverList.list(
          children: [
            const _SectionHeader('提醒'),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('通知权限'),
              subtitle: Text(
                switch (widget.controller.notificationPermissionGranted) {
                  true => '已开启，截期可以按时发送提醒',
                  false => '未开启，点击重新申请',
                  null => '点击授权，开启到期提醒',
                },
              ),
              trailing: widget.controller.requestingNotificationPermission
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: widget.controller.requestingNotificationPermission
                  ? null
                  : () async {
                      final granted = await widget.controller
                          .requestNotificationPermission();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(granted ? '通知权限已开启' : '未获得通知权限，可稍后重试'),
                        ),
                      );
                    },
            ),
            ListTile(
              leading: const Icon(Icons.notification_add_outlined),
              title: const Text('发送即时通知'),
              subtitle: const Text('立即验证系统通知栏显示效果'),
              onTap: () async {
                final granted = await widget.controller
                    .requestNotificationPermission();
                if (!granted || !context.mounted) return;
                try {
                  await widget.controller.sendInstantNotification();
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('即时通知已发送')));
                  }
                } on Object {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('即时通知发送失败，请查看系统权限')),
                    );
                  }
                }
              },
            ),
            const ListTile(
              leading: Icon(Icons.bedtime_outlined),
              title: Text('安静时段'),
              subtitle: Text('23:00 – 07:00，仅调整非紧急提醒'),
            ),
            const _SectionHeader('文字识别'),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(
                widget.controller.ocrModelStatus.coreVisionSupported
                    ? '系统文字识别'
                    : '离线识别组件',
              ),
              subtitle: widget.controller.downloadingOcrModels
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value:
                              widget.controller.ocrModelStatus.downloadProgress,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '已下载 ${(widget.controller.ocrModelStatus.downloadProgress * 100).round()}%',
                        ),
                      ],
                    )
                  : Text(
                      widget.controller.ocrModelStatus.coreVisionSupported
                          ? '当前设备支持，无需下载额外组件'
                          : widget.controller.ocrModelStatus.installed
                          ? '已安装 ${widget.controller.ocrModelStatus.version}'
                          : '约 10.2 MB，仅在本机识别图片',
                    ),
              trailing: widget.controller.downloadingOcrModels
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : widget.controller.ocrModelStatus.coreVisionSupported
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : widget.controller.ocrModelStatus.installed
                  ? TextButton(
                      onPressed: widget.controller.deleteOcrModels,
                      child: const Text('删除'),
                    )
                  : const Icon(Icons.download_outlined),
              onTap:
                  widget.controller.ocrModelStatus.coreVisionSupported ||
                      widget.controller.downloadingOcrModels ||
                      widget.controller.ocrModelStatus.installed
                  ? null
                  : _chooseOcrSource,
            ),
            const _SectionHeader('隐私'),
            const ListTile(
              leading: Icon(Icons.visibility_outlined),
              title: Text('敏感码直接显示'),
              subtitle: Text('应用、锁屏通知、服务卡片与主动分享均显示完整取件码'),
            ),
            const ListTile(
              leading: Icon(Icons.image_outlined),
              title: Text('保留应用内原图副本'),
              subtitle: Text('删除卡片时同时删除副本；不影响图库'),
            ),
            const ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('本机处理'),
              subtitle: Text('图片和识别结果不上传；网络仅用于下载离线识别组件'),
            ),
            const _SectionHeader('关于'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('截期 FreshCue'),
              subtitle: const Text('版本 0.1.0 · 本地优先 · 隐私优先'),
              onTap: () {
                _versionTaps++;
                if (kDebugMode || _versionTaps >= 7) {
                  _versionTaps = 0;
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          DiagnosticsPage(controller: widget.controller),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    ),
  );
}
