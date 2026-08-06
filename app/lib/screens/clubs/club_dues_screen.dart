import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/club_dues.dart';
import '../../models/club_event.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_empty_state.dart';

class ClubDuesScreen extends ConsumerStatefulWidget {
  final Club club;

  const ClubDuesScreen({super.key, required this.club});

  @override
  ConsumerState<ClubDuesScreen> createState() => _ClubDuesScreenState();
}

class _ClubDuesScreenState extends ConsumerState<ClubDuesScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<ClubMember> _members = const [];
  List<ClubDuesPeriod> _periods = const [];
  List<ClubDuesPayment> _payments = const [];
  List<ClubDuesAuditEntry> _audit = const [];
  ClubDuesPeriod? _selectedPeriod;
  final Set<String> _selectedUsers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? selectPeriodId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait<Object>([
        api.clubMembers(widget.club.id),
        api.clubDuesPeriods(widget.club.id),
      ]);
      final members = results[0] as List<ClubMember>;
      final periods = results[1] as List<ClubDuesPeriod>;
      final selected = periods.isEmpty
          ? null
          : periods.firstWhere(
              (period) => period.id == selectPeriodId,
              orElse: () => periods.first,
            );
      final payments = selected == null
          ? <ClubDuesPayment>[]
          : await api.clubDuesPayments(selected.id);
      final audit = await api.clubDuesAudit(
        payments.map((payment) => payment.id),
      );
      if (!mounted) return;
      setState(() {
        _members = members;
        _periods = periods;
        _selectedPeriod = selected;
        _payments = payments;
        _audit = audit;
        _selectedUsers.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPeriod(ClubDuesPeriod period) async {
    if (_selectedPeriod?.id == period.id) return;
    await _load(selectPeriodId: period.id);
  }

  Future<void> _editPeriod({bool createNew = false}) async {
    final initial = createNew ? null : _selectedPeriod;
    final amountController = TextEditingController(
      text: (initial?.amount ?? widget.club.monthlyFee ?? 0).toString(),
    );
    final accountController =
        TextEditingController(text: initial?.accountInfo ?? '');
    var month = initial?.periodMonth ??
        DateTime(DateTime.now().year, DateTime.now().month);
    var dueDate = initial?.dueDate;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(initial == null ? '월별 회비 장부 만들기' : '회비 장부 설정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('회비 월'),
                  subtitle: Text(_monthLabel(month)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: initial != null
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: month,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            helpText: '회비가 적용되는 달을 선택하세요',
                          );
                          if (picked != null) {
                            setDialogState(() {
                              month = DateTime(picked.year, picked.month);
                            });
                          }
                        },
                ),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '회비',
                    suffixText: '원',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('납부 기한'),
                  subtitle: Text(
                    dueDate == null ? '설정 안 함' : _dateLabel(dueDate!),
                  ),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: dueDate ?? month,
                      firstDate: month,
                      lastDate: DateTime(month.year, month.month + 2, 0),
                    );
                    if (picked != null) {
                      setDialogState(() => dueDate = picked);
                    }
                  },
                ),
                TextField(
                  controller: accountController,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: '입금 안내 (선택)',
                    hintText: '예: 카카오뱅크 3333-… 홍길동',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final amount = int.tryParse(amountController.text.trim());
                if (amount == null || amount < 0 || amount > 1000000) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('0원~100만원 사이로 입력해주세요')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      amountController.dispose();
      accountController.dispose();
      return;
    }
    final amount = int.parse(amountController.text.trim());
    final account = accountController.text.trim();
    amountController.dispose();
    accountController.dispose();
    await _runBusy(() async {
      final id = await ref.read(apiProvider).upsertClubDuesPeriod(
            clubId: widget.club.id,
            periodMonth: month,
            amount: amount,
            dueDate: dueDate,
            accountInfo: account.isEmpty ? null : account,
          );
      await _load(selectPeriodId: id);
    }, successMessage: '회비 장부를 저장했습니다');
  }

  Future<void> _changeStatus(
    Iterable<String> userIds,
    ClubDueStatus status,
  ) async {
    final period = _selectedPeriod;
    final ids = userIds.toList(growable: false);
    if (period == null || ids.isEmpty) return;
    await _runBusy(() async {
      await ref.read(apiProvider).setClubDueStatus(
            periodId: period.id,
            userIds: ids,
            status: status,
          );
      await _load(selectPeriodId: period.id);
    }, successMessage: '${ids.length}명의 상태를 ${status.label}로 변경했습니다');
  }

  Future<void> _remindUnpaid() async {
    final period = _selectedPeriod;
    if (period == null) return;
    final unpaid = _payments
        .where((payment) =>
            payment.status == ClubDueStatus.unpaid &&
            (_selectedUsers.isEmpty || _selectedUsers.contains(payment.userId)))
        .map((payment) => payment.userId)
        .toList(growable: false);
    if (unpaid.isEmpty) {
      _showMessage('알림을 보낼 미납 멤버가 없습니다');
      return;
    }
    await _runBusy(() async {
      final count = await ref.read(apiProvider).sendClubDuesReminders(
            periodId: period.id,
            userIds: unpaid,
          );
      if (mounted) _showMessage('$count명에게 앱 알림을 보냈습니다');
    });
  }

  Future<void> _runBusy(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && successMessage != null) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage('처리하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회비 장부'),
        actions: [
          IconButton(
            tooltip: '장부 설정',
            onPressed: _busy ? null : () => _editPeriod(),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: '회비 장부를 불러오지 못했어요',
                  description: _error!,
                  actionLabel: '다시 시도',
                  onAction: _load,
                )
              : _selectedPeriod == null
                  ? AppEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: '아직 회비 장부가 없어요',
                      description: '이번 달 장부를 만들면 멤버별 납부 상태를 체크할 수 있어요.',
                      actionLabel: '이번 달 장부 만들기',
                      onAction: () => _editPeriod(createNew: true),
                    )
                  : _buildLedger(context),
    );
  }

  Widget _buildLedger(BuildContext context) {
    final period = _selectedPeriod!;
    final paymentByUser = {
      for (final payment in _payments) payment.userId: payment,
    };
    // 목록과 같은 기준으로 센다 — 목록은 현재 멤버를 돌면서 "행 없으면 미납"으로
    // 표시하는데, 요약을 _payments 로 세면 행 없는 신규 가입자가 목록엔 미납으로
    // 보이면서 숫자에선 빠지고, 탈퇴자 행은 반대로 숫자에만 남는다.
    int countBy(ClubDueStatus target) => _members
        .where((member) =>
            (paymentByUser[member.userId]?.status ?? ClubDueStatus.unpaid) ==
            target)
        .length;
    final paid = countBy(ClubDueStatus.paid);
    final unpaid = countBy(ClubDueStatus.unpaid);
    final exempt = countBy(ClubDueStatus.exempt);
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => _load(selectPeriodId: period.id),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: period.id,
                  decoration: const InputDecoration(labelText: '회비 월'),
                  items: _periods
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(_monthLabel(item.periodMonth)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _busy
                      ? null
                      : (id) {
                          final next = _periods
                              .where((item) => item.id == id)
                              .firstOrNull;
                          if (next != null) _selectPeriod(next);
                        },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filledTonal(
                tooltip: '다른 달 장부 만들기',
                onPressed:
                    _busy ? null : () => _editPeriod(createNew: true),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: AppRadius.hero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_money(period.amount)}원 · ${period.dueDate == null ? '납부 기한 없음' : '${_dateLabel(period.dueDate!)}까지'}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (period.accountInfo?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(period.accountInfo!),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _SummaryChip(label: '납부', count: paid, color: Colors.green),
                    const SizedBox(width: AppSpacing.sm),
                    _SummaryChip(label: '미납', count: unpaid, color: cs.error),
                    const SizedBox(width: AppSpacing.sm),
                    _SummaryChip(
                        label: '면제', count: exempt, color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Checkbox(
                value: _members.isNotEmpty &&
                    _selectedUsers.length == _members.length,
                tristate: _selectedUsers.isNotEmpty &&
                    _selectedUsers.length != _members.length,
                onChanged: _busy
                    ? null
                    : (checked) => setState(() {
                          _selectedUsers
                            ..clear()
                            ..addAll(checked == true
                                ? _members.map((member) => member.userId)
                                : const <String>[]);
                        }),
              ),
              Expanded(
                child: Text(
                  _selectedUsers.isEmpty
                      ? '멤버 ${_members.length}명'
                      : '${_selectedUsers.length}명 선택',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _remindUnpaid,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('미납 알림'),
              ),
            ],
          ),
          if (_selectedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                children: ClubDueStatus.values
                    .map(
                      (status) => ActionChip(
                        label: Text('일괄 ${status.label}'),
                        onPressed: _busy
                            ? null
                            : () => _changeStatus(_selectedUsers, status),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ..._members.map((member) {
            final payment = paymentByUser[member.userId];
            final status = payment?.status ?? ClubDueStatus.unpaid;
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: Checkbox(
                  value: _selectedUsers.contains(member.userId),
                  onChanged: _busy
                      ? null
                      : (checked) => setState(() {
                            if (checked == true) {
                              _selectedUsers.add(member.userId);
                            } else {
                              _selectedUsers.remove(member.userId);
                            }
                          }),
                ),
                title: Text(
                  member.displayName?.trim().isNotEmpty == true
                      ? member.displayName!
                      : '멤버',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(member.roleLabel),
                trailing: PopupMenuButton<ClubDueStatus>(
                  enabled: !_busy,
                  initialValue: status,
                  onSelected: (next) => _changeStatus([member.userId], next),
                  itemBuilder: (context) => ClubDueStatus.values
                      .map(
                        (item) => PopupMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                  child: _StatusBadge(status: status),
                ),
              ),
            );
          }),
          if (_audit.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '최근 변경 기록',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              children: _audit.take(20).map((entry) {
                final payment = _payments
                    .where((item) => item.id == entry.paymentId)
                    .firstOrNull;
                final member = _members
                    .where((item) => item.userId == payment?.userId)
                    .firstOrNull;
                return ListTile(
                  dense: true,
                  title: Text(
                    '${member?.displayName ?? '멤버'} · ${entry.nextStatus.label}',
                  ),
                  subtitle: Text(_dateTimeLabel(entry.createdAt)),
                );
              }).toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: AppRadius.card,
        ),
        child: Column(
          children: [
            Text('$count명',
                style: TextStyle(color: color, fontWeight: FontWeight.w900)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ClubDueStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ClubDueStatus.paid => Colors.green,
      ClubDueStatus.unpaid => Theme.of(context).colorScheme.error,
      ClubDueStatus.exempt => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

String _monthLabel(DateTime value) => '${value.year}년 ${value.month}월';

String _dateLabel(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  return '${_dateLabel(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _money(int value) {
  final digits = value.toString();
  return digits.replaceAllMapped(
    RegExp(r'(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
}
