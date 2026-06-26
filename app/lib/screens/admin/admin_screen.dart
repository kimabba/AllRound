import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config.dart';
import '../../models/admin.dart';
import '../../models/crawl_source.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import 'crawl_logs_tab.dart';
import 'crawl_sources_tab.dart';
import 'draft_approval_widgets.dart';
import 'knowledge_base_tab.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.initialTab = 0});
  final int initialTab;

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

  // Phase 3: 일괄 승인/거부용 선택 상태 + 필터 chip.
  final Set<String> _selectedDraftIds = {};
  DraftFilter _draftFilter = DraftFilter.all;
  bool _bulkActionInFlight = false;

  // Tab 2: crawl_sources DB rows + per-row toggle/delete pending flags
  List<CrawlSource> _sources = [];
  bool _loadingSources = false;
  final Set<String> _togglingIds = {};
  // Phase 2: 수동 실행 중인 source id 집합 (버튼 spinner + 중복 호출 방지)
  final Set<String> _runningIds = {};

  // Tab 3: pending clubs
  List<Club> _pendingClubs = [];
  bool _loadingPendingClubs = false;

  @override
  void initState() {
    super.initState();
    _tab =
        TabController(length: 5, vsync: this, initialIndex: widget.initialTab);
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
      } else if (_tab.index == 3) {
        _loadPendingClubs();
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
    if (AppConfig.adminDesignPreview) return;
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
    if (AppConfig.adminDesignPreview) return;
    if (_loadingDrafts) return;
    if (mounted) setState(() => _loadingDrafts = true);
    try {
      final api = ref.read(apiProvider);
      // 023 마이그레이션의 tournament_review_queue view 사용 — 사용자 제보/크롤러 통합.
      final rows = await api.tournamentReviewQueue();
      if (mounted) {
        setState(() {
          _drafts = rows;
          // 이미 처리되어 사라진 id 는 선택 집합에서 제거.
          final existing = rows.map((r) => r['id'] as String).toSet();
          _selectedDraftIds.removeWhere((id) => !existing.contains(id));
        });
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

  /// 현재 필터에 매칭되는 draft 행만 반환. UI 렌더링과 "전체 선택" 모두 이 결과 사용.
  List<Map<String, dynamic>> get _filteredDrafts {
    switch (_draftFilter) {
      case DraftFilter.all:
        return _drafts;
      case DraftFilter.crawler:
        return _drafts.where((r) => r['submission_kind'] == 'crawler').toList();
      case DraftFilter.user:
        return _drafts.where((r) => r['submission_kind'] == 'user').toList();
    }
  }

  Future<void> _bulkApprove() async {
    if (_selectedDraftIds.isEmpty || _bulkActionInFlight) return;
    final ids = _selectedDraftIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일괄 승인'),
        content: Text('${ids.length}건을 일괄 승인할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('승인'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (mounted) setState(() => _bulkActionInFlight = true);
    try {
      final api = ref.read(apiProvider);
      final affected = await api.bulkApproveTournaments(ids);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('승인 완료: $affected건')),
        );
        _selectedDraftIds.clear();
      }
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('일괄 승인 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _bulkActionInFlight = false);
    }
  }

  Future<void> _bulkReject() async {
    if (_selectedDraftIds.isEmpty || _bulkActionInFlight) return;
    final reasonController = TextEditingController();
    final ids = _selectedDraftIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ids.length}건 일괄 거부'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: '거부 사유 (필수)',
          ),
          autofocus: true,
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('거부'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('거부 사유는 필수입니다')),
        );
      }
      return;
    }
    if (mounted) setState(() => _bulkActionInFlight = true);
    try {
      final api = ref.read(apiProvider);
      final affected = await api.bulkRejectTournaments(ids, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('거부 완료: $affected건')),
        );
        _selectedDraftIds.clear();
      }
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('일괄 거부 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _bulkActionInFlight = false);
    }
  }

  void _toggleSelectAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedDraftIds.addAll(_filteredDrafts.map((r) => r['id'] as String));
      } else {
        for (final r in _filteredDrafts) {
          _selectedDraftIds.remove(r['id'] as String);
        }
      }
    });
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
      final reason = reasonController.text.trim().isEmpty
          ? null
          : reasonController.text.trim();
      await api.approveTournament(id, approve: false, reason: reason);
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('거절 실패: $e')));
      }
    }
  }

  // ── Tab 3: pending clubs ───────────────────────────────────────────────────

  Future<void> _loadPendingClubs() async {
    if (AppConfig.adminDesignPreview) return;
    if (_loadingPendingClubs) return;
    if (mounted) setState(() => _loadingPendingClubs = true);
    try {
      final list = await ref.read(apiProvider).pendingClubs();
      if (mounted) setState(() => _pendingClubs = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('클럽 목록 로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingPendingClubs = false);
    }
  }

  Future<void> _approveClub(String clubId, {required bool approve}) async {
    String? reason;
    if (!approve) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('거절 사유'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: '사유를 입력하세요'),
            autofocus: true,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('거절'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    }
    try {
      await ref
          .read(apiProvider)
          .approveClub(clubId, approve: approve, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? '클럽 승인 완료' : '클럽 거절 완료')),
        );
      }
      await _loadPendingClubs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('처리 실패: $e')));
      }
    }
  }

  // ── Tab 2: crawl_sources CRUD ─────────────────────────────────────────────

  Future<void> _loadSources() async {
    if (AppConfig.adminDesignPreview) return;
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
    final result = await showDialog<SourceFormResult>(
      context: context,
      builder: (ctx) => SourceFormDialog(initial: source),
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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '크롤 현황'),
            Tab(text: 'Draft 승인'),
            Tab(text: '크롤 소스'),
            Tab(text: '클럽 승인'),
            Tab(text: '지식베이스'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildLogsTab(),
          _buildDraftsTab(),
          _buildSourcesTab(),
          _buildPendingClubsTab(),
          const KnowledgeBaseTab(),
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
        itemBuilder: (_, i) => LogCard(log: _logs[i]),
      ),
    );
  }

  // ── Tab 2: Draft Approval ─────────────────────────────────────────────────

  Widget _buildDraftsTab() {
    if (_loadingDrafts && _drafts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredDrafts;
    // 현재 필터 결과 중 선택된 개수 — 헤더 표시와 전체선택 토글 상태 계산에 사용.
    final visibleIds = filtered.map((r) => r['id'] as String).toSet();
    final selectedInView = visibleIds.intersection(_selectedDraftIds).length;
    final allSelected =
        filtered.isNotEmpty && selectedInView == filtered.length;
    final crawlerCount =
        _drafts.where((r) => r['submission_kind'] == 'crawler').length;
    final userCount =
        _drafts.where((r) => r['submission_kind'] == 'user').length;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: Text('전체 (${_drafts.length})'),
                selected: _draftFilter == DraftFilter.all,
                onSelected: (_) =>
                    setState(() => _draftFilter = DraftFilter.all),
              ),
              FilterChip(
                label: Text('크롤러 ($crawlerCount)'),
                selected: _draftFilter == DraftFilter.crawler,
                onSelected: (_) =>
                    setState(() => _draftFilter = DraftFilter.crawler),
              ),
              FilterChip(
                label: Text('사용자 제보 ($userCount)'),
                selected: _draftFilter == DraftFilter.user,
                onSelected: (_) =>
                    setState(() => _draftFilter = DraftFilter.user),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: allSelected,
                tristate: true,
                // tristate: 일부만 선택된 경우 null → 한 번 더 누르면 전체 선택.
                onChanged: filtered.isEmpty
                    ? null
                    : (v) => _toggleSelectAll(v ?? true),
              ),
              Text(
                '선택 $selectedInView / ${filtered.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                // 전역 테마 minimumSize: Size.fromHeight(52) = Size(∞, 52)를 오버라이드.
                // Row 안에서 무한 너비 constraint 에러 방지.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: (_selectedDraftIds.isEmpty || _bulkActionInFlight)
                    ? null
                    : _bulkApprove,
                icon: _bulkActionInFlight
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('일괄 승인'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: (_selectedDraftIds.isEmpty || _bulkActionInFlight)
                    ? null
                    : _bulkReject,
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text(
                  '일괄 거부',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadDrafts,
        child: ListView(
          children: [
            header,
            const SizedBox(height: 80),
            const Center(child: Text('승인 대기 대회 없음')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDrafts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        itemCount: filtered.length + 1,
        separatorBuilder: (_, i) =>
            i == 0 ? const SizedBox(height: 8) : const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == 0) return header;
          final t = filtered[i - 1];
          final id = t['id'] as String;
          final title = t['title'] as String? ?? '(제목 없음)';
          final sport = t['sport'] as String? ?? '';
          final startDate = t['start_date']?.toString() ?? '';
          final date =
              startDate.length >= 10 ? startDate.substring(0, 10) : startDate;
          final region = t['region'] as String? ?? '';
          final sourceUrl = t['source_url'] as String? ?? '';
          final source = t['source'] as String? ?? '';
          final kind = t['submission_kind'] as String? ?? 'crawler';
          final submitterEmail = t['submitted_by_email'] as String?;
          final sourceLabel = kind == 'user'
              ? (submitterEmail != null
                  ? submitterEmail.split('@').first
                  : 'user')
              : source.isEmpty
                  ? 'crawler'
                  : source;
          final selected = _selectedDraftIds.contains(id);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedDraftIds.add(id);
                          } else {
                            _selectedDraftIds.remove(id);
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SubmissionKindBadge(kind: kind),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  sourceLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(title,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('$sport · $date · $region',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (sourceUrl.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              sourceUrl,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                ),
                                onPressed: () => _approve(id),
                                child: const Text('승인'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                ),
                                onPressed: () => _reject(id),
                                child: const Text('거절'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Tab 3 (admin): Pending Clubs ─────────────────────────────────────────

  Widget _buildPendingClubsTab() {
    if (_loadingPendingClubs && _pendingClubs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pendingClubs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPendingClubs,
        child: ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('승인 대기 클럽이 없습니다')),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPendingClubs,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _pendingClubs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = _pendingClubs[i];
          final meta = [
            c.sport == 'tennis' ? '테니스' : '풋살',
            if (c.region != null) c.region!,
            if (c.address != null) c.address!,
          ].join(' · ');
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(meta, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (c.contact != null) ...[
                    const SizedBox(height: 2),
                    Text('연락처: ${c.contact!}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (c.description != null) ...[
                    const SizedBox(height: 6),
                    Text(c.description!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36)),
                        onPressed: () => _approveClub(c.id, approve: true),
                        child: const Text('승인'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36)),
                        onPressed: () => _approveClub(c.id, approve: false),
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

  // ── Tab 2: Crawl Sources (DB-driven CRUD) ─────────────────────────────────

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
          return SourceCard(
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
