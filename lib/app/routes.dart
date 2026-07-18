/// 统一深链解析：通知、服务卡片、实况窗点击都经此进入页面。
/// 不信任外部卡片 ID —— 路由前查库，失败时安全回落首页。
class AppRoute {
  const AppRoute.home() : kind = RouteKind.home, id = null;
  const AppRoute.card(this.id) : kind = RouteKind.card;
  const AppRoute.archive() : kind = RouteKind.archive, id = null;
  const AppRoute.import_(this.id) : kind = RouteKind.import_;

  final RouteKind kind;
  final String? id;

  static AppRoute parse(String uri) {
    final u = Uri.tryParse(uri);
    if (u == null || u.scheme != 'freshcue') return const AppRoute.home();
    switch (u.host) {
      case 'card':
        final id = u.pathSegments.firstOrNull;
        return id == null || id.isEmpty || id.length > 64
            ? const AppRoute.home()
            : AppRoute.card(id);
      case 'archive':
        return const AppRoute.archive();
      case 'import':
        final id = u.pathSegments.firstOrNull;
        return id == null ? const AppRoute.home() : AppRoute.import_(id);
      default:
        return const AppRoute.home();
    }
  }
}

enum RouteKind { home, card, archive, import_ }
