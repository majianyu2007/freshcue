// Form Kit bridge: persists redacted card snapshots and refreshes running forms.
// Channel: freshcue/forms.
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import common from '@ohos.app.ability.common';
import { CapabilityRegistry } from './CapabilitiesPlugin';

const STORE_NAME = 'freshcue_form';
const STORE_KEY = 'data';
const FORM_NAME = 'freshcue_cards';
const MAX_CARDS = 3;

export class FormPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;

  getUniqueClassName(): string {
    return 'FormPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/forms');
    this.channel.setMethodCallHandler(this);
    CapabilityRegistry.mark('forms', true, true, '');
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'updateCards') {
      this.updateCards(call, result);
      return;
    }
    result.notImplemented();
  }

  private async updateCards(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.context === null) {
      result.error('form_update_failed', 'context unavailable', null);
      return;
    }
    try {
      const rawCards = call.argument('cards') as Array<Map<string, Object>>;
      const data = this.flatten(rawCards ?? []);
      const store = preferences.getPreferencesSync(this.context, { name: STORE_NAME });
      store.putSync(STORE_KEY, JSON.stringify(data));
      store.flushSync();

      const forms = await formProvider.getPublishedRunningFormInfos();
      const binding = formBindingData.createFormBindingData(data);
      for (const form of forms) {
        if (form.formName === FORM_NAME) {
          await formProvider.updateForm(form.formId, binding);
        }
      }
      result.success(null);
    } catch (_e) {
      result.error('form_update_failed', 'unable to refresh forms', null);
    }
  }

  // StandardMessageCodec 的 MAP 分支固定解码为 Map；不能用 instanceof
  // 判断，因为跨 ArkTS 模块边界时会返回 false。
  private static readString(card: Map<string, Object>, key: string): string {
    const value = card.get(key);
    return typeof value === 'string' ? value as string : '';
  }

  private static readBool(card: Map<string, Object>, key: string): boolean {
    return card.get(key) === true;
  }

  private flatten(cards: Array<Map<string, Object>>): Record<string, Object> {
    const count = Math.min(cards.length, MAX_CARDS);
    const data: Record<string, Object> = { 'count': count };
    for (let index = 0; index < MAX_CARDS; index++) {
      let id = '';
      let title = '';
      let timeLabel = '';
      let urgent = false;
      if (index < count) {
        const card = cards[index];
        id = FormPlugin.readString(card, 'id');
        title = FormPlugin.readString(card, 'title');
        timeLabel = FormPlugin.readString(card, 'timeLabel');
        urgent = FormPlugin.readBool(card, 'urgent');
      }
      data[`card${index}Title`] = title;
      data[`card${index}Time`] = timeLabel;
      data[`card${index}Urgent`] = urgent;
      data[`card${index}Uri`] = id.length === 0 ? 'freshcue://home' : `freshcue://card/${id}`;
    }
    return data;
  }
}
