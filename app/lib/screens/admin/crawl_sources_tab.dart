import 'package:flutter/material.dart';
import '../../models/crawl_source.dart';

// ── Source card widget ───────────────────────────────────────────────────────

class SourceCard extends StatelessWidget {
  const SourceCard({
    super.key,
    required this.source,
    required this.toggling,
    required this.running,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
  });

  final CrawlSource source;
  final bool toggling;
  final bool running;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRun;

  String _fmtTs(DateTime? dt) {
    if (dt == null) return '실행 이력 없음';
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'ok':
        return Colors.green;
      case 'no_change':
        return Colors.blueGrey;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagStyle = theme.textTheme.bodySmall;
    final statusColor = _statusColor(source.lastStatus);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(source.slug,
                          style: tagStyle?.copyWith(color: Colors.grey)),
                    ],
                  ),
                ),
                if (toggling)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(value: source.enabled, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 6),
            Text(source.url,
                style: tagStyle, overflow: TextOverflow.ellipsis, maxLines: 2),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                SourceChip(label: source.sourceType),
                if (source.sport != null) SourceChip(label: source.sport!),
                if (source.region != null) SourceChip(label: source.region!),
                SourceChip(label: 'cron: ${source.scheduleCron}'),
              ],
            ),
            const SizedBox(height: 8),
            Text('parser: ${source.parserModule}', style: tagStyle),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '최근 실행: ${_fmtTs(source.lastCrawledAt)}'
                  '${source.lastStatus != null ? ' · ${source.lastStatus}' : ''}'
                  '${source.lastFetchedCount != null ? ' · fetched ${source.lastFetchedCount}' : ''}',
                  style: tagStyle,
                ),
              ],
            ),
            if (source.lastError != null && source.lastError!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(source.lastError!,
                  style: tagStyle?.copyWith(color: Colors.red)),
            ],
            if (source.notes != null && source.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('메모: ${source.notes!}',
                  style: tagStyle?.copyWith(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: (running || !source.enabled) ? null : onRun,
                  icon: running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(running ? '실행 중...' : '수동 실행'),
                ),
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit),
                  label: const Text('수정'),
                ),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('삭제', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ── Source create/edit dialog ────────────────────────────────────────────────

class SourceFormResult {
  final String name;
  final String slug;
  final String url;
  final String? sport;
  final String? region;
  final String sourceType;
  final String parserModule;
  final String scheduleCron;
  final bool enabled;
  final String? notes;

  SourceFormResult({
    required this.name,
    required this.slug,
    required this.url,
    required this.sport,
    required this.region,
    required this.sourceType,
    required this.parserModule,
    required this.scheduleCron,
    required this.enabled,
    required this.notes,
  });
}

class SourceFormDialog extends StatefulWidget {
  const SourceFormDialog({super.key, this.initial});
  final CrawlSource? initial;

  @override
  State<SourceFormDialog> createState() => _SourceFormDialogState();
}

class _SourceFormDialogState extends State<SourceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _url;
  late final TextEditingController _sport;
  late final TextEditingController _region;
  late final TextEditingController _parserModule;
  late final TextEditingController _scheduleCron;
  late final TextEditingController _notes;
  String _sourceType = 'board';
  bool _enabled = true;

  static const _sourceTypes = ['board', 'rss', 'json_api', 'sitemap'];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _slug = TextEditingController(text: i?.slug ?? '');
    _url = TextEditingController(text: i?.url ?? '');
    _sport = TextEditingController(text: i?.sport ?? '');
    _region = TextEditingController(text: i?.region ?? '');
    _parserModule = TextEditingController(text: i?.parserModule ?? '');
    _scheduleCron =
        TextEditingController(text: i?.scheduleCron ?? '0 21 * * *');
    _notes = TextEditingController(text: i?.notes ?? '');
    _sourceType = i?.sourceType ?? 'board';
    _enabled = i?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _url.dispose();
    _sport.dispose();
    _region.dispose();
    _parserModule.dispose();
    _scheduleCron.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? '필수' : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final sport = _sport.text.trim();
    final region = _region.text.trim();
    final notes = _notes.text.trim();
    Navigator.pop(
      context,
      SourceFormResult(
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        url: _url.text.trim(),
        sport: sport.isEmpty ? null : sport,
        region: region.isEmpty ? null : region,
        sourceType: _sourceType,
        parserModule: _parserModule.text.trim(),
        scheduleCron: _scheduleCron.text.trim(),
        enabled: _enabled,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return AlertDialog(
      title: Text(isEdit ? '크롤 소스 수정' : '크롤 소스 추가'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '이름 (사람이 보는 식별자)',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: _slug,
                  enabled:
                      !isEdit, // slug is the unique key — don't allow rename
                  decoration: InputDecoration(
                    labelText: 'slug (코드 식별자, 영문 소문자/하이픈)',
                    helperText: isEdit ? '생성 후에는 변경할 수 없습니다' : null,
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'URL (listing)'),
                  validator: _required,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _sport,
                        decoration: const InputDecoration(
                          labelText: 'sport (tennis/futsal/빈칸)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _region,
                        decoration: const InputDecoration(
                          labelText: 'region (한글, 전국이면 빈칸)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _sourceType,
                  decoration: const InputDecoration(labelText: 'source_type'),
                  items: _sourceTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _sourceType = v ?? 'board'),
                ),
                TextFormField(
                  controller: _parserModule,
                  decoration: const InputDecoration(
                    labelText: 'parser_module (예: tennis-gwangju-board)',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: _scheduleCron,
                  decoration: const InputDecoration(
                    labelText: 'schedule_cron (예: 0 21 * * *)',
                    helperText: 'Phase 2 dispatcher 도입 이후 동적 스케줄로 적용',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: '메모 (선택)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('enabled'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: Text(isEdit ? '저장' : '추가')),
      ],
    );
  }
}
