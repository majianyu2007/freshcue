// ⚠️ 参考实现，未真机验证（见 ohos/README.md）。
// EntryAbility：注册 4 个桥接插件，处理冷/热启动 Want（分享、通知深链）。

import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import window from '@ohos.window';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { OcrPlugin } from '../plugins/OcrPlugin';
import { SharePlugin } from '../plugins/SharePlugin';
import { ReminderPlugin } from '../plugins/ReminderPlugin';
import { LiveViewPlugin } from '../plugins/LiveViewPlugin';

export default class EntryAbility extends FlutterAbility {
  private sharePlugin = new SharePlugin();
  private reminderPlugin = new ReminderPlugin();

  configureFlutterEngine(engine: FlutterEngine): void {
    super.configureFlutterEngine(engine);
    new OcrPlugin().register(engine);
    this.sharePlugin.register(engine);
    this.reminderPlugin.register(engine);
    new LiveViewPlugin().register(engine);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    this.dispatchWant(want, true); // 冷启动
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    this.dispatchWant(want, false); // 热启动
  }

  private dispatchWant(want: Want, cold: boolean): void {
    const uri = want.uri ?? '';
    // 通知行为深链：freshcue://action/<action>/<cardId>/<instanceId>
    if (uri.startsWith('freshcue://action/')) {
      const parts = uri.substring('freshcue://action/'.length).split('/');
      if (parts.length === 3) {
        this.reminderPlugin.emitAction(parts[0], parts[1], parts[2]);
      }
      return;
    }
    // 通知点击深链：freshcue://card/<id> —— 交给 Flutter 路由（opened 事件）。
    if (uri.startsWith('freshcue://card/')) {
      const cardId = uri.substring('freshcue://card/'.length);
      this.reminderPlugin.emitAction('opened', cardId, '');
      return;
    }
    // 分享接收。
    this.sharePlugin.handleWant(want, cold);
  }
}
