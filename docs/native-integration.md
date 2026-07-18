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

- `napi_init.cpp`: N-API async boundary; retains the ArkTS pixel buffer instead of making a second RGBA copy.
- `ppocrv5.cpp`: pinned upstream PP-OCRv5 detector preprocessing, DB-map contour postprocessing, rotated crops and recognition CTC decoding.
- `offline_ocr.cpp`: 1280 px overlapping tiles, duplicate suppression, reading-order sort and normalized block coordinates.
- `third_party/ncnn-20260526-harmonyos/arm64-v8a/` and `third_party/opencv-mobile-4.13.0-harmonyos/arm64-v8a/`: pinned static runtimes.

The HAP packages both `PP_OCRv5_mobile_det` and `PP_OCRv5_mobile_rec` ncnn parameter/weight pairs, the recognition dictionary and license notices. ArkTS limits decode output to a 4096 px long side and 6 Mi pixels before allocating RGBA storage; native detection then tiles the bounded image so long screenshots do not collapse into one detector input.

The detector proposes text regions from its probability map. Regions are deduplicated and sorted top-to-bottom/left-to-right, perspective-oriented crops are passed to the recognizer, and CTC output becomes Flutter blocks. Provider values remain `coreVision`, `offline`, `mock`, or `none`. The offline mean token score is uncalibrated and is used only to reject low-quality native output; it is not exposed as line `confidence`, so both offline and Core Vision blocks preserve `null`.

`tool/native_ocr_smoke.sh` compiles this same C++ det → rec path on macOS using checksum-pinned ncnn/OpenCV packages. Its deterministic ten-case gate covers white notification, dark chat, chat bubble, image/text mix, small text, two columns, low contrast, long screenshot, ticket layout and dense list; the current observed result is 9/10.

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
- `ohos/entry/src/main/resources/base/profile/form_config.json`: dynamic (`isDynamic: true`) 2×4 declaration.
- `FormPlugin.ets`: stores Flutter snapshots, builds `FormBindingData`, queries running forms and calls `formProvider.updateForm`.

Snapshot contract: at most three records `{id, title, timeLabel}`. `AppController` sends only current active, non-expired cards and replaces sensitive titles with `敏感卡片`. Empty slots are overwritten during every update so removed cards do not remain visible. Tapping a row opens `freshcue://card/<id>`; tapping the empty state opens `freshcue://archive`.

`FreshCueFormAbility` returns the same flattened fields through `formBindingData.createFormBindingData` on add and scheduled update. The 2×4 UI consumes them through `LocalStorageProp`; each `FormLink` uses the API 24 `router` action with a `freshcue://` URI.

The Form Kit API surface and HAP compilation are verified. Adding the card, update delivery and deep-link behavior require device/launcher validation.

## 8. API constraints and unsupported capability

The app compiles against API 24. Direct project API use is below that level, but lowering `compatibleSdkVersion` has not been validated against the Flutter engine and installed SDK set; do not lower it without a device and multi-SDK compatibility run.

Live View is intentionally absent. The local API 24 declarations describe system live-view notification content for system applications and expose no supported third-party create/publish route equivalent to the former `LiveViewGateway`. Do not reintroduce a placeholder, Mock-success path or speculative channel. Reconsider only with documented entitlement and an official usable API.
