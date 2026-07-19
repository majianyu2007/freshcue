
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { CapabilitiesPlugin, CapabilityRegistry } from '../plugins/CapabilitiesPlugin';
import { OcrPlugin } from '../plugins/OcrPlugin';
import { SharePlugin } from '../plugins/SharePlugin';
import { ReminderPlugin } from '../plugins/ReminderPlugin';
import { FormPlugin } from '../plugins/FormPlugin';
import { CalendarPlugin } from '../plugins/CalendarPlugin';

export default class EntryAbility extends FlutterAbility {
  private sharePlugin: SharePlugin = new SharePlugin();
  private reminderPlugin: ReminderPlugin = new ReminderPlugin();
  private calendarPlugin: CalendarPlugin = new CalendarPlugin();

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new CapabilitiesPlugin())
    flutterEngine.getPlugins()?.add(new OcrPlugin())
    this.sharePlugin.setAbilityContext(this.context)
    flutterEngine.getPlugins()?.add(this.sharePlugin)
    this.reminderPlugin.setAbilityContext(this.context)
    flutterEngine.getPlugins()?.add(this.reminderPlugin)
    this.calendarPlugin.setAbilityContext(this.context)
    flutterEngine.getPlugins()?.add(this.calendarPlugin)
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
    // 长按图标快捷方式：parameters 里带 freshcue_shortcut（camera/gallery）。
    const params = want.parameters
    const shortcut = params === undefined ? undefined : params['freshcue_shortcut']
    if (typeof shortcut === 'string' && shortcut.length > 0) {
      this.reminderPlugin.emitRoute(`freshcue://import/${shortcut}`)
      return
    }
    // 服务卡片的 router action 会把目标 URI 放在 parameters 中；
    // 同时保留 want.uri 兼容系统直接分发深链。
    const formRoute = params === undefined ? undefined : params['freshcue_route']
    if (typeof formRoute === 'string' && formRoute.startsWith('freshcue://')) {
      this.reminderPlugin.emitRoute(formRoute)
      return
    }
    const uri: string = want.uri ?? ''
    // 通知点击深链：freshcue://card/<id> → 打开卡片。
    if (uri.startsWith('freshcue://card/')) {
      const cardId = uri.substring('freshcue://card/'.length)
      this.reminderPlugin.emitOpened(cardId)
      return
    }
    // 其余 freshcue 深链（服务卡片点击等）交给 Flutter 路由统一解析。
    if (uri.startsWith('freshcue://')) {
      this.reminderPlugin.emitRoute(uri)
      return
    }
    // 其余按系统分享接收处理。
    this.sharePlugin.handleWant(want, isColdStart)
  }
}
