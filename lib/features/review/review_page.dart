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
import '../../domain/parser/screenshot_parser.dart';
import '../../domain/services/reminder_policy.dart';

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
  late Set<int> selectedDraftIndexes;
  late DeliveryMode deliveryMode;
  bool _showReminderDetails = false;

  @override
  void initState() {
    super.initState();
    ctx = widget.controller.pendingDraft!;
    titleCtl = TextEditingController(text: ctx.draft.title);
    locationCtl = TextEditingController(text: ctx.draft.location ?? '');
    secretCtl = TextEditingController(text: ctx.draft.secretValue ?? '');
    category = ctx.draft.category;
    anchors = Map.of(ctx.draft.suggestedAnchors);
    selectedDraftIndexes = {for (var i = 0; i < ctx.drafts.length; i++) i};
    deliveryMode = widget.controller.defaultDeliveryMode;
    if (deliveryMode == DeliveryMode.systemCalendar &&
        anchors[TemporalRole.eventStart] == null &&
        anchors[TemporalRole.deadline] == null &&
        anchors[TemporalRole.expiry] == null) {
      deliveryMode = DeliveryMode.appReminder;
    }
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
    final expansion = widget.controller.reminderPolicy.expand(
      _previewCard,
      _plans,
      widget.controller.clock.now(),
      IdGen.newId,
    );
    final calendarAnchor =
        _previewCard.eventStartAt ??
        _previewCard.deadlineAt ??
        _previewCard.expiresAt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认内容'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    widget.controller.cancelImport();
                    Navigator.pop(context);
                  },
            child: const Text('取消'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_saveLabel()),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (ctx.duplicateOfCardId != null)
            _Notice(
              icon: Icons.copy_all_outlined,
              text: '这张图之前导入过，保存后会多一张卡片。',
              color: AppTheme.upcomingColor,
            ),
          if (widget.controller.importFailure != null)
            _Notice(
              icon: Icons.edit_note_outlined,
              text: '这次没认全，你可以直接修改下面的内容。',
              color: AppTheme.upcomingColor,
            ),
          if (ctx.draft.highRisk)
            _Notice(
              icon: Icons.warning_amber_outlined,
              text: '图中可能有证件号或银行卡号，保存前请仔细检查。',
              color: AppTheme.urgentColor,
            ),
          if (ctx.drafts.length > 1) ...[
            _SectionTitle(
              title: '这张图里有 ${ctx.drafts.length} 条信息',
              subtitle: '只保留你需要的',
            ),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < ctx.drafts.length; i++)
                    CheckboxListTile(
                      value: selectedDraftIndexes.contains(i),
                      title: Text(ctx.drafts[i].title),
                      subtitle: Text(
                        i == 0 ? '当前正在编辑' : _draftSummary(ctx.drafts[i]),
                      ),
                      onChanged: (selected) => setState(() {
                        if (selected == true) {
                          selectedDraftIndexes.add(i);
                        } else {
                          selectedDraftIndexes.remove(i);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _EvidenceImage(
            asset: ctx.asset,
            blocks: ctx.blocks,
            highlightBlockIds: _highlightIds(),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: '卡片内容', subtitle: '有误的地方直接改'),
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
            decoration: const InputDecoration(
              labelText: '分类',
              border: OutlineInputBorder(),
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
              labelText: '地点（可不填）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: secretCtl,
            decoration: const InputDecoration(
              labelText: '取件码、入场码等（可不填）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '时间', subtitle: '点一下即可修改'),
          ..._buildCandidateGroups(),
          _AddAnchorButton(
            existing: anchors.keys.toSet(),
            onAdd: (role) => _pickDateTime(role),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '保存后怎么提醒', subtitle: '两种方式不会同时开启'),
          _DeliveryPicker(
            value: deliveryMode,
            calendarEnabled: calendarAnchor != null,
            onChanged: (value) => setState(() => deliveryMode = value),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: deliveryMode == DeliveryMode.appReminder
                  ? _appReminderSummary(expansion)
                  : _calendarSummary(calendarAnchor),
            ),
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('识别说明'),
            subtitle: const Text('需要时再查看原文和判断依据'),
            children: [
              ListTile(
                title: const Text('文字识别'),
                trailing: Text(ctx.ocrProvider.label),
              ),
              ListTile(
                title: const Text('分类依据'),
                subtitle: Text(ctx.draft.categoryExplanation),
              ),
              for (final warning in ctx.draft.warnings)
                ListTile(
                  leading: const Icon(Icons.info_outline, size: 18),
                  title: Text(warning),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _saveLabel() {
    if (ctx.drafts.length > 1) {
      return '保存 ${selectedDraftIndexes.length} 张卡片';
    }
    return deliveryMode == DeliveryMode.systemCalendar ? '保存并加入系统日程' : '保存卡片';
  }

  Widget _appReminderSummary(ExpansionResult expansion) {
    if (expansion.instances.isEmpty) {
      return const Row(
        children: [
          Icon(Icons.notifications_off_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('没有可提醒的未来时间')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.notifications_active_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '截期会提醒 ${expansion.instances.length} 次，最近一次是 '
                '${formatShort(expansion.instances.first.triggerAt)}',
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () =>
              setState(() => _showReminderDetails = !_showReminderDetails),
          child: Text(_showReminderDetails ? '收起时间' : '查看全部时间'),
        ),
        if (_showReminderDetails) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final instance in expansion.instances)
                Chip(label: Text(formatShort(instance.triggerAt))),
            ],
          ),
          for (final note in expansion.notes)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(note, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ],
    );
  }

  Widget _calendarSummary(DateTime? anchor) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.calendar_month_outlined),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          anchor == null
              ? '先添加一个未来时间，才能加入系统日程'
              : '将在 ${formatDateTime(anchor)} 创建日程。'
                    '首次使用时系统会询问日历权限。',
        ),
      ),
    ],
  );

  String _draftSummary(ParsedDraft draft) {
    final anchors = draft.suggestedAnchors;
    if (anchors.isEmpty) return draft.category.label;
    final first = anchors.entries.first;
    return '${draft.category.label} · ${first.key.label} ${formatDateTime(first.value)}';
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
            subtitle: cand.requiresConfirmation
                ? const Text('日期可能有偏差，请点击核对')
                : cand.role == TemporalRole.publishTime
                ? const Text('仅作参考，不用于提醒')
                : null,
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
    if (selectedDraftIndexes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少保留一条信息')));
      return;
    }
    if (selectedDraftIndexes.contains(0) && titleCtl.text.trim().isEmpty) {
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
        includePrimary: selectedDraftIndexes.contains(0),
        additionalDraftIndexes: selectedDraftIndexes
            .where((i) => i > 0)
            .toSet(),
        deliveryMode: deliveryMode,
      );
      if (!mounted) return;
      final msg = failures.permissionDenied
          ? failures.mode == DeliveryMode.systemCalendar
                ? '卡片已保存；允许日历权限后可再加入系统日程'
                : '卡片已保存；开启通知后才能收到提醒'
          : failures.failures > 0
          ? failures.mode == DeliveryMode.systemCalendar
                ? '卡片已保存，但日程还没有写入，可以稍后重试'
                : '卡片已保存，部分提醒需要稍后重试'
          : failures.mode == DeliveryMode.systemCalendar
          ? '已保存并加入系统日程'
          : '已保存';
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _DeliveryPicker extends StatelessWidget {
  const _DeliveryPicker({
    required this.value,
    required this.calendarEnabled,
    required this.onChanged,
  });

  final DeliveryMode value;
  final bool calendarEnabled;
  final ValueChanged<DeliveryMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _DeliveryOption(
          icon: Icons.notifications_active_outlined,
          title: '截期提醒',
          subtitle: '在应用里管理',
          selected: value == DeliveryMode.appReminder,
          onTap: () => onChanged(DeliveryMode.appReminder),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _DeliveryOption(
          icon: Icons.calendar_month_outlined,
          title: '系统日程',
          subtitle: calendarEnabled ? '在日历里管理' : '需要先设时间',
          selected: value == DeliveryMode.systemCalendar,
          enabled: calendarEnabled,
          onTap: () => onChanged(DeliveryMode.systemCalendar),
        ),
      ),
    ],
  );
}

class _DeliveryOption extends StatelessWidget {
  const _DeliveryOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = enabled
        ? selected
              ? colors.onPrimaryContainer
              : colors.onSurface
        : colors.onSurface.withValues(alpha: 0.38);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: foreground),
                  const Spacer(),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 19,
                    color: foreground,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ],
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
