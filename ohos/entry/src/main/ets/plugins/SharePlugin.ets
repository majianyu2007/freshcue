// 图片入口桥接。channel: freshcue/share (+ events)
// 两条入口，机制不同，文档如实区分：
//  1) 图库选择 pickImage —— photoAccessHelper.PhotoViewPicker（系统 Picker，免权限，前台可验证）。
//  2) 系统分享接收 —— 基于 UIAbility skills(action.sendData/UTD image) + Want，
//     由 systemShare.getSharedData(want) 还原 SharedRecord。收到 URI 立即读字节，
//     不长期依赖来源授权。这是 Want/Ability 级接收，非 ShareKit 发送 API。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-interface-description
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
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Want from '@ohos.app.ability.Want';
import util from '@ohos.util';
import { CapabilityRegistry } from './CapabilitiesPlugin';

interface PendingShare {
  id: string;
  bytes: Uint8Array;
  displayName: string | null;
  extraCount: number;
}

export class SharePlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private pending: PendingShare | null = null;
  private readonly consumedIds = new Set<string>();
  private abilityContext: common.UIAbilityContext | null = null;
  private preparedData: systemShare.SharedData | null = null;
  private readonly knockShareCallback =
    (target: harmonyShare.SharableTarget): void => { this.sharePrepared(target); };
  private readonly gesturesShareCallback =
    (target: harmonyShare.SharableTarget): void => { this.sharePrepared(target); };

  // 常见图片 UTD 叶子类型（general.image 的子类型）。
  private static readonly imageUtds = new Set<string>([
    'general.image', 'general.jpeg', 'general.png', 'general.heif',
    'general.heic', 'general.webp', 'general.bmp', 'general.gif',
    'general.tiff', 'general.svg', 'general.raw-image',
  ]);

  setAbilityContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  getUniqueClassName(): string {
    return 'SharePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/share');
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'freshcue/share/events');
    this.eventChannel.setStreamHandler(this);
    CapabilityRegistry.mark('share', true, true, '');
    if (canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      harmonyShare.on('knockShare', this.knockShareCallback);
      harmonyShare.on('gesturesShare', this.gesturesShareCallback);
      CapabilityRegistry.mark('harmonyShare', true, true, '');
    } else {
      CapabilityRegistry.mark('harmonyShare', true, false, 'device_unsupported');
    }
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    if (canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      harmonyShare.off('knockShare', this.knockShareCallback);
      harmonyShare.off('gesturesShare', this.gesturesShareCallback);
    }
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = null;
  }

  onListen(_args: ESObject, events: EventSink): void {
    this.sink = events;
  }

  onCancel(_args: ESObject): void {
    this.sink = null;
  }

  /// EntryAbility.onCreate(冷启动)/onNewWant(热启动) 调用。
  async handleWant(want: Want | undefined, isColdStart: boolean): Promise<void> {
    if (want === undefined) {
      return;
    }
    const item = await this.readFirstImage(want);
    if (item === null) {
      return;
    }
    if (this.consumedIds.has(item.id)) {
      return; // 重复 Want 去重
    }
    if (isColdStart || this.sink === null) {
      this.pending = item; // 等 Flutter getInitialShare 消费
    } else {
      this.sink.success(this.toMap(item));
      this.consumedIds.add(item.id);
    }
  }

  private async readFirstImage(want: Want): Promise<PendingShare | null> {
    let uris: Array<string> = [];
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();
      for (const r of records) {
        if (r.uri !== undefined && r.uri.length > 0 && SharePlugin.isImage(r.utd)) {
          uris.push(r.uri);
        }
      }
    } catch (_e) {
      return null; // 非分享 Want 或还原失败
    }
    if (uris.length === 0) {
      return null;
    }
    return this.readUri(uris[0], uris.length - 1);
  }

  private static isImage(utd: string): boolean {
    if (SharePlugin.imageUtds.has(utd)) {
      return true;
    }
    return utd.indexOf('image') >= 0;
  }

  private readUri(uri: string, extraCount: number): PendingShare | null {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return {
        id: util.generateRandomUUID(),
        bytes: new Uint8Array(buf),
        displayName: SharePlugin.baseName(uri),
        extraCount: extraCount,
      };
    } catch (_e) {
      return null; // uri 失效
    } finally {
      if (file !== null) {
        try { fs.closeSync(file); } catch (_e) { /* ignore */ }
      }
    }
  }

  private static baseName(uri: string): string {
    const parts = uri.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : uri;
  }

  private toMap(item: PendingShare): Record<string, Object | null> {
    return {
      'id': item.id,
      'bytes': item.bytes,
      'displayName': item.displayName,
      'extraCount': item.extraCount,
    };
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getInitialShare':
        result.success(this.pending === null ? null : this.toMap(this.pending));
        break;
      case 'consumeInitialShare': {
        const id = call.argument('id') as string;
        this.consumedIds.add(id);
        if (this.pending !== null && this.pending.id === id) {
          this.pending = null;
        }
        result.success(null);
        break;
      }
      case 'pickImage':
        this.pickImage(result);
        break;
      case 'capturePhoto':
        this.capturePhoto(result);
        break;
      case 'shareText':
        this.shareText(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  private async pickImage(result: MethodResult): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
      };
      const res = await picker.select(options);
      if (res.photoUris.length === 0) {
        result.error('cancelled', 'user cancelled', null);
        return;
      }
      const item = this.readUri(res.photoUris[0], 0);
      if (item === null) {
        result.error('uri_expired', 'read failed', null);
        return;
      }
      result.success(this.toMap(item));
    } catch (e) {
      const err = e as BusinessError;
      // 用户取消选择在部分实现下也会抛异常。
      result.error('cancelled', `code=${err.code}`, null);
    }
  }

  private async capturePhoto(result: MethodResult): Promise<void> {
    if (this.abilityContext === null) {
      result.error('camera_unavailable', 'ability context unavailable', null);
      return;
    }
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
      };
      const captured = await cameraPicker.pick(
        this.abilityContext,
        [cameraPicker.PickerMediaType.PHOTO],
        profile,
      );
      if (captured.resultCode !== 0 || captured.resultUri.length === 0) {
        result.error('cancelled', 'user cancelled', null);
        return;
      }
      const item = this.readUri(captured.resultUri, 0);
      if (item === null) {
        result.error('uri_expired', 'read failed', null);
        return;
      }
      item.displayName = '随手拍.jpg';
      result.success(this.toMap(item));
    } catch (e) {
      const err = e as BusinessError;
      result.error('camera_failed', `code=${err.code}`, null);
    }
  }

  private createTextData(title: string, text: string): systemShare.SharedData {
    return new systemShare.SharedData({
      utd: 'general.plain-text',
      title: title,
      content: text,
    });
  }

  private async shareText(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.abilityContext === null) {
      result.error('share_failed', 'ability context unavailable', null);
      return;
    }
    try {
      const title = call.argument('title') as string;
      const text = call.argument('text') as string;
      this.preparedData = this.createTextData(title, text);
      const controller = new systemShare.ShareController(this.preparedData);
      await controller.show(this.abilityContext, {});
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      result.error('share_failed', `code=${err.code}`, null);
    }
  }

  private async sharePrepared(target: harmonyShare.SharableTarget): Promise<void> {
    if (this.preparedData === null) {
      await target.clarifyNonShare({ message: '请先在截期中打开并分享一张卡片' });
      return;
    }
    await target.share(this.preparedData);
  }
}
