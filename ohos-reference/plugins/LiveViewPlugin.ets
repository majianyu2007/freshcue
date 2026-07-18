// ⚠️ 参考实现，未真机验证；实况窗需要测试/正式权益（见 docs/known-limitations.md）。
// channel: freshcue/live_view —— 本地实况窗倒计时（实验能力，feature flag 默认关）。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/liveview-create-locally-V5

import { liveViewManager } from '@kit.LiveViewKit';
import {
  MethodCall, MethodChannel, MethodResult, FlutterEngine,
} from '@ohos/flutter_ohos';

export class LiveViewPlugin {
  private activeIds = new Map<string, number>(); // cardId -> liveView sequence

  register(engine: FlutterEngine): void {
    new MethodChannel(
      engine.dartExecutor.getBinaryMessenger(), 'freshcue/live_view',
    ).setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.onCall(call, result);
      },
    });
  }

  private async onCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'isSupported':
        result.success(canIUse('SystemCapability.Ability.LiveViewService'));
        break;
      case 'isEnabledByUser': {
        try {
          result.success(await liveViewManager.isLiveViewEnabled());
        } catch (_e) {
          result.success(false);
        }
        break;
      }
      case 'hasEntitlement': {
        // 无直接查询 API：以一次真实创建的错误码为准；这里保守返回
        // isLiveViewEnabled 的结果，创建失败时映射 liveview_not_entitled。
        try {
          result.success(await liveViewManager.isLiveViewEnabled());
        } catch (_e) {
          result.success(false);
        }
        break;
      }
      case 'startCountdown': {
        // 仅允许前台调用（EntryAbility 保证），场景限 pickup/ticket/短时 event。
        try {
          const cardId = call.argument('cardId') as string;
          const view: liveViewManager.LiveView = {
            id: this.activeIds.size + 1,
            event: 'TIME_COUNTDOWN',
            liveViewData: {
              primary: {
                title: call.argument('title') as string,
                content: [],
                keepTime: Math.floor(
                  ((call.argument('targetAtMs') as number) - Date.now()) / 1000),
                clickAction: {
                  abilityName: 'EntryAbility',
                  uri: `freshcue://card/${cardId}`,
                },
              },
            },
          };
          const r = await liveViewManager.startLiveView(view);
          this.activeIds.set(cardId, r.id ?? view.id);
          result.success(null);
        } catch (e) {
          const name = (e as Error).name ?? '';
          result.error(
            name.includes('permission') ? 'liveview_not_entitled' : 'liveview_scene_unsupported',
            name, null);
        }
        break;
      }
      case 'stop': {
        try {
          const cardId = call.argument('cardId') as string;
          const id = this.activeIds.get(cardId);
          if (id !== undefined) {
            await liveViewManager.stopLiveView({ id: id });
            this.activeIds.delete(cardId);
          }
          result.success(null);
        } catch (_e) {
          result.success(null);
        }
        break;
      }
      default:
        result.notImplemented();
    }
  }
}
