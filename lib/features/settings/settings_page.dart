import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../platform/gateways.dart';
import '../diagnostics/diagnostics_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      const SliverAppBar(title: Text('设置'), floating: true),
      SliverList.list(
        children: [
          const _SectionHeader('常用设置'),
          _DestinationTile(
            icon: Icons.notifications_active_outlined,
            title: '提醒',
            subtitle:
                '${controller.notificationPermissionGranted == true ? '通知已开启' : '通知未开启'} · '
                '${controller.quietHoursEnabled ? '${_hour(controller.quietStartHour)} – ${_hour(controller.quietEndHour)} 安静时段' : '安静时段已关闭'}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReminderSettingsPage(controller: controller),
              ),
            ),
          ),
          _DestinationTile(
            icon: Icons.document_scanner_outlined,
            title: '文字识别',
            subtitle: controller.ocrModelStatus.ready
                ? '${controller.ocrModelStatus.provider.label} · 已就绪'
                : '需要安装离线识别组件',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => OcrSettingsPage(controller: controller),
              ),
            ),
          ),
          _DestinationTile(
            icon: Icons.privacy_tip_outlined,
            title: '隐私与数据',
            subtitle: controller.showSensitiveCodes
                ? '取件码直接显示 · 图片只在本机处理'
                : '取件码默认隐藏 · 图片只在本机处理',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PrivacySettingsPage(controller: controller),
              ),
            ),
          ),
          const _SectionHeader('应用'),
          _DestinationTile(
            icon: Icons.info_outline,
            title: '关于截期',
            subtitle: '版本 0.1.0',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
          ),
          if (kDebugMode) ...[
            const _SectionHeader('开发'),
            _DestinationTile(
              icon: Icons.build_outlined,
              title: '开发诊断',
              subtitle: '能力状态与脱敏错误记录',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DiagnosticsPage(controller: controller),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    ],
  );
}

class ReminderSettingsPage extends StatelessWidget {
  const ReminderSettingsPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _permissionTap(BuildContext context) async {
    try {
      if (controller.notificationPermissionGranted == true) {
        await controller.openNotificationSettings();
      } else {
        await controller.requestNotificationPermission();
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法打开通知设置')));
      }
    }
  }

  Future<void> _updateQuietHours(
    BuildContext context, {
    bool? enabled,
    int? startHour,
    int? endHour,
  }) async {
    final failures = await controller.updateQuietHours(
      enabled: enabled ?? controller.quietHoursEnabled,
      startHour: startHour ?? controller.quietStartHour,
      endHour: endHour ?? controller.quietEndHour,
    );
    if (context.mounted && failures > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('设置已保存，$failures 条系统提醒需要稍后重试')));
    }
  }

  Future<void> _pickHour(BuildContext context, {required bool start}) async {
    final current = start ? controller.quietStartHour : controller.quietEndHour;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
      helpText: start ? '安静时段开始' : '安静时段结束',
    );
    if (picked == null || !context.mounted) return;
    await _updateQuietHours(
      context,
      startHour: start ? picked.hour : null,
      endHour: start ? null : picked.hour,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提醒')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        children: [
          const _SectionHeader('系统通知'),
          ListTile(
            leading: Icon(
              controller.notificationPermissionGranted == true
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: const Text('通知权限'),
            subtitle: Text(
              controller.notificationPermissionGranted == true
                  ? '已开启；点击进入系统设置，可关闭或调整通知'
                  : '未开启；点击申请通知权限',
            ),
            trailing: controller.requestingNotificationPermission
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: controller.requestingNotificationPermission
                ? null
                : () => _permissionTap(context),
          ),
          _DestinationTile(
            icon: Icons.science_outlined,
            title: '通知测试',
            subtitle: '检查通知栏显示，不创建卡片或定时提醒',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => NotificationTestPage(controller: controller),
              ),
            ),
          ),
          const _SectionHeader('安静时段'),
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('避开夜间提醒'),
            subtitle: const Text('仅调整提前 12 小时以上的非紧急提醒'),
            value: controller.quietHoursEnabled,
            onChanged: (value) => _updateQuietHours(context, enabled: value),
          ),
          ListTile(
            enabled: controller.quietHoursEnabled,
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('开始时间'),
            trailing: Text(_hour(controller.quietStartHour)),
            onTap: () => _pickHour(context, start: true),
          ),
          ListTile(
            enabled: controller.quietHoursEnabled,
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('结束时间'),
            trailing: Text(_hour(controller.quietEndHour)),
            onTap: () => _pickHour(context, start: false),
          ),
        ],
      ),
    ),
  );
}

class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  bool sending = false;

  Future<void> _send() async {
    if (sending) return;
    setState(() => sending = true);
    try {
      final granted = await widget.controller.requestNotificationPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先开启通知权限')));
        }
        return;
      }
      await widget.controller.sendInstantNotification();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('测试通知已发送，请查看通知栏')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('发送失败，请检查系统通知设置')));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知测试')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.notifications_none, size: 56),
        const SizedBox(height: 20),
        Text('发送一条即时通知', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('只用于检查通知栏是否能够显示，不会创建五分钟提醒，也不会写入时效箱。'),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: sending ? null : _send,
          icon: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('发送测试通知'),
        ),
      ],
    ),
  );
}

class OcrSettingsPage extends StatefulWidget {
  const OcrSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends State<OcrSettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshOcrModelStatus();
  }

  Future<void> _download() async {
    final source = await _chooseOcrSource(context);
    if (source == null || !mounted) return;
    try {
      await widget.controller.downloadOcrModels(source);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('离线识别组件已校验并安装')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载失败，请更换线路后重试')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除离线识别组件？'),
        content: const Text('删除后仍可手动录入信息；需要图片识别时可以重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteOcrModels();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('离线识别组件已删除')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请重启应用后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('文字识别')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final status = widget.controller.ocrModelStatus;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      status.ready ? Icons.check_circle : Icons.info_outline,
                      color: status.ready ? Colors.green : null,
                      size: 32,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status.ready ? '文字识别已就绪' : '需要识别组件',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            status.coreVisionSupported
                                ? '使用 ${status.provider.label}'
                                : status.installed
                                ? '使用离线 OCR · ${status.version}'
                                : '约 10.2 MB，下载后完全在本机识别',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.controller.downloadingOcrModels) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: status.downloadProgress),
              const SizedBox(height: 8),
              Text('正在下载并校验 ${(status.downloadProgress * 100).round()}%'),
            ],
            const _SectionHeader('组件管理'),
            if (status.coreVisionSupported)
              const ListTile(
                leading: Icon(Icons.memory_outlined),
                title: Text('无需额外组件'),
                subtitle: Text('当前设备提供系统文字识别能力'),
              )
            else ...[
              ListTile(
                enabled: !widget.controller.downloadingOcrModels,
                leading: Icon(
                  status.installed ? Icons.swap_horiz : Icons.download_outlined,
                ),
                title: Text(status.installed ? '更换下载线路或重新安装' : '下载离线识别组件'),
                subtitle: const Text('GitHub、国内加速和备用加速均校验完整性'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _download,
              ),
              if (status.installed)
                ListTile(
                  enabled: !widget.controller.downloadingOcrModels,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除离线识别组件'),
                  subtitle: const Text('释放约 10.2 MB 本机空间'),
                  onTap: _delete,
                ),
            ],
            const _SectionHeader('数据说明'),
            const _InformationCard(
              icon: Icons.phonelink_lock_outlined,
              title: '图片不上传',
              body: '网络只在你主动下载识别组件时使用。截图和识别文字始终留在本机。',
            ),
          ],
        );
      },
    ),
  );
}

class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('隐私与数据')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        children: [
          const _SectionHeader('取件码与临时码'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('直接显示敏感码'),
            subtitle: Text(
              controller.showSensitiveCodes
                  ? '应用、锁屏通知、服务卡片和主动分享均显示完整码'
                  : '上述位置默认遮罩；需要时可在详情页查看',
            ),
            value: controller.showSensitiveCodes,
            onChanged: controller.setShowSensitiveCodes,
          ),
          const _SectionHeader('本机数据'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _InformationCard(
              icon: Icons.verified_user_outlined,
              title: '只在设备上处理',
              body: '图片和识别结果不上传。应用保存原图副本以便回看，删除卡片时同步删除副本，不影响系统图库。',
            ),
          ),
        ],
      ),
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于截期')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Icon(
          Icons.hourglass_top_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          '截期 FreshCue',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        const Text('版本 0.1.0', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        const _InformationCard(
          icon: Icons.auto_awesome_outlined,
          title: '把截图变成会提醒的时效信息',
          body: '拍照或导入截图，在本机识别时间、地点和取件码，确认后生成卡片与提醒。',
        ),
        const SizedBox(height: 12),
        const _InformationCard(
          icon: Icons.lock_outline,
          title: '本地优先',
          body: '无需账号和后端，不上传用户图片或识别内容。',
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('开源许可'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: '截期 FreshCue',
            applicationVersion: '0.1.0',
          ),
        ),
      ],
    ),
  );
}

Future<OcrDownloadSource?> _chooseOcrSource(BuildContext context) =>
    showModalBottomSheet<OcrDownloadSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('选择下载线路'),
              subtitle: Text('所有线路都会进行大小和 SHA-256 完整性校验'),
            ),
            for (final option in const [
              (OcrDownloadSource.github, 'GitHub', '适合能够直接访问 GitHub 的网络'),
              (OcrDownloadSource.ghproxy, '国内加速', '通过 ghproxy.net 下载'),
              (OcrDownloadSource.fastly, '备用加速', '通过 ghfast.top 下载'),
            ])
              ListTile(
                title: Text(option.$2),
                subtitle: Text(option.$3),
                onTap: () => Navigator.pop(context, option.$1),
              ),
          ],
        ),
      ),
    );

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
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

String _hour(int hour) => '${hour.toString().padLeft(2, '0')}:00';
