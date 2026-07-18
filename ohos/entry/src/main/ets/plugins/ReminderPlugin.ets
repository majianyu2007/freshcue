// 代理提醒桥接。channel: freshcue/reminders (+ events)
// 依据本机 SDK @ohos.reminderAgentManager (API 24)：
//  - publishReminder(ReminderRequestCalendar): Promise<number> 返回 reminderId
//  - 提醒即使进程被终止仍按时触发（代理提醒核心价值）
//  - wantAgent(uri=freshcue://card/<id>) → 点击通知拉起 EntryAbility 打开卡片
//  诚实说明：本 SDK 的 ActionButtonType 仅有 CLOSE / SNOOZE，无自定义按钮类型，
//  因此“完成/延后”不做成通知自定义按钮，而是点击通知进入卡片后在应用内操作。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  EventChannel,
  EventSink,
  StreamHandler,
  MethodResult,
} from '@ohos/flutter_ohos';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { CapabilityRegistry } from './CapabilitiesPlugin';

const BUNDLE = 'com.freshcue.app';

export class ReminderPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private sink: EventSink | null = null;
  // 冷启动期间收到的通知点击先入队，Flutter 订阅后一次性补发（去重）。
  private queued: Array<Record<string, string>> = [];
  private readonly delivered = new Set<string>();

  getUniqueClassName(): string {
    return 'ReminderPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/reminders');
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'freshcue/reminders/events');
    this.eventChannel.setStreamHandler(this);
    const available = canIUse('SystemCapability.Notification.ReminderAgent');
    CapabilityRegistry.mark('reminders', true, available,
      available ? '' : 'device_unsupported');
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = null;
  }

  onListen(_args: ESObject, events: EventSink): void {
    this.sink = events;
    for (const a of this.queued) {
      events.success(a);
    }
    this.queued = [];
  }

  onCancel(_args: ESObject): void {
    this.sink = null;
  }

  /// EntryAbility 收到 freshcue://card/<id> 深链时调用（通知点击）。
  emitOpened(cardId: string): void {
    const key = `opened:${cardId}`;
    if (this.delivered.has(key)) {
      return; // 同一次点击只投递一次
    }
    this.delivered.add(key);
    const payload: Record<string, string> = {
      'action': 'opened',
      'cardId': cardId,
      'instanceId': '',
    };
    if (this.sink !== null) {
      this.sink.success(payload);
    } else {
      this.queued.push(payload);
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isAvailable':
        result.success(canIUse('SystemCapability.Notification.ReminderAgent'));
        break;
      case 'requestPermissionIfNeeded':
        this.requestPermission(result);
        break;
      case 'scheduleCalendarReminder':
        this.schedule(call, result);
        break;
      case 'cancelReminder':
        this.cancel(call, result);
        break;
      case 'getScheduledReminderIds':
        // 本 SDK 的 getValidReminders 返回项不含 reminderId，
        // 平台 ID 由数据库保存（publishReminder 返回值）。此处返回空表。
        result.success([]);
        break;
      default:
        result.notImplemented();
    }
  }

  private async requestPermission(result: MethodResult): Promise<void> {
    try {
      // PUBLISH_AGENT_REMINDER 为安装期授予；此处确保通知开关已开启。
      await notificationManager.requestEnableNotification();
      result.success(true);
    } catch (_e) {
      result.success(false);
    }
  }

  private async schedule(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const triggerAtMs = call.argument('triggerAtMs') as number;
      const cardId = call.argument('cardId') as string;
      const instanceId = call.argument('instanceId') as string;
      const title = call.argument('title') as string;
      const body = call.argument('body') as string;
      const sound = call.argument('sound') as boolean;
      const t = new Date(triggerAtMs);

      const reminder: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: t.getFullYear(),
          month: t.getMonth() + 1,
          day: t.getDate(),
          hour: t.getHours(),
          minute: t.getMinutes(),
          second: 0,
        },
        title: title,
        content: body,
        notificationId: ReminderPlugin.stableId(instanceId),
        ringDuration: sound ? 1 : 0,
        tapDismissed: true,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        // 点击通知 → 打开对应卡片（进程被杀后仍有效）。
        wantAgent: {
          pkgName: BUNDLE,
          abilityName: 'EntryAbility',
          uri: `freshcue://card/${cardId}`,
        },
      };
      const platformId = await reminderAgentManager.publishReminder(reminder);
      result.success(platformId);
    } catch (e) {
      const err = e as BusinessError;
      result.error('reminder_failed', `code=${err.code}`, null);
    }
  }

  private async cancel(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      await reminderAgentManager.cancelReminder(call.argument('id') as number);
      result.success(null);
    } catch (_e) {
      result.success(null); // 已不存在视为成功
    }
  }

  /// 字符串 → 稳定的 31-bit 正整数，用作 notificationId。
  private static stableId(s: string): number {
    let hash = 0;
    for (let i = 0; i < s.length; i++) {
      hash = (hash * 31 + s.charCodeAt(i)) | 0;
    }
    return Math.abs(hash);
  }
}
