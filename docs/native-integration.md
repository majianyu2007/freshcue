# Native Integration

## 1. Verified toolchain

- Desktop development: Homebrew Flutter 3.44.6.
- HAP build: CPF-Flutter 3.35.8-ohos-1.0.1 at `.toolchains/flutter-ohos/`.
- HarmonyOS SDK: DevEco Studio bundled 6.1.1 / API 24.
- Application: `com.freshcue.app`, entry module `entry`, phone, arm64-v8a.

Use the OHOS Flutter wrapper/alias for HAP builds:

```bash
hflutter build hap --debug
hflutter build hap --release
```

After `assembleHap` succeeds, an unsigned package is written to:

```text
ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

Without `signingConfigs`, the Flutter command subsequently returns nonzero and asks for DevEco signing. This means “compiled and packaged, unsigned,” not “installable.”

When switching between desktop and OHOS Flutter, run `flutter clean` with the active toolchain if engine shader caches are incompatible.

## 2. DevEco open, sign and run

1. Open the repository's `ohos/` subdirectory in DevEco Studio.
2. Select **File → Project Structure → Signing Configs**.
3. Enable **Automatically generate signature** and sign in with a Huawei account.
4. Connect a compatible HarmonyOS NEXT device and confirm it appears with `hdc list targets`.
5. Run from DevEco, or build/install a signed HAP using the OHOS Flutter/hdc tools.

Never commit certificates, private keys, `.toolchains/`, `.hvigor/`, `build/`, or HAP artifacts.

## 3. Plugin registration and channels

`EntryAbility.ets` registers the generated Flutter plugins plus:

| Plugin | Channel | Purpose |
|---|---|---|
| `CapabilitiesPlugin` | `freshcue/capabilities` | Report platform/API/bridge and per-kit status |
| `SharePlugin` | `freshcue/share`, `freshcue/share/events` | Photo picker, cold/hot share delivery and deduplication |
| `OcrPlugin` | `freshcue/ocr` | Core Vision and offline OCR routing |
| `ReminderPlugin` | `freshcue/reminders`, `freshcue/reminders/events` | Permission, publish/cancel and notification deep links |
| `FormPlugin` | `freshcue/forms` | Persist redacted snapshot and refresh active service cards |

`EntryAbility.onCreate` dispatches the initial Want; `onNewWant` handles a hot-start Want. Supported routes:

- `ohos.want.action.sendData` with image URI(s): system share import.
- `freshcue://card/<id>`: notification/service-card deep link to card detail.
- `freshcue://archive`: service-card fallback when no card ID is present.

Dart converts all `PlatformException.code` values to stable `FailureCode` values. Adding a channel method requires updating the Dart contract, ArkTS implementation, capability reporting and a contract test together.

## 4. Offline OCR

`OcrPlugin` first asks Core Vision `textRecognition.recognizeText`. It loads the native offline provider once and uses it when Core Vision is unavailable or recognition throws.

Native components:

- `ohos/entry/src/main/cpp/napi_init.cpp`: N-API module `offline_ocr`.
- `offline_ocr.cpp`: image decode/preprocess, ncnn inference, CTC decode and line grouping.
- `ppocrv5_dict.h`: PaddleOCR recognition character dictionary.
- `third_party/ncnn-20260526-harmonyos/arm64-v8a/`: pinned HarmonyOS ncnn headers and static library.

Packaged resources:

- `PP_OCRv5_mobile_rec.ncnn.param`
- `PP_OCRv5_mobile_rec.ncnn.bin`
- `THIRD_PARTY_NOTICES.txt`, `APACHE-2.0.txt`, `BSD-3-Clause.txt`

The model performs recognition; text-region proposals come from deterministic image preprocessing and connected-component grouping. Results are normalized to Flutter coordinates. Provider values are explicit: `coreVision`, `offline`, `mock`, or `none`. The bridge never labels offline output as Core Vision and never fabricates per-line confidence.

A synthetic local smoke image was recognized as four expected Chinese lines by the same model/ncnn route. HarmonyOS runtime loading and camera/gallery image variability still require device verification.

## 5. Share receiving

The module declares a `sendData` skill for `general.image` URIs and accepts at most nine URIs. `SharePlugin` uses `systemShare.getSharedData(want)`, extracts the first image, converts it to bytes, and reports `extraCount` for remaining images. Cold and hot events carry an ID; consumed IDs are deduplicated across the ArkTS and Dart boundary.

`PhotoViewPicker` provides the explicit gallery-import path. The app copies bytes into its sandbox immediately and does not retain URI permissions.

## 6. Reminder Agent

`ReminderPlugin` calls `@ohos.reminderAgentManager.publishReminder` with calendar reminders and stores the returned integer ID. Cancellation uses that ID. A stable 31-bit hash is used only for the notification ID field; it is not a platform reminder ID.

Required permission: `ohos.permission.PUBLISH_AGENT_REMINDER`. The release manifest does not include `INTERNET`.

The API 24 `ActionButtonType` supports system actions such as close/snooze, not an arbitrary custom “complete” button. FreshCue therefore opens `freshcue://card/<id>` and lets the user complete or snooze inside the app.

## 7. Form Kit service card

Form Kit files:

- `ohos/entry/src/main/ets/form/FreshCueFormAbility.ets`: `FormExtensionAbility`; serves initial data from Preferences.
- `ohos/entry/src/main/ets/form/pages/FreshCueCard.ets`: 2×4 ArkTS service-card UI.
- `ohos/entry/src/main/resources/base/profile/form_config.json`: form declaration.
- `FormPlugin.ets`: receives Flutter snapshots, stores JSON in Preferences, calls `formProvider.updateForm` for running `freshcue_cards` instances.

Snapshot contract: at most three records `{id, title, timeLabel}`. `AppController` sends only current active, non-expired cards and replaces sensitive titles with `敏感卡片`. Empty slots are overwritten during every update so removed cards do not remain visible. Tapping a row opens `freshcue://card/<id>`; tapping the empty state opens `freshcue://archive`.

The Form Kit API surface and HAP compilation are verified. Adding the card, update delivery and deep-link behavior require device/launcher validation.

## 8. API constraints and unsupported capability

The app compiles against API 24. Direct project API use is below that level, but lowering `compatibleSdkVersion` has not been validated against the Flutter engine and installed SDK set; do not lower it without a device and multi-SDK compatibility run.

Live View is intentionally absent. The local API 24 declarations describe system live-view notification content for system applications and expose no supported third-party create/publish route equivalent to the former `LiveViewGateway`. Do not reintroduce a placeholder, Mock-success path or speculative channel. Reconsider only with documented entitlement and an official usable API.
