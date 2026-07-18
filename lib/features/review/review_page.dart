import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/id_gen.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/entities/source_asset.dart';
import '../../domain/entities/temporal_card.dart';
import '../../domain/enums/enums.dart';
import '../../platform/gateways.dart';

/// 确认页：原图证据 + 高亮 + 字段编辑 + 提醒预览。
/// 用户确认前不创建任何正式提醒。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final DraftContext ctx;
  late TextEditingController titleCtl;
  late TextEditingController locationCtl;
  late TextEditingController secretCtl;
  late CardCategory category;

  /// 编辑中的锚点（角色 → 时间）。
  late Map<TemporalRole, DateTime> anchors;

  /// 当前选中候选（用于原图高亮）。
  String? highlightedCandidateId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ctx = widget.controller.pendingDraft!;
    titleCtl = TextEditingController(text: ctx.draft.title);
    locationCtl = TextEditingController(text: ctx.draft.location ?? '');
    secretCtl = TextEditingController(text: ctx.draft.secretValue ?? '');
    category = ctx.draft.category;
    anchors = Map.of(ctx.draft.suggestedAnchors);
  }

  @override
  void dispose() {
    titleCtl.dispose();
    locationCtl.dispose();
    secretCtl.dispose();
    super.dispose();
  }

  TemporalCard get _previewCard {
    final now = widget.controller.clock.now();
    return TemporalCard(
      id: 'preview',
      title: titleCtl.text,
      category: category,
      status: CardStatus.draft,
      eventStartAt: anchors[TemporalRole.eventStart],
      eventEndAt: anchors[TemporalRole.eventEnd],
      deadlineAt: anchors[TemporalRole.deadline],
      expiresAt: anchors[TemporalRole.expiry],
      isSensitive:
          secretCtl.text.isNotEmpty || category == CardCategory.temporarySecret,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<ReminderPlan> get _plans =>
      widget.controller.reminderPolicy.defaultPlans(_previewCard, IdGen.newId);

  @override
  Widget build(BuildContext context) {
    final now = widget.controller.clock.now();
    final expansion = widget.controller.reminderPolicy.expand(
      _previewCard,
      _plans,
      now,
      IdGen.newId,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认时效卡片'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    widget.controller.cancelImport();
                    Navigator.pop(context);
                  },
            child: const Text('放弃'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ctx.duplicateOfCardId != null)
            _Notice(
              icon: Icons.copy_all_outlined,
              text: '这张截图似乎已导入过，继续将创建一张新卡片。',
              color: AppTheme.upcomingColor,
            ),
          if (ctx.ocrProvider != OcrProvider.none)
            _Notice(
              icon: Icons.document_scanner_outlined,
              text: '识别来源：${ctx.ocrProvider.label}',
              color: Theme.of(context).colorScheme.primary,
            ),
          if (widget.controller.importFailure != null)
            _Notice(
              icon: Icons.edit_note_outlined,
              text: '自动识别失败，原图已保留。请手动填写标题和关键时间。',
              color: AppTheme.upcomingColor,
            ),
          if (ctx.draft.highRisk)
            _Notice(
              icon: Icons.warning_amber_outlined,
              text: '检测到疑似证件号/银行卡号，不建议保存此类信息。',
              color: AppTheme.urgentColor,
            ),
          for (final w in ctx.draft.warnings.where((w) => !w.contains('不建议保存')))
            _Notice(
              icon: Icons.info_outline,
              text: w,
              color: Theme.of(context).colorScheme.primary,
            ),
          _EvidenceImage(
            asset: ctx.asset,
            blocks: ctx.blocks,
            highlightBlockIds: _highlightIds(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: titleCtl,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CardCategory>(
            initialValue: category,
            decoration: InputDecoration(
              labelText: '分类（${ctx.draft.categoryExplanation}）',
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final c in CardCategory.values)
                DropdownMenuItem(
                  value: c,
                  child: Row(
                    children: [
                      Icon(AppTheme.categoryIcon(c), size: 18),
                      const SizedBox(width: 8),
                      Text(c.label),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: locationCtl,
            decoration: const InputDecoration(
              labelText: '地点',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: secretCtl,
            decoration: const InputDecoration(
              labelText: '取件码/入场码（保存后默认遮罩）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text('关键时间', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._buildCandidateGroups(),
          _AddAnchorButton(
            existing: anchors.keys.toSet(),
            onAdd: (role) => _pickDateTime(role),
          ),
          const SizedBox(height: 20),
          Text('提醒计划', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (expansion.instances.isEmpty)
            const Text('当前设置不会创建提醒')
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final inst in expansion.instances)
                  Chip(label: Text(formatShort(inst.triggerAt))),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '保存后将创建 ${expansion.instances.length} 条系统提醒',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          for (final note in expansion.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '· $note',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.upcomingColor),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认并创建卡片'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Set<String> _highlightIds() {
    final c = ctx.draft.candidates
        .where((c) => c.id == highlightedCandidateId)
        .firstOrNull;
    return c?.evidenceBlockIds.toSet() ?? {};
  }

  List<Widget> _buildCandidateGroups() {
    final widgets = <Widget>[];
    // 按角色显示解析候选，可点击定位原图证据。
    for (final cand in ctx.draft.candidates) {
      final active =
          anchors[cand.role] == cand.normalizedDateTime ||
          (cand.role == TemporalRole.publishTime);
      widgets.add(
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            onTap: () => setState(() => highlightedCandidateId = cand.id),
            leading: Icon(
              cand.role == TemporalRole.publishTime
                  ? Icons.article_outlined
                  : Icons.access_time,
              color: cand.requiresConfirmation
                  ? AppTheme.upcomingColor
                  : Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              '${cand.role.label} · '
              '${cand.normalizedDateTime == null ? cand.rawText : formatDateTime(cand.normalizedDateTime!)}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('原文「${cand.rawText}」'),
                if (cand.explanation.isNotEmpty)
                  Text(
                    cand.explanation,
                    style: TextStyle(
                      color: AppTheme.upcomingColor,
                      fontSize: 12,
                    ),
                  ),
                if (cand.requiresConfirmation)
                  const Text(
                    '请确认',
                    style: TextStyle(
                      color: AppTheme.urgentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                if (cand.role == TemporalRole.publishTime)
                  const Text('发布时间不用于提醒', style: TextStyle(fontSize: 12)),
              ],
            ),
            trailing: cand.role == TemporalRole.publishTime
                ? null
                : IconButton(
                    icon: Icon(active ? Icons.check_box : Icons.edit_outlined),
                    tooltip: '修改时间',
                    onPressed: () => _pickDateTime(
                      cand.role,
                      initial: cand.normalizedDateTime,
                    ),
                  ),
          ),
        ),
      );
    }
    // 手动添加过、无候选来源的锚点。
    final candidateRoles = ctx.draft.candidates.map((c) => c.role).toSet();
    for (final e in anchors.entries) {
      if (candidateRoles.contains(e.key)) continue;
      widgets.add(
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.access_time),
            title: Text('${e.key.label} · ${formatDateTime(e.value)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => anchors.remove(e.key)),
            ),
            onTap: () => _pickDateTime(e.key, initial: e.value),
          ),
        ),
      );
    }
    return widgets;
  }

  Future<void> _pickDateTime(TemporalRole role, {DateTime? initial}) async {
    final now = widget.controller.clock.now();
    final base = initial ?? anchors[role] ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    setState(() {
      anchors[role] = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (titleCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写标题')));
      return;
    }
    setState(() => _saving = true);
    try {
      final (cardId, failures) = await widget.controller.confirmDraft(
        title: titleCtl.text.trim(),
        category: category,
        location: locationCtl.text.trim().isEmpty
            ? null
            : locationCtl.text.trim(),
        secretValue: secretCtl.text.trim().isEmpty
            ? null
            : secretCtl.text.trim(),
        anchors: anchors,
      );
      if (!mounted) return;
      final msg = switch (failures) {
        -1 => '卡片已保存，但通知权限未开启，提醒未启用',
        0 => '卡片已创建',
        _ => '卡片已保存，$failures 条提醒创建失败（可在详情页重试）',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context, cardId);
    } on AppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 原图证据视图（可缩放）+ OCR 高亮框。
class _EvidenceImage extends StatelessWidget {
  const _EvidenceImage({
    required this.asset,
    required this.blocks,
    required this.highlightBlockIds,
  });

  final SourceAsset? asset;
  final List<OcrBlock> blocks;
  final Set<String> highlightBlockIds;

  @override
  Widget build(BuildContext context) {
    final path = asset?.sandboxPath;
    if (path == null || !File(path).existsSync()) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text('无图片（手动输入模式）'),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 260,
        child: InteractiveViewer(
          maxScale: 5,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(path), fit: BoxFit.contain),
                // 高亮框基于归一化坐标铺在 contain 后的整个区域。
                for (final b in blocks)
                  if (highlightBlockIds.contains(b.id))
                    Positioned(
                      left: b.left * constraints.maxWidth,
                      top: b.top * constraints.maxHeight,
                      width: (b.right - b.left) * constraints.maxWidth,
                      height: (b.bottom - b.top) * constraints.maxHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}

class _AddAnchorButton extends StatelessWidget {
  const _AddAnchorButton({required this.existing, required this.onAdd});
  final Set<TemporalRole> existing;
  final void Function(TemporalRole) onAdd;

  @override
  Widget build(BuildContext context) {
    final available = [
      TemporalRole.deadline,
      TemporalRole.eventStart,
      TemporalRole.eventEnd,
      TemporalRole.expiry,
    ].where((r) => !existing.contains(r)).toList();
    if (available.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<TemporalRole>(
        itemBuilder: (context) => [
          for (final r in available)
            PopupMenuItem(value: r, child: Text(r.label)),
        ],
        onSelected: onAdd,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(Icons.add, size: 18), Text('添加时间')],
          ),
        ),
      ),
    );
  }
}
