
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { CapabilitiesPlugin, CapabilityRegistry } from '../plugins/CapabilitiesPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new CapabilitiesPlugin())
    // 尚未编译接入的 Kit 如实登记（后续逐个替换）。
    CapabilityRegistry.mark('ocr', false, false, 'not_compiled')
    CapabilityRegistry.mark('share', false, false, 'not_compiled')
    CapabilityRegistry.mark('reminders', false, false, 'not_compiled')
    CapabilityRegistry.mark('liveView', false, false, 'feature_disabled')
  }
}
