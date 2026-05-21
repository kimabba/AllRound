import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/admin.dart';
import '../../models/crawl_source.dart';
import '../../state/providers.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Timer? _refreshTimer;

  List<CrawlAuditLog> _logs = [];
  bool _loadingLogs = false;

  List<Map<String, dynamic>> _drafts = [];
  bool _loadingDrafts = false;

  // Tab 2: crawl_sources DB rows + per-row toggle/delete pending flags
  List<CrawlSource> _sources = [];
  bool _loadingSources = false;
  final Set<String> _togglingIds = {};
  // Phase 2: 수동 실행 중인 source id 집합 (버튼 spinner + 중복 호출 방지)
  final Set<String> _runningIds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_onTabChanged);
    _startRefreshTimer();
    _loadLogs();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // FAB visibility depends on _tab.index — force rebuild on every change.
    if (_tab.indexIsChanging) return;
    if (mounted) setState(() {});
    if (_tab.index == 0) {
      _startRefreshTimer();
      _loadLogs();
    } else {
      _cancelRefreshTimer();
      if (_tab.index == 1) {
        _loadDrafts();
      } else if (_tab.index == 2) {
        _loadSources();
      }
    }
  }

  void _startRefreshTimer() {
    _cancelRefreshTimer();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadLogs();
    });
  }

  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _loadLogs() async {
    if (_loadingLogs) return;
    if (mounted) setState(() => _loadingLogs = true);
    try {
      final api = ref.read(apiProvider);
      final logs = await api.crawlAuditLogs();
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('로그 로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _loadDrafts() async {
    if (_loadingDrafts) return;
    if (mounted) setState(() => _loadingDrafts = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final rows = await supabase
          .from('tournaments')
          .select()
          .eq('status', 'draft')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _drafts = List<Map<String, dynamic>>.from(rows));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Draft 로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingDrafts = false);
    }
  }

  Future<void> _approve(String id) async {
    try {
      final api = ref.read(apiProvider);
      await api.approveTournament(id, approve: true);
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('승인 실패: $e')));
      }
    }
  }

  Future<void> _reject(String id) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: '사유를 입력하세요'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiProvider);
      final reason =
          reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
      await api.approveTournament(id, approve: false, reason: reason);
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('거절 실패: $e')));
      }
    }
  }

  // ── Tab 2: crawl_sources CRUD ─────────────────────────────────────────────

  Future<void> _loadSources() async {
    if (_loadingSources) return;
    if (mounted) setState(() => _loadingSources = true);
    try {
      final api = ref.read(apiProvider);
      final list = await api.crawlSources();
      if (mounted) setState(() => _sources = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('소스 로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  Future<void> _toggleSource(CrawlSource s, bool enabled) async {
    if (_togglingIds.contains(s.id)) return;
    setState(() => _togglingIds.add(s.id));
    try {
      final api = ref.read(apiProvider);
      final updated = await api.toggleCrawlSourceEnabled(s.id, enabled);
      if (mounted) {
        setState(() {
          final i = _sources.indexWhere((x) => x.id == s.id);
          if (i >= 0) _sources[i] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('토글 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _togglingIds.remove(s.id));
    }
  }

  Future<void> _deleteSource(CrawlSource s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('소스 삭제'),
        content: Text("'${s.name}' (${s.slug}) 를 삭제할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiProvider);
      await api.deleteCrawlSource(s.id);
      await _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  /// Phase 2: 수동 실행 — crawl-dispatch?slug=...&force=true 호출.
  /// 실행 후 sources 재로드해서 last_crawled_at / last_status 즉시 반영.
  ///
  /// A4 (Codex 권고): SnackBar 색상으로 성공/실패 시각 구분.
  ///   - executed[0].status == 'ok'      → 기본 (성공)
  ///   - status == 'no_change'           → 회색 (변화 없음, 비-에러)
  ///   - status == 'error'               → 빨강 (parser 실패)
  ///   - executed 비고 skipped 'already_running_or_stale' → 주황 (중복 호출)
  ///   - 그 외 / 예외                    → 빨강
  Future<void> _runManual(CrawlSource s) async {
    if (_runningIds.contains(s.id)) return;
    if (mounted) setState(() => _runningIds.add(s.id));
    try {
      final api = ref.read(apiProvider);
      final res = await api.runCrawlSource(s.slug, force: true);
      final executed = (res['executed'] as List?) ?? const [];
      final skipped = (res['skipped'] as List?) ?? const [];

      String summary;
      Color? bg;
      if (executed.isEmpty) {
        // 실행되지 않음 — 보통 skip 사유 표시.
        if (skipped.isNotEmpty) {
          final first = skipped.first as Map<String, dynamic>;
          final reason = first['reason']?.toString() ?? 'unknown';
          summary = '${s.slug}: skipped · $reason';
          // already_running_or_stale = 동시 호출 방지 (B6) — 주황
          bg = reason == 'already_running_or_stale'
              ? Colors.orange.shade700
              : Colors.grey.shade700;
        } else {
          summary = '${s.slug}: 실행 결과 없음';
          bg = Colors.grey.shade700;
        }
      } else {
        final first = executed.first as Map<String, dynamic>;
        final status = first['status']?.toString() ?? 'unknown';
        summary = '${s.slug}: $status · '
            'fetched ${first['fetched_count'] ?? 0} · '
            'inserted ${first['inserted_count'] ?? 0} · '
            'updated ${first['updated_count'] ?? 0}';
        switch (status) {
          case 'ok':
            bg = null; // 기본 (성공)
            break;
          case 'no_change':
            bg = Colors.blueGrey.shade700;
            break;
          case 'error':
            bg = Colors.red.shade700;
            break;
          default:
            bg = Colors.grey.shade700;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(summary), backgroundColor: bg),
        );
      }
      await _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('수동 실행 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _runningIds.remove(s.id));
    }
  }

  Future<void> _openSourceEditor({CrawlSource? source}) async {
    final result = await showDialog<_SourceFormResult>(
      context: context,
      builder: (ctx) => _SourceFormDialog(initial: source),
    );
    if (result == null) return;
    try {
      final api = ref.read(apiProvider);
      if (source == null) {
        await api.createCrawlSource(
          name: result.name,
          slug: result.slug,
          url: result.url,
          sport: result.sport,
          region: result.region,
          sourceType: result.sourceType,
          parserModule: result.parserModule,
          scheduleCron: result.scheduleCron,
          enabled: result.enabled,
          notes: result.notes,
        );
      } else {
        await api.updateCrawlSource(
          source.id,
          name: result.name,
          url: result.url,
          sport: result.sport,
          region: result.region,
          sourceType: result.sourceType,
          parserModule: result.parserModule,
          scheduleCron: result.scheduleCron,
          enabled: result.enabled,
          notes: result.notes,
          clearSport: result.sport == null,
          clearRegion: result.region == null,
          clearNotes: result.notes == null,
        );
      }
      await _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '크롤 현황'),
            Tab(text: 'Draft 승인'),
            Tab(text: '크롤 소스'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildLogsTab(),
          _buildDraftsTab(),
          _buildSourcesTab(),
        ],
      ),
      floatingActionButton: _tab.index == 2
          ? FloatingActionButton.extended(
              onPressed: () => _openSourceEditor(),
              icon: const Icon(Icons.add),
              label: const Text('소스 추가'),
            )
          : null,
    );
  }

  // ── Tab 1: Crawl History ──────────────────────────────────────────────────

  Widget _buildLogsTab() {
    if (_loadingLogs && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('로그 없음'));
    }
    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _logs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _LogCard(log: _logs[i]),
      ),
    );
  }

  // ── Tab 2: Draft Approval ─────────────────────────────────────────────────

  Widget _buildDraftsTab() {
    if (_loadingDrafts && _drafts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_drafts.isEmpty) {
      return const Center(child: Text('승인 대기 대회 없음'));
    }
    return RefreshIndicator(
      onRefresh: _loadDrafts,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _drafts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final t = _drafts[i];
          final id = t['id'] as String;
          final title = t['title'] as String? ?? '(제목 없음)';
          final sport = t['sport'] as String? ?? '';
          final date = t['start_date']?.toString().substring(0, 10) ?? '';
          final region = t['region'] as String? ?? '';
          final sourceUrl = t['source_url'] as String? ?? '';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('$sport · $date · $region',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (sourceUrl.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sourceUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () => _approve(id),
                        child: const Text('승인'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _reject(id),
                        child: const Text('거절'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Tab 3: Crawl Sources (DB-driven CRUD) ─────────────────────────────────

  Widget _buildSourcesTab() {
    if (_loadingSources && _sources.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sources.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSources,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: const [
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('등록된 크롤 소스가 없습니다.')),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSources,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: _sources.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = _sources[i];
          return _SourceCard(
            source: s,
            toggling: _togglingIds.contains(s.id),
            running: _runningIds.contains(s.id),
            onToggle: (v) => _toggleSource(s, v),
            onEdit: () => _openSourceEditor(source: s),
            onDelete: () => _deleteSource(s),
            onRun: () => _runManual(s),
          );
        },
      ),
    );
  }
}

// ── Source card widget ───────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  const _SourceCard({
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
                _Chip(label: source.sourceType),
                if (source.sport != null) _Chip(label: source.sport!),
                if (source.region != null) _Chip(label: source.region!),
                _Chip(label: 'cron: ${source.scheduleCron}'),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
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

class _SourceFormResult {
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

  _SourceFormResult({
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

class _SourceFormDialog extends StatefulWidget {
  const _SourceFormDialog({this.initial});
  final CrawlSource? initial;

  @override
  State<_SourceFormDialog> createState() => _SourceFormDialogState();
}

class _SourceFormDialogState extends State<_SourceFormDialog> {
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

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? '필수' : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final sport = _sport.text.trim();
    final region = _region.text.trim();
    final notes = _notes.text.trim();
    Navigator.pop(
      context,
      _SourceFormResult(
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
                  enabled: !isEdit, // slug is the unique key — don't allow rename
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
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _sourceType = v ?? 'board'),
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

// ── Log card widget ───────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});
  final CrawlAuditLog log;

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return Colors.blue;
      case 'success':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(log.status);
    final started = log.startedAt.toLocal();
    final ts =
        '${started.year}-${started.month.toString().padLeft(2, '0')}-${started.day.toString().padLeft(2, '0')} '
        '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(log.source,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color),
                  ),
                  child: Text(log.status,
                      style: TextStyle(color: color, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(ts, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
                'fetched: ${log.fetchedCount}  inserted: ${log.insertedCount}  updated: ${log.updatedCount}',
                style: Theme.of(context).textTheme.bodySmall),
            if (log.error != null) ...[
              const SizedBox(height: 4),
              Text(log.error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
