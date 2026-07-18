import 'package:flutter/material.dart';

import '../domain/enums/enums.dart';

/// 视觉语言：深靛蓝主色（时间与可靠），状态色仅用于状态，
/// 满足对比度要求，状态同时用图标/文字表达（不只靠颜色）。
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF3A3D8F); // 深靛蓝

  static const freshColor = Color(0xFF0E8A72); // 青绿
  static const upcomingColor = Color(0xFFB26A00); // 琥珀
  static const urgentColor = Color(0xFFC0392B); // 克制珊瑚红
  static const expiredColor = Color(0xFF757575);

  static Color freshnessColor(Freshness f, Brightness b) {
    final dark = b == Brightness.dark;
    return switch (f) {
      Freshness.fresh => dark ? const Color(0xFF4DD0B5) : freshColor,
      Freshness.upcoming => dark ? const Color(0xFFFFB74D) : upcomingColor,
      Freshness.urgent => dark ? const Color(0xFFFF8A80) : urgentColor,
      Freshness.expired => dark ? const Color(0xFFBDBDBD) : expiredColor,
    };
  }

  static IconData freshnessIcon(Freshness f) => switch (f) {
        Freshness.fresh => Icons.eco_outlined,
        Freshness.upcoming => Icons.schedule,
        Freshness.urgent => Icons.notification_important_outlined,
        Freshness.expired => Icons.inventory_2_outlined,
      };

  static IconData categoryIcon(CardCategory c) => switch (c) {
        CardCategory.pickup => Icons.local_shipping_outlined,
        CardCategory.event => Icons.event_outlined,
        CardCategory.ticket => Icons.confirmation_number_outlined,
        CardCategory.deadline => Icons.flag_outlined,
        CardCategory.temporarySecret => Icons.password_outlined,
        CardCategory.generic => Icons.sticky_note_2_outlined,
      };

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: scheme.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

String formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}年${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
}

String formatShort(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
}
