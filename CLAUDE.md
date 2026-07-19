# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

FreshCue（截期）is a Flutter app targeting HarmonyOS NEXT. It turns screenshots of short-lived information (events, pickup codes, tickets, deadlines) into editable time-limited cards: on-device OCR → Chinese time parsing → user confirmation → SQLite card → agent reminders → service card. Strictly local-first: no accounts, no backend, no analytics, and **no network permission** — never add `ohos.permission.INTERNET` or network-dependent packages.

Docs to consult for depth: `AGENTS.md` (conventions), `docs/architecture.md`, `docs/native-integration.md`, `docs/testing.md`. Note: user-facing strings, most docs, and test names are Chinese.

## Two Flutter toolchains (critical)

- **Desktop dev/test**: Homebrew Flutter 3.44.6 (`flutter`). `flutter run` on desktop uses explicitly-marked Mock gateways for native capabilities.
- **HAP builds**: CPF-Flutter 3.35.8-ohos-1.0.1 in `.toolchains/flutter-ohos/`, invoked via the user's shell alias `hflutter` (wraps `$FRESHCUE_OHOS_FLUTTER` with `$DEVECO_HOME` node on PATH). In non-interactive shells the alias may be missing; the underlying binary is `.toolchains/flutter-ohos/bin/flutter`.
- After switching toolchains, run `flutter clean` with the active toolchain if shader/engine cache errors appear.

## Commands

```bash
flutter pub get
tool/check.sh                                  # canonical gate: dart format check + flutter analyze + flutter test
flutter test test/parser/parser_test.dart      # one file
flutter test --plain-name '演示样例完整解析'      # one test (names are Chinese)
dart format lib test                           # fix formatting failures from check.sh
tool/native_ocr_smoke.sh                       # real ncnn det→rec gate on macOS; first run downloads pinned deps into .toolchains/
hflutter build hap --debug                     # HarmonyOS HAP (also --release)
```

**HAP build gotcha**: after Hvigor `assembleHap` succeeds, the Flutter wrapper still exits nonzero because no signing config exists. The artifact `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` is the success evidence — do not report this as a build failure, and do not describe an unsigned HAP as installable. Signing happens in DevEco Studio (open the `ohos/` subdirectory, never run scaffold commands against the repo root).

Any ArkTS/C++ change must be verified with a HAP build; desktop tests cannot compile it.

## Architecture

Dependency direction is strictly inward:

```text
lib/core ← lib/domain ← lib/data ← lib/app + lib/features
                         ↑
                    lib/platform
```

- `lib/core/` — `Clock`, `Result`, `AppFailure`, `AppLog`/`Redactor`, secure `IdGen`.
- `lib/domain/` — **pure Dart** (no Flutter/DB/platform imports): entities, freshness/reminder policies, and the parser pipeline (`screenshot_parser.dart`): `TimeSpanExtractor` → `DateNormalizer` → `RoleClassifier` → `CategoryClassifier`/`FieldExtractor` → aggregation into `ParsedDraft`. Regex only locates time spans; year inference, cross-year/leap-year handling, role classification, and field extraction are separate deterministic stages.
- `lib/data/` — SQLite schema/repositories (`app_schema.dart`), memory repositories, `ImageAssetService` (magic-byte validation, SHA-256 dedupe, sandbox copies, thumbnails), and `CardService`, which owns all cross-repository/platform transactions. Pages never write SQL.
- `lib/platform/` — gateway contracts (`gateways.dart`), MethodChannel impls (`channel_gateways.dart`), desktop mocks (`mock_gateways.dart`), registry, capability handshake. Channels: `freshcue/capabilities`, `freshcue/ocr`, `freshcue/share`(+`/events`), `freshcue/reminders`(+`/events`), `freshcue/forms`, `freshcue/calendar`.
- `lib/app/` + `lib/features/` — manual DI in `composition.dart` (+ `main.dart`); `AppController` is the **single `ChangeNotifier`** for app state, import flow, deep links, and service-card publication. No Provider/Riverpod/Bloc — do not introduce one.
- `ohos/entry/src/main/ets/` — `EntryAbility.ets` registers plugins and dispatches Wants (`ohos.want.action.sendData`, `freshcue://card/<id>`, `freshcue://archive`). Plugins: Capabilities, Share, Ocr (Core Vision → offline fallback), Reminder, Form, Calendar.
- `ohos/entry/src/main/cpp/` — N-API offline OCR: PaddleOCR PP-OCRv5 mobile det→rec on pinned ncnn + opencv-mobile static runtimes.
- `test/` — mirrors `lib/` layering.

Main flow: `ShareGateway`/gallery → `ImageAssetService` → `OcrGateway` → `ScreenshotParser` → `ReviewPage` (every field editable, explicit confirm) → `CardService` → repositories + `ReminderGateway` → `AppController.refresh` → `FormGateway` snapshot (max 3 cards, sensitive titles masked).

## Invariants

- **Time**: domain code never calls `DateTime.now()`; inject `Clock`. Tests use `FixedClock` (typically anchored `2026-07-18 10:00`).
- **Card states**: persisted states are only `draft/active/completed/archived`. Derived freshness `fresh/upcoming/urgent/expired` is computed at read time by `FreshnessPolicy` and never stored.
- **Errors**: recoverable failures cross layers as `AppFailure` with stable `FailureCode`; every `PlatformException.code` is mapped, raw exceptions never reach UI.
- **Privacy**: all logging goes through `AppLog`/`Redactor`; never log full OCR text, secrets/pickup codes, or private paths. Form Kit and notifications mask sensitive card content.
- **Reminders**: DB is the source of truth for intent; Reminder Agent is the executor. Editing a card time cancels old platform reminders, rebuilds instances, and rolls back on partial failure. Deleting a card cascades reminders, OCR records, and sandbox image copies (gallery originals untouched).
- **Persistence selection**: Release builds must not construct Mock gateways (`composition.dart` enforces this). Whether OHOS SQLite is used depends only on `Platform.operatingSystem` + a valid sandbox path — never on the (possibly slow) capability handshake.
- **Migrations**: append-only; current schema v2. A DB change needs a migration test from the previous real schema, not just fresh-database coverage.
- **`copyWith`**: nullable fields use a sentinel to distinguish "not passed" from "explicitly null".
- **OCR confidence**: per-line `confidence` stays `null` for both Core Vision and offline providers (the offline mean token score is uncalibrated and used only natively for low-quality filtering).
- **Pinned deps**: the `sqflite` OHOS fork in `pubspec.yaml` is pinned to an immutable commit — never change it to a floating branch. Same for the checksum-pinned ncnn/opencv archives.
- **Live View is intentionally absent**: API 24 offers no third-party create/publish route. Do not reintroduce a gateway, placeholder, or mock-success path for it.

## Testing

`flutter_test` only; SQLite tests run against a real in-memory DB via `sqflite_common_ffi`. Test observable contracts, not source text or incidental widget structure. Change-type requirements: a platform contract change needs Dart decode/error-mapping tests **and** an HAP compile; a lifecycle change needs failure injection proving cards/reminders/assets don't diverge.

## Claim vocabulary

No HarmonyOS device is connected. Use only evidence-backed terms for status: `已自动测试` (test passed), `已编译` (compiled into HAP), `已打包（未签名）` (unsigned HAP exists), `待设备验证` (runtime unverified), `已设备验证` (with recorded device evidence), `被阻塞`. Never claim OCR, share, reminders, SQLite, or service cards "work on HarmonyOS" without device evidence.

## Never commit

`.toolchains/`, `ohos/**/build/`, `.hvigor/`, HAP/HAR/HSP artifacts, signing material (`*.p7b`, `*.cer`, `*.p12`, `*.csr`, `signingConfigs/`), `tool/local.sh`.
