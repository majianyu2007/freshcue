import 'package:flutter/material.dart';

import '../domain/enums/enums.dart';

/// 截期视觉语言：纸张般的暖底色、墨色正文和少量朱砂强调。
/// 状态色只表达时效，不用渐变与大面积高饱和色。
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFFE05A47);
  static const ink = Color(0xFF252422);
  static const paper = Color(0xFFFFFBF6);
  static const freshColor = Color(0xFF2D7D6C);
  static const upcomingColor = Color(0xFFB5652A);
  static const urgentColor = Color(0xFFC94335);
  static const expiredColor = Color(0xFF77736E);

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
    CardCategory.study => Icons.school_outlined,
    CardCategory.healthcare => Icons.medical_services_outlined,
    CardCategory.ticket => Icons.confirmation_number_outlined,
    CardCategory.bill => Icons.receipt_long_outlined,
    CardCategory.renewal => Icons.autorenew,
    CardCategory.coupon => Icons.local_offer_outlined,
    CardCategory.deadline => Icons.flag_outlined,
    CardCategory.temporarySecret => Icons.password_outlined,
    CardCategory.note => Icons.edit_note_outlined,
    CardCategory.generic => Icons.sticky_note_2_outlined,
  };

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: dark ? const Color(0xFF1C1B1A) : paper,
    );
    final textTheme = Typography.material2021().black.copyWith(
      headlineMedium: const TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      titleLarge: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: const TextStyle(fontSize: 15, height: 1.45),
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: dark
          ? Typography.material2021().white.merge(textTheme)
          : textTheme,
      useMaterial3: true,
      // 页面进出统一使用轻快的前进式淡入淡出，避免生硬跳变。
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        color: dark ? scheme.surfaceContainerLow : Colors.white,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: dark ? Colors.white : ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? scheme.surfaceContainer : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
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
