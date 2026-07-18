import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('设置'), floating: true),
        SliverList.list(
          children: [
            const _SectionHeader('提醒'),
            const ListTile(
              leading: Icon(Icons.notifications_outlined),
              title: Text('默认提醒模板'),
              subtitle: Text('跟随卡片分类（活动：1天/1小时/10分钟前）'),
            ),
            const ListTile(
              leading: Icon(Icons.bedtime_outlined),
              title: Text('安静时段'),
              subtitle: Text('23:00 – 07:00，仅调整非紧急提醒'),
            ),
            const _SectionHeader('隐私'),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('锁屏隐私'),
              subtitle: Text('临时码卡片在锁屏通知中隐藏内容'),
            ),
            const ListTile(
              leading: Icon(Icons.image_outlined),
              title: Text('保留应用内原图副本'),
              subtitle: Text('删除卡片时同时删除副本；不影响图库'),
            ),
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('数据不出设备'),
              subtitle: Text('截图、识别文字与提醒全部保存在本机，无网络权限'),
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
