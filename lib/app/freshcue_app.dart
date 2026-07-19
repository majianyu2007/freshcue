import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/archive/archive_page.dart';
import '../features/card_detail/card_detail_page.dart';
import '../features/home/card_tile.dart';
import '../features/home/home_page.dart';
import '../features/import/import_flow.dart';
import '../features/settings/settings_page.dart';
import '../platform/gateways.dart';
import 'app_controller.dart';
import 'routes.dart';
import 'theme.dart';

class FreshCueApp extends StatelessWidget {
  const FreshCueApp({super.key, required this.controller, this.showOnboarding});

  final AppController controller;
  final bool? showOnboarding;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '截期 FreshCue',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AppShell(
      controller: controller,
      showOnboarding: showOnboarding ?? !controller.onboardingComplete,
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.showOnboarding,
  });

  final AppController controller;
  final bool showOnboarding;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  bool onboardingDone = false;

  @override
  void initState() {
    super.initState();
    onboardingDone = !widget.showOnboarding;
    widget.controller.pendingRoute.addListener(_onPendingRoute);
    widget.controller.addListener(_maybeOpenSharedDraft);
    // controller.start() 在 runApp 前完成；冷启动分享/通知可能已写入状态，
    // 因此监听器注册后必须主动消费一次，而不能只等后续变更。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeOpenSharedDraft();
      _onPendingRoute();
    });
  }

  @override
  void dispose() {
    widget.controller.pendingRoute.removeListener(_onPendingRoute);
    widget.controller.removeListener(_maybeOpenSharedDraft);
    super.dispose();
  }

  bool _reviewOpen = false;

  /// 分享/冷启动导入完成后自动进入确认页。
  void _maybeOpenSharedDraft() {
    if (_reviewOpen) return;
    if (widget.controller.importStage == ImportStage.done &&
        widget.controller.pendingDraft != null) {
      _reviewOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await openDraftReview(context, widget.controller);
        _reviewOpen = false;
      });
    }
  }

  void _onPendingRoute() {
    final uri = widget.controller.pendingRoute.value;
    if (uri == null) return;
    widget.controller.pendingRoute.value = null;
    final route = AppRoute.parse(uri);
    switch (route.kind) {
      case RouteKind.card:
        _openCard(route.id!);
      case RouteKind.archive:
        setState(() => tab = 1);
      case RouteKind.home:
      case RouteKind.import_:
        setState(() => tab = 0);
    }
  }

  void _openCard(String id) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) =>
                CardDetailPage(controller: widget.controller, cardId: id),
          ),
        )
        .then((_) => widget.controller.refresh());
  }

  @override
  Widget build(BuildContext context) {
    if (!onboardingDone) {
      return OnboardingPage(
        controller: widget.controller,
        onDone: () => setState(() => onboardingDone = true),
      );
    }
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final stage = widget.controller.importStage;
        final busy =
            stage == ImportStage.reading ||
            stage == ImportStage.recognizing ||
            stage == ImportStage.analyzing ||
            stage == ImportStage.preparing;
        return Scaffold(
          body: Column(
            children: [
              if (widget.controller.usingMockPlatform) const MockBanner(),
              Expanded(
                child: busy
                    ? ProcessingView(
                        stage: stage,
                        onCancel: widget.controller.cancelImport,
                      )
                    : IndexedStack(
                        index: tab,
                        children: [
                          HomePage(
                            controller: widget.controller,
                            onOpenCard: _openCard,
                          ),
                          ArchivePage(
                            controller: widget.controller,
                            onOpenCard: _openCard,
                          ),
                          SettingsPage(controller: widget.controller),
                        ],
                      ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.inbox_outlined),
                selectedIcon: Icon(Icons.inbox),
                label: '时效箱',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: '过期箱',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 首次启动引导：解释核心能力，在用户理解用途后申请通知权限。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final AppController controller;
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pager = PageController();
  int page = 0;
  bool finishing = false;

  static const _pages = [
    (Icons.add_a_photo_outlined, '拍下或导入', '拍照、从图库选择，或从其他应用分享截图。'),
    (Icons.document_scanner_outlined, '在本机识别', '图片和识别结果只保存在你的设备上。'),
    (Icons.notifications_active_outlined, '按时提醒', '允许通知后，截期会在关键时间到来前提醒你。'),
  ];

  Future<void> _finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    await widget.controller.requestNotificationPermission();
    await widget.controller.completeOnboarding();
    if (mounted) widget.onDone();
  }

  Future<void> _downloadOcr() async {
    final source = await showModalBottomSheet<OcrDownloadSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('下载离线识别组件'),
              subtitle: Text('请选择适合当前网络的线路'),
            ),
            for (final option in const [
              (OcrDownloadSource.github, 'GitHub', '直接下载'),
              (OcrDownloadSource.ghproxy, '国内加速', 'ghproxy.net'),
              (OcrDownloadSource.fastly, '备用加速', 'ghfast.top'),
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
    if (source == null || !mounted) return;
    try {
      await widget.controller.downloadOcrModels(source);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载失败，请换一条线路重试')));
      }
    }
  }

  Widget _capabilitySummary(BuildContext context) {
    final caps = widget.controller.capabilities;
    final entries = [
      ('本地存储', caps.kit('database').available),
      ('图片导入与分享', caps.kit('share').available),
      ('系统提醒', caps.kit('reminders').available),
      ('文字识别', widget.controller.ocrModelStatus.ready),
    ];
    return Card(
      margin: const EdgeInsets.only(top: 28),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      entry.$2 ? Icons.check_circle : Icons.info_outline,
                      size: 20,
                      color: entry.$2
                          ? Colors.green
                          : Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(entry.$1)),
                    Text(entry.$2 ? '可用' : '需要设置'),
                  ],
                ),
              ),
            if (!widget.controller.ocrModelStatus.ready) ...[
              const Divider(height: 24),
              const Text('这台设备需要安装离线识别组件（约 10.2 MB）。'),
              const SizedBox(height: 10),
              if (widget.controller.downloadingOcrModels) ...[
                LinearProgressIndicator(
                  value: widget.controller.ocrModelStatus.downloadProgress,
                ),
                const SizedBox(height: 6),
                Text(
                  '已下载 ${(widget.controller.ocrModelStatus.downloadProgress * 100).round()}%',
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: widget.controller.downloadingOcrModels
                    ? null
                    : _downloadOcr,
                icon: widget.controller.downloadingOcrModels
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: const Text('选择下载线路'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => page = i),
              itemBuilder: (context, i) {
                final (icon, title, body) = _pages[i];
                return Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Text(body, textAlign: TextAlign.center),
                      if (i == _pages.length - 1) _capabilitySummary(context),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              onPressed: page < _pages.length - 1
                  ? () => _pager.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    )
                  : _finish,
              child: finishing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(page < _pages.length - 1 ? '下一步' : '允许通知并开始'),
            ),
          ),
        ],
      ),
    ),
  );
}
