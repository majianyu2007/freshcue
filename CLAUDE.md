# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

FreshCue（截期）is a HarmonyOS NEXT app: share a screenshot of temporary info (event notices, pickup codes, tickets) → on-device OCR → Chinese temporal parsing that distinguishes multiple time roles (报名截止 vs 活动开始 vs 失效 vs 发布时间) → user confirms → agent reminders → auto-archive on expiry. No account, no cloud, no backend, no network permission. UI is Flutter; only OCR / share receive / agent reminders / live view are bridged to ArkTS.

## Toolchains (two, kept separate)

- **Desktop dev/test** uses the system Homebrew Flutter (`flutter` on PATH, currently 3.44.6). Runs analyze + all unit/widget tests.
- **HAP builds** use the OHOS-adapted Flutter (CPF-Flutter `3.35.8-ohos-1.0.1`, Dart 3.9.2) at `.toolchains/flutter-ohos/` (gitignored), invoked via the `hflutter` alias defined in `~/.zshrc` (marker block `FreshCue HarmonyOS Toolchain`). The alias scopes DevEco's node v18 + China mirror so it doesn't shadow the global nvm node or the Homebrew flutter. The HarmonyOS SDK is DevEco Studio's bundled one: **HarmonyOS 6.1.1 / API 24**.

After switching between the two toolchains, run `flutter clean` once — otherwise the `ink_sparkle.frag` shader from one engine cache fails to decode under the other (a cache artifact, not a code failure).

## Commands

```bash
# Desktop (Homebrew Flutter)
tool/check.sh                    # format-check + analyze + full test suite (the canonical gate)
flutter analyze                  # must be 0 issues
flutter test                     # 119 tests
flutter test test/parser/parser_test.dart                 # one file
flutter test --plain-name '演示样例完整解析'               # one test by name
flutter run                      # desktop debug (shows yellow "模拟能力" mock banner)

# HAP build (OHOS Flutter) — needs a new terminal so ~/.zshrc block is loaded
cd ~/Project/freshcue && hflutter build hap --debug
# artifact: ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

To verify an ArkTS change actually type-checks (hvigor incremental builds are fast and can mislead): `rm -rf ohos/entry/build ohos/.hvigor` before `hflutter build hap --debug` for a clean rebuild. Injecting a deliberate type error and confirming `hvigor ERROR: ArkTS Compiler Error` is the reliable proof the compiler is checking your file.

DevEco: open the **`ohos/` subfolder** (not the repo root — the root is a Flutter project without HarmonyOS markers). Full open/sign/emulator steps are in `docs/native-integration.md` §3.

## Architecture

Strict layering (`analysis_options.yaml` enforces strict-casts/inference/raw-types, `avoid_dynamic_calls`, trailing commas, single quotes):

- `lib/core/` — Clock, Result/AppFailure (stable `FailureCode` → Chinese `userMessage`), Redactor, AppLog, IdGen. No Flutter deps except logging.
- `lib/domain/` — **pure Dart, no platform deps.** Entities, enums, the parser pipeline, and policies. This is where the product's real logic lives and where most tests point.
- `lib/data/` — SQL (`sqflite_common` API) + memory repositories, `ImageAssetService`, and `CardService` (orchestration).
- `lib/platform/` — 4 Gateway interfaces + `channel_gateways.dart` (real MethodChannel impls) + `mock_gateways.dart` (Debug only) + `PlatformRegistry` + `capabilities.dart` (handshake).
- `lib/app/` + `lib/features/` — `AppController` (a `ChangeNotifier`, no state framework) and pages. Pages never write SQL directly.

### Load-bearing invariants

1. **Injectable Clock.** Domain code must never call `DateTime.now()`; take a `Clock` and use `FixedClock` in tests. All time-sensitive tests anchor to `2026-07-18 10:00`.
2. **Derived state is not persisted.** `fresh/upcoming/urgent/expired` is computed live by `FreshnessPolicy`; only `draft/active/completed/archived` are stored.
3. **Reminder Plan vs Instance.** `ReminderPlan` = intent ("截止前 2 小时"); `ReminderInstance` = absolute trigger time + platform id + status. `ReminderPolicy` expands plans (skip-past, dedup, quiet-hours 23:00–07:00 only shifts non-urgent). Editing a time = cancel all platform reminders → re-expand → atomic replace.
4. **DB is the source of truth for reminder intent; Reminder Agent is the executor.** `CardService.reconcile()` runs at startup (mark expired-but-scheduled as fired, backfill missing platform ids).
5. **Parser is the crown jewel** (`lib/domain/parser/`). Pipeline: `TimeSpanExtractor` (regex only *locates* spans) → `DateNormalizer` (anchors to capture time, year inference, cross-year/leap-year, historical-screenshot tolerance) → `RoleClassifier` (distance-decayed keyword scoring — **not** one giant regex; `publish_time` must not become an event anchor) → `CategoryClassifier` → `FieldExtractor` → `ScreenshotParser` assembles `ParsedDraft`. Heuristic scores are named `confidenceScore`/`roleConfidence`, kept separate from OCR-engine confidence.
6. **Mock never runs silently in Release.** `PlatformRegistry` asserts against it; Debug shows a persistent yellow banner when mocks are active. OHOS bridge presence is decided by the `freshcue/capabilities` handshake, and `main.dart` picks SQL (OHOS) vs in-memory (desktop) from it.

### Flutter ↔ ArkTS boundary

Channels: `freshcue/{capabilities, ocr, share (+events), reminders (+events), live_view}`. ArkTS plugins live in `ohos/entry/src/main/ets/plugins/` and register in `EntryAbility.ets`. `PlatformException.code` strings map to `FailureCode` in `channel_gateways.dart`. Reality constraints discovered from the real API 24 SDK (documented in `docs/hap-bringup-report.md`): Core Vision returns `cornerPoints` polygons with **no per-line confidence** (→ null, not fabricated); `ActionButtonType` has only CLOSE/SNOOZE so there are **no custom notification buttons** (complete/snooze happen in-app after tapping the notification's `wantAgent` deep link `freshcue://card/<id>`); share *receiving* is a Want/`sendData`-skill mechanism via `systemShare.getSharedData`, not the ShareKit send API.

Old pre-bringup reference ArkTS is preserved under `ohos-reference/` (compile-isolated, e.g. LiveView which needs AGC entitlement). `ohos/` itself is a real generated scaffold — don't overwrite it with `flutter create` over the repo root.

### DB migrations

`lib/data/database/app_schema.dart` — versioned, append-only (never edit historical migrations). Currently v2. Migration tests live in `test/data/database_test.dart` (real SQLite via `sqflite_common_ffi`).

## Honesty rules for this project

State capability status precisely using: `接口预留 / 参考代码 / 已编译 / 已模拟器验证 / 已真机验证 / 被阻塞`. There is **no device** (`hdc list targets` empty), so all runtime behavior (real OCR, share cold/hot start, reminder after process kill, notification routing) is unverified — never mark those passed. Don't claim HAP/device results you didn't produce. `docs/known-limitations.md` and `docs/device-test-checklist.md` track the honest state.

## Docs map

`docs/hap-bringup-report.md` (toolchain decision, HAP artifacts, per-Kit real-API findings) · `architecture.md` · `product-spec.md` (6 card categories + reminder templates) · `privacy-design.md` · `native-integration.md` (DevEco open/sign/run) · `testing.md` (coverage matrix) · `known-limitations.md`. The competition demo script was intentionally moved out of the repo to `~/Documents/freshcue/`.
