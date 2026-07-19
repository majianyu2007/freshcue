
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { CapabilitiesPlugin, CapabilityRegistry } from '../plugins/CapabilitiesPlugin';
import { OcrPlugin } from '../plugins/OcrPlugin';
import { SharePlugin } from '../plugins/SharePlugin';
import { ReminderPlugin } from '../plugins/ReminderPlugin';
import { FormPlugin } from '../plugins/FormPlugin';

export default class EntryAbility extends FlutterAbility {
  private sharePlugin: SharePlugin = new SharePlugin();
  private reminderPlugin: ReminderPlugin = new ReminderPlugin();

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new CapabilitiesPlugin())
    flutterEngine.getPlugins()?.add(new OcrPlugin())
    this.sharePlugin.setAbilityContext(this.context)
    flutterEngine.getPlugins()?.add(this.sharePlugin)
    flutterEngine.getPlugins()?.add(this.reminderPlugin)
    flutterEngine.getPlugins()?.add(new FormPlugin())
    // 冷启动：引擎就绪后用启动 Want 尝试分发（分享内容或通知深链）。
    this.dispatchWant(this.getWant(), true)
    CapabilityRegistry.mark('database', true, true, '')
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParams)
    this.dispatchWant(want, false)
  }

  private dispatchWant(want: Want | undefined, isColdStart: boolean): void {
    if (want === undefined) {
      return
    }
    const uri: string = want.uri ?? ''
    // 通知点击深链：freshcue://card/<id> → 打开卡片。
    if (uri.startsWith('freshcue://card/')) {
      const cardId = uri.substring('freshcue://card/'.length)
      this.reminderPlugin.emitOpened(cardId)
      return
    }
    // 其余按系统分享接收处理。
    this.sharePlugin.handleWant(want, isColdStart)
  }
}
