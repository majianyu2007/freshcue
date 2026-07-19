// Calendar Kit 桥接。只有用户选择“系统日程”时才申请读写日历权限。
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CapabilityRegistry } from './CapabilitiesPlugin';

const CALENDAR_ACCOUNT: calendarManager.CalendarAccount = {
  name: 'freshcue',
  type: calendarManager.CalendarType.LOCAL,
  displayName: '截期',
};

export class CalendarPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private abilityContext: common.UIAbilityContext | null = null;
  private calendar: calendarManager.Calendar | null = null;

  setAbilityContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  getUniqueClassName(): string {
    return 'CalendarPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/calendar');
    this.channel.setMethodCallHandler(this);
    const available = canIUse('SystemCapability.Applications.CalendarData');
    CapabilityRegistry.mark(
      'calendar',
      true,
      available,
      available ? '' : 'device_unsupported',
    );
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.calendar = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isAvailable':
        result.success(canIUse('SystemCapability.Applications.CalendarData'));
        break;
      case 'requestPermission':
        this.requestPermission(result);
        break;
      case 'createEvent':
        this.createEvent(call, result);
        break;
      case 'updateEvent':
        this.updateEvent(call, result);
        break;
      case 'deleteEvent':
        this.deleteEvent(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  private async requestPermission(result: MethodResult): Promise<void> {
    if (this.abilityContext === null) {
      result.error('calendar_unavailable', 'ability_context_missing', null);
      return;
    }
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = [
        'ohos.permission.READ_CALENDAR',
        'ohos.permission.WRITE_CALENDAR',
      ];
      const response = await manager.requestPermissionsFromUser(
        this.abilityContext,
        permissions,
      );
      result.success(
        response.authResults.length === permissions.length &&
        response.authResults.every((status: number) => status === 0),
      );
    } catch (_e) {
      result.success(false);
    }
  }

  private async getCalendar(): Promise<calendarManager.Calendar> {
    if (this.calendar !== null) {
      return this.calendar;
    }
    if (this.abilityContext === null) {
      throw new Error('ability_context_missing');
    }
    const manager = calendarManager.getCalendarManager(this.abilityContext);
    try {
      this.calendar = await manager.getCalendar(CALENDAR_ACCOUNT);
    } catch (e) {
      const error = e as BusinessError;
      if (error.code !== 23900003) {
        throw new Error(`calendar_lookup_failed_${error.code ?? 0}`);
      }
      this.calendar = await manager.createCalendar(CALENDAR_ACCOUNT);
    }
    return this.calendar;
  }

  private eventFromCall(call: MethodCall): calendarManager.Event {
    const startAtMs = call.argument('startAtMs') as number;
    const endAtMs = call.argument('endAtMs') as number;
    const location = call.argument('location') as string | null;
    return {
      type: calendarManager.EventType.NORMAL,
      title: call.argument('title') as string,
      startTime: startAtMs,
      endTime: endAtMs,
      description: call.argument('description') as string | undefined,
      location: location === null ? undefined : { location: location },
      reminderTime: call.argument('reminderMinutes') as Array<number>,
      identifier: `freshcue-${call.argument('cardId') as string}`,
    };
  }

  private async createEvent(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getCalendar();
      result.success(await calendar.addEvent(this.eventFromCall(call)));
    } catch (e) {
      this.reportError(result, e);
    }
  }

  private async updateEvent(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getCalendar();
      const event = this.eventFromCall(call);
      event.id = call.argument('eventId') as number;
      await calendar.updateEvent(event);
      result.success(null);
    } catch (e) {
      this.reportError(result, e);
    }
  }

  private async deleteEvent(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getCalendar();
      await calendar.deleteEvent(call.argument('eventId') as number);
      result.success(null);
    } catch (e) {
      this.reportError(result, e);
    }
  }

  private reportError(result: MethodResult, e: Object): void {
    const error = e as BusinessError;
    const code = error.code === 201
      ? 'calendar_permission_denied'
      : 'calendar_failed';
    result.error(code, `code=${error.code ?? 0}`, null);
  }
}
