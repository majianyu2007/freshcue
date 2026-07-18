
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { CapabilitiesPlugin, CapabilityRegistry } from '../plugins/CapabilitiesPlugin';
import { OcrPlugin } from '../plugins/OcrPlugin';
import { SharePlugin } from '../plugins/SharePlugin';

export default class EntryAbility extends FlutterAbility {
  private sharePlugin: SharePlugin = new SharePlugin();

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new CapabilitiesPlugin())
    flutterEngine.getPlugins()?.add(new OcrPlugin())
    flutterEngine.getPlugins()?.add(this.sharePlugin)
    // 冷启动分享：引擎就绪后用启动 Want 尝试还原分享内容。
    this.sharePlugin.handleWant(this.getWant(), true)
    // 尚未编译接入的 Kit 如实登记。
    CapabilityRegistry.mark('reminders', false, false, 'not_compiled')
    CapabilityRegistry.mark('liveView', false, false, 'feature_disabled')
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParams)
    // 热启动分享：应用已在运行时收到第二张图片。
    this.sharePlugin.handleWant(want, false)
  }
}
