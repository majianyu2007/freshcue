import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/archive/archive_page.dart';
import '../features/card_detail/card_detail_page.dart';
import '../features/home/card_tile.dart';
import '../features/home/home_page.dart';
import '../features/import/import_flow.dart';
import '../features/settings/settings_page.dart';
import 'app_controller.dart';
import 'routes.dart';
import 'theme.dart';

class FreshCueApp extends StatelessWidget {
  const FreshCueApp({
    super.key,
    required this.controller,
    this.showOnboarding = true,
  });

  final AppController controller;
  final bool showOnboarding;

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
        home: AppShell(controller: controller, showOnboarding: showOnboarding),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            CardDetailPage(controller: widget.controller, cardId: id),
      ),
    ).then((_) => widget.controller.refresh());
  }

  @override
  Widget build(BuildContext context) {
    if (!onboardingDone) {
      return OnboardingPage(onDone: () => setState(() => onboardingDone = true));
    }
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final stage = widget.controller.importStage;
        final busy = stage == ImportStage.reading ||
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

/// 首次启动引导（3 屏，不请求任何权限）。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pager = PageController();
  int page = 0;

  static const _pages = [
    (Icons.ios_share, '分享截图', '在任何应用里看到含时间的截图，\n通过系统分享发送给 FreshCue。'),
    (Icons.psychology_outlined, '端上识别', '文字与时间在你的设备上识别，\n截图和内容不上传。'),
    (Icons.notifications_active_outlined, '到点提醒', '系统按时提醒你，\n过期的信息自动收进过期箱。'),
  ];

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
                          Icon(icon, size: 72,
                              color: Theme.of(context).colorScheme.primary,),
                          const SizedBox(height: 32),
                          Text(title,
                              style: Theme.of(context).textTheme.headlineSmall,),
                          const SizedBox(height: 16),
                          Text(body, textAlign: TextAlign.center),
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
                      : widget.onDone,
                  child: Text(page < _pages.length - 1 ? '下一步' : '开始使用'),
                ),
              ),
            ],
          ),
        ),
      );
}
