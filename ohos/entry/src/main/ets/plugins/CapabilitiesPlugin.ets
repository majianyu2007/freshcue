// 统一能力握手通道：freshcue/capabilities
// 每个 Kit 插件编译接入后在 EntryAbility 中登记 compiled 状态；
// available 由各插件的运行时检查决定，reason 用稳定机器码。
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import deviceInfo from '@ohos.deviceInfo';

export interface KitStatus {
  compiled: boolean;
  available: boolean;
  reason: string;
  provider: string;
}

export class CapabilityRegistry {
  static readonly kits = new Map<string, KitStatus>();

  static mark(
    name: string,
    compiled: boolean,
    available: boolean,
    reason: string,
    provider: string = '',
  ): void {
    CapabilityRegistry.kits.set(name, {
      compiled: compiled,
      available: available,
      reason: reason,
      provider: provider,
    });
  }
}

export class CapabilitiesPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private filesDir: string = '';

  getUniqueClassName(): string {
    return 'CapabilitiesPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.filesDir = binding.getApplicationContext().filesDir;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/capabilities');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'ping':
        result.success('pong');
        break;
      case 'getCapabilities': {
        const kits: Record<string, Object> = {};
        CapabilityRegistry.kits.forEach((status, name) => {
          kits[name] = {
            'compiled': status.compiled,
            'available': status.available,
            'reason': status.reason,
            'provider': status.provider,
          } as Record<string, Object>;
        });
        const payload: Record<string, Object> = {
          'platform': 'ohos',
          'apiVersion': deviceInfo.sdkApiVersion,
          'bridgeVersion': 1,
          'filesDir': this.filesDir,
          'kits': kits,
        };
        result.success(payload);
        break;
      }
      default:
        result.notImplemented();
    }
  }
}
