// ⚠️ 参考实现，未真机验证（见 ohos/README.md）。
// channel: freshcue/reminders —— 桥接 @ohos.reminderAgentManager 代理提醒。
// 需要权限 ohos.permission.PUBLISH_AGENT_REMINDER（module.json5）。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder

import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import {
  MethodCall, MethodChannel, MethodResult, EventChannel, EventSink, FlutterEngine,
} from '@ohos/flutter_ohos';

export class ReminderPlugin {
  private sink: EventSink | null = null;
  // 冷启动期间收到的行为先入队，Flutter 订阅后一次性补发（每个行为只发一次）。
  private queuedActions: Array<Record<string, string>> = [];
  private deliveredKeys = new Set<string>();

  register(engine: FlutterEngine): void {
    const messenger = engine.dartExecutor.getBinaryMessenger();
    new MethodChannel(messenger, 'freshcue/reminders').setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.onCall(call, result);
      },
    });
    new EventChannel(messenger, 'freshcue/reminders/events').setStreamHandler({
      onListen: (_args: Object, sink: EventSink) => {
        this.sink = sink;
        for (const a of this.queuedActions) { sink.success(a); }
        this.queuedActions = [];
      },
      onCancel: () => { this.sink = null; },
    });
  }

  /// EntryAbility 从通知 Want 中解析出的行为（wantAgent uri 参数携带）。
  emitAction(action: string, cardId: string, instanceId: string): void {
    const key = `${action}:${instanceId}`;
    if (this.deliveredKeys.has(key)) { return; } // 同一行为只执行一次
    this.deliveredKeys.add(key);
    const payload: Record<string, string> = {
      'action': action, 'cardId': cardId, 'instanceId': instanceId,
    };
    if (this.sink !== null) { this.sink.success(payload); }
    else { this.queuedActions.push(payload); }
  }

  private async onCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'isAvailable':
        result.success(canIUse('SystemCapability.Notification.ReminderAgent'));
        break;
      case 'requestPermissionIfNeeded': {
        try {
          await notificationManager.requestEnableNotification();
          result.success(true);
        } catch (_e) {
          result.success(false);
        }
        break;
      }
      case 'scheduleCalendarReminder': {
        try {
          const triggerAtMs = call.argument('triggerAtMs') as number;
          const t = new Date(triggerAtMs);
          const cardId = call.argument('cardId') as string;
          const instanceId = call.argument('instanceId') as string;
          const reminder: reminderAgentManager.ReminderRequestCalendar = {
            reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
            dateTime: {
              year: t.getFullYear(), month: t.getMonth() + 1, day: t.getDate(),
              hour: t.getHours(), minute: t.getMinutes(), second: 0,
            },
            title: call.argument('title') as string,
            content: call.argument('body') as string,
            // 通知行为按钮：完成 / 延后（自定义按钮携带深链）。
            actionButton: [
              {
                title: '完成',
                type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CUSTOM,
                wantAgent: {
                  pkgName: 'com.freshcue.app',
                  abilityName: 'EntryAbility',
                  uri: `freshcue://action/complete/${cardId}/${instanceId}`,
                },
              },
              {
                title: '延后10分钟',
                type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CUSTOM,
                wantAgent: {
                  pkgName: 'com.freshcue.app',
                  abilityName: 'EntryAbility',
                  uri: `freshcue://action/snooze_10m/${cardId}/${instanceId}`,
                },
              },
            ],
            wantAgent: { // 点击通知 → 卡片详情
              pkgName: 'com.freshcue.app',
              abilityName: 'EntryAbility',
              uri: `freshcue://card/${cardId}`,
            },
            ringDuration: (call.argument('sound') as boolean) ? 5 : 0,
            // 锁屏隐藏内容：由通知子系统的锁屏可见性控制，敏感卡片正文已在
            // Flutter 侧遮罩（双保险）。
          };
          const platformId = await reminderAgentManager.publishReminder(reminder);
          result.success(platformId);
        } catch (e) {
          result.error('reminder_failed', `${(e as Error).name}`, null);
        }
        break;
      }
      case 'cancelReminder': {
        try {
          await reminderAgentManager.cancelReminder(call.argument('id') as number);
          result.success(null);
        } catch (_e) {
          result.success(null); // 已不存在视为成功
        }
        break;
      }
      case 'getScheduledReminderIds': {
        try {
          const all = await reminderAgentManager.getValidReminders();
          // API 23 起 getValidReminders 返回 ReminderInfo（含 reminderId）。
          const ids: number[] = [];
          for (const r of all) { ids.push((r as reminderAgentManager.ReminderInfo).reminderId); }
          result.success(ids);
        } catch (_e) {
          result.success([]);
        }
        break;
      }
      default:
        result.notImplemented();
    }
  }
}
