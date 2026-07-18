import 'package:freshcue/domain/parser/screenshot_parser.dart';
void main() {
  final p = ScreenshotParser();
  final d = p.parseText('发布于7月1日，7月8日开会', DateTime(2026, 7, 18, 10, 0));
  for (final c in d.candidates) {
    print('${c.rawText} | ${c.role} | conf=${c.roleConfidence} | ${c.normalizedDateTime} | alt=${c.alternativeRoles}');
  }
}
