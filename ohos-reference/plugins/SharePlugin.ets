// ⚠️ 参考实现，未真机验证（见 ohos/README.md）。
// channel: freshcue/share —— 分享接收（冷/热启动）+ 图库选择。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-interface-description

import { systemShare } from '@kit.ShareKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import Want from '@ohos.app.ability.Want';
import {
  MethodCall, MethodChannel, MethodResult, EventChannel, EventSink, FlutterEngine,
} from '@ohos/flutter_ohos';

interface PendingShare {
  id: string;
  bytes: Uint8Array;
  displayName: string | null;
  extraCount: number;
}

export class SharePlugin {
  private pending: PendingShare | null = null;
  private consumedIds = new Set<string>();
  private sink: EventSink | null = null;

  register(engine: FlutterEngine): void {
    const messenger = engine.dartExecutor.getBinaryMessenger();
    new MethodChannel(messenger, 'freshcue/share').setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.onCall(call, result);
      },
    });
    new EventChannel(messenger, 'freshcue/share/events').setStreamHandler({
      onListen: (_args: Object, sink: EventSink) => { this.sink = sink; },
      onCancel: () => { this.sink = null; },
    });
  }

  /// EntryAbility onCreate（冷启动）/ onNewWant（热启动）调用。
  /// 收到 URI 后立即读取字节 —— 不长期依赖来源应用的临时授权。
  async handleWant(want: Want, isColdStart: boolean): Promise<void> {
    const uris = await this.extractImageUris(want);
    if (uris.length === 0) { return; }
    const item = await this.readUri(uris[0], uris.length - 1);
    if (item === null) { return; }
    if (this.consumedIds.has(item.id)) { return; } // 重复 intent 去重
    if (isColdStart || this.sink === null) {
      this.pending = item;
    } else {
      this.sink.success(this.toMap(item));
      this.consumedIds.add(item.id);
    }
  }

  private async extractImageUris(want: Want): Promise<string[]> {
    // Share Kit 拉起：从 want 中恢复 SharedData；仅接受图片，其他类型拒绝。
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();
      const uris: string[] = [];
      for (const r of records) {
        if (r.uri !== undefined && (r.utd?.startsWith('general.image') ?? false)) {
          uris.push(r.uri);
        }
      }
      return uris;
    } catch (_e) {
      return [];
    }
  }

  private async readUri(uri: string, extraCount: number): Promise<PendingShare | null> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      return {
        id: util.generateRandomUUID(),
        bytes: new Uint8Array(buf),
        displayName: uri.split('/').pop() ?? null,
        extraCount: extraCount,
      };
    } catch (_e) {
      return null; // uri_expired 场景：由 getInitialShare 返回空
    }
  }

  private toMap(item: PendingShare): Record<string, Object | null> {
    return {
      'id': item.id,
      'bytes': item.bytes,
      'displayName': item.displayName,
      'extraCount': item.extraCount,
    };
  }

  private async onCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'getInitialShare':
        result.success(this.pending === null ? null : this.toMap(this.pending));
        break;
      case 'consumeInitialShare': {
        const id = call.argument('id') as string;
        this.consumedIds.add(id);
        if (this.pending?.id === id) { this.pending = null; }
        result.success(null);
        break;
      }
      case 'pickImage': {
        try {
          const picker = new photoAccessHelper.PhotoViewPicker();
          const res = await picker.select({
            MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
            maxSelectNumber: 1,
          });
          if (res.photoUris.length === 0) {
            result.error('cancelled', 'user cancelled', null);
            break;
          }
          const item = await this.readUri(res.photoUris[0], 0);
          if (item === null) {
            result.error('uri_expired', 'read failed', null);
            break;
          }
          result.success(this.toMap(item));
        } catch (e) {
          result.error('invalid_image', `${(e as Error).name}`, null);
        }
        break;
      }
      default:
        result.notImplemented();
    }
  }
}
