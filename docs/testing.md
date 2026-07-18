# Testing and QA

## 1. Canonical quality gate

From the repository root:

```bash
tool/check.sh
```

It runs:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

If an OHOS Flutter executable is active and `ohos/build-profile.json5` exists, the script also attempts a Debug HAP build. An unsigned HAP can be produced even though the wrapper returns nonzero at the signing check; read the build output and inspect the expected artifact.

Targeted commands:

```bash
flutter test test/parser/parser_test.dart
flutter test test/data/card_service_test.dart
flutter test test/widgets/app_widget_test.dart
flutter test --plain-name '演示样例完整解析'
```

Native OCR gate (real det → rec path, no Flutter Mock):

```bash
tool/native_ocr_smoke.sh
```

The first run downloads checksum-pinned macOS ncnn 20260526 and opencv-mobile 4.13.0 packages into ignored `.toolchains/` storage. It generates ten deterministic image layouts in memory and fails below 8/10 key-time matches. Latest observed result: **9/10**.

## 2. Automated coverage

Latest observed desktop gate: **136 tests passed**, `flutter analyze` **0 issues**.

| Area | Main tests | Contracts covered |
|---|---|---|
| Parser | `test/parser/parser_test.dart` | Span location, year inference, cross-year, leap-year, historical capture, semantic roles, categories, fields, high-risk values |
| Domain | `test/domain/domain_test.dart` | Freshness states, reminder expansion, quiet hours, deduplication, snooze |
| Data | `test/data/database_test.dart`, `test/data/card_service_test.dart`, `test/data/image_asset_service_test.dart` | SQLite v1→v2 migration, nullable confidence, transaction behavior, lifecycle orchestration, rollback, asset validation/cleanup |
| Platform | `test/platform/capabilities_test.dart`, `test/app/composition_test.dart` | Capability/provider contract, malformed maps, Release Mock prohibition, persistence selection |
| UI | `test/widgets/app_widget_test.dart` | Import/review flows, OCR failure recovery, permission denial, dark/large text, archive, deep links, Form Kit privacy snapshot |

Tests use `flutter_test` only. SQLite coverage runs against a real in-memory database through `sqflite_common_ffi`. Time-sensitive tests use `FixedClock`, generally anchored to `2026-07-18 10:00`, and must not depend on wall-clock time.

## 3. Required test style

- Test observable behavior and invariants, not source text or incidental widget structure.
- Keep domain tests pure Dart and deterministic.
- Use memory repositories and explicit Mock gateways for controller/widget tests.
- For nullable platform fields, cover missing, malformed and explicit `null` values.
- A platform contract change needs both Dart decode/error mapping coverage and an HAP compile.
- A DB change needs a migration from the previous real schema, not only a fresh-database test.
- A lifecycle change needs failure injection proving cards, reminders and assets do not diverge.
- Never call `DateTime.now()` in domain tests or production domain logic; inject `Clock`.

## 4. HAP compile gate

Use the OHOS toolchain for ArkTS/C++ changes:

```bash
hflutter build hap --debug
hflutter build hap --release
```

Expected build evidence:

- Hvigor `assembleHap` completes.
- `entry-default-unsigned.hap` exists under `ohos/entry/build/default/outputs/default/`.
- The package includes `libs/arm64-v8a/libentry.so`, both detector and recognizer model resources, `ets/modules.abc`, `ets/widgets.abc`, and a dynamic `resources/base/profile/form_config.json`.
- Merged manifest targets HarmonyOS API 24, has `debug:false` for Release, and requests only `PUBLISH_AGENT_REMINDER`.

Signing is a separate gate. Do not claim installation or runtime verification from an unsigned artifact.

## 5. Device acceptance checklist

All items below remain **待设备验证** until evidence records device model, system version, date, result and screenshot/log:

1. Install a signed Debug and Release HAP; cold start without a network connection.
2. Confirm diagnostic handshake: platform `ohos`; database, OCR, share, reminders and forms report compiled/available accurately.
3. Import representative white/dark, bubble, mixed-content, small-text, two-column, low-contrast and long screenshots; confirm editable OCR blocks.
4. Disable or fail Core Vision and verify offline det → rec OCR recognizes useful Chinese/time text in airplane mode.
5. Verify OCR failure still opens manual confirmation and preserves the source image.
6. Share one image into a cold app, then another into a hot app; each event is consumed once.
7. Share multiple images; only the first imports and `extraCount` produces the user warning.
8. Confirm a card, force-stop the app, and verify Reminder Agent fires at the scheduled time.
9. Tap a notification; verify `freshcue://card/<id>` opens the correct card. Complete and snooze in-app.
10. Edit a card time; verify old reminders disappear and only rebuilt reminders remain.
11. Delete a card; verify reminders and app sandbox copies are removed while the gallery original remains.
12. Restart the device; verify SQLite cards and valid agent reminders survive/reconcile.
13. Add the 2×4 `freshcue_cards` service card; verify up to three nearest active cards, compact time labels and row deep links.
14. Complete/archive/delete cards and confirm the launcher card refreshes with no stale row.
15. Create a sensitive temporary-secret card and confirm Form Kit and lock-screen notification content show no original secret/title value.
16. Exercise rotated/EXIF images and large/low-contrast screenshots; verify block coordinates and thumbnails.

## 6. Evidence vocabulary

Use only claims supported by the executed gate:

- **已自动测试**: an automated test was executed and passed.
- **已编译**: source was type-checked/compiled into the HAP.
- **已打包（未签名）**: unsigned HAP exists; not installable evidence.
- **已设备验证**: run on a named device/system with recorded evidence.
- **待设备验证**: static, test or build evidence exists, but runtime behavior is unknown.
- **被阻塞**: a named external prerequisite such as signing account or device is absent.

Compilation does not prove device API availability, permission prompts, launcher Form updates, process-death reminder behavior or OCR accuracy on real screenshots.
