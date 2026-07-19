import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../domain/enums/enums.dart';
import '../review/review_page.dart';

/// 导入流程入口：选择来源 → 处理页 → 确认页。
Future<void> startImportFlow(
  BuildContext context,
  AppController controller, {
  String? initialChoice,
}) async {
  final choice =
      initialChoice ??
      await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: const Text('拍一张'),
                subtitle: const Text('打开系统相机，拍下含有时间的信息'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从图库选择'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('体验真实中文截图'),
                subtitle: const Text('取件、票务、活动通知，走完整离线 OCR'),
                onTap: () => Navigator.pop(context, 'samples'),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_alt_outlined),
                title: const Text('手动粘贴文字'),
                subtitle: const Text('OCR 不可用或识别失败时的降级方式'),
                onTap: () => Navigator.pop(context, 'manual'),
              ),
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('演示样例'),
                subtitle: const Text('合成的活动通知截图，不含个人信息'),
                onTap: () => Navigator.pop(context, 'demo'),
              ),
            ],
          ),
        ),
      );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'camera':
      final item = await controller.share.capturePhoto();
      if (item == null || !context.mounted) return;
      final ok = await controller.importFromBytes(
        item.bytes,
        source: ImportSource.camera,
        displayName: item.displayName,
      );
      if (ok && context.mounted) await openDraftReview(context, controller);
    case 'gallery':
      final item = await controller.share.pickImage();
      if (item == null) {
        if (context.mounted && controller.usingMockPlatform) {
          // Mock 环境无图库桥接：引导用演示样例。
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前为模拟能力模式，图库不可用，已使用演示样例')),
          );
          await controller.importDemo();
          if (context.mounted) await openDraftReview(context, controller);
        }
        return;
      }
      if (item.extraCount > 0 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入第一张，其余 ${item.extraCount} 张未导入')),
        );
      }
      final ok = await controller.importFromBytes(
        item.bytes,
        source: ImportSource.gallery,
        displayName: item.displayName,
      );
      if (ok && context.mounted) await openDraftReview(context, controller);
    case 'samples':
      final sample = await _chooseSample(context);
      if (sample == null || !context.mounted) return;
      final data = await rootBundle.load(sample.$1);
      final ok = await controller.importFromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        source: ImportSource.gallery,
        displayName: sample.$2,
      );
      if (ok && context.mounted) await openDraftReview(context, controller);
    case 'manual':
      if (context.mounted) await _manualInput(context, controller);
    case 'demo':
      await controller.importDemo();
      if (context.mounted) await openDraftReview(context, controller);
  }
}

Future<(String, String)?> _chooseSample(BuildContext context) =>
    showDialog<(String, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择一张中文截图'),
        children: [
          for (final sample in const [
            ('assets/samples/parcel_pickup.png', '快递取件通知', '识别取件码与免费保管截止时间'),
            ('assets/samples/concert_ticket.png', '音乐会电子票', '识别入场与演出两个时间角色'),
            ('assets/samples/registration_notice.png', '活动报名通知', '识别报名截止与活动时间'),
          ])
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, (sample.$1, '${sample.$2}.png')),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      sample.$1,
                      width: 56,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sample.$2,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sample.$3,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

Future<void> _manualInput(
  BuildContext context,
  AppController controller,
) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) {
      final ctl = TextEditingController();
      return AlertDialog(
        title: const Text('粘贴或输入文字'),
        content: TextField(
          controller: ctl,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：报名截止7月20日 18:00\n活动时间7月25日 14:00',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text),
            child: const Text('解析'),
          ),
        ],
      );
    },
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  controller.importManualText(text);
  await openDraftReview(context, controller);
}

/// 打开确认页（草稿已就绪时）。
Future<void> openDraftReview(
  BuildContext context,
  AppController controller,
) async {
  if (controller.pendingDraft == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ReviewPage(controller: controller),
    ),
  );
}

/// 处理页：分阶段进度（不伪造百分比）。
class ProcessingView extends StatelessWidget {
  const ProcessingView({super.key, required this.stage, this.onCancel});

  final ImportStage stage;
  final VoidCallback? onCancel;

  static const _labels = {
    ImportStage.reading: '正在读取图片',
    ImportStage.recognizing: '正在识别文字',
    ImportStage.analyzing: '正在分析时间',
    ImportStage.preparing: '正在准备确认',
  };

  @override
  Widget build(BuildContext context) {
    final steps = _labels.keys.toList();
    final currentIdx = steps.indexOf(stage);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    i < currentIdx
                        ? Icons.check_circle
                        : (i == currentIdx
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off),
                    size: 18,
                    color: i <= currentIdx
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor,
                  ),
                  const SizedBox(width: 8),
                  Text(_labels[steps[i]]!),
                ],
              ),
            ),
          if (onCancel != null) ...[
            const SizedBox(height: 24),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ],
      ),
    );
  }
}
