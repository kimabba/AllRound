import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/providers.dart';

class TournamentEditScreen extends ConsumerStatefulWidget {
  const TournamentEditScreen({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentEditScreen> createState() =>
      _TournamentEditScreenState();
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _data;

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _deadline;
  String _status = 'draft';

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _description = TextEditingController();
    _location = TextEditingController();
    _deadline = TextEditingController();
    _loadTournament();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _deadline.dispose();
    super.dispose();
  }

  Future<void> _loadTournament() async {
    try {
      final supabase = ref.read(supabaseProvider);
      final row = await supabase
          .from('tournaments')
          .select()
          .eq('id', widget.tournamentId)
          .single();
      if (mounted) {
        setState(() {
          _data = row;
          _title.text = row['title'] ?? '';
          _description.text = row['description'] ?? '';
          _location.text = row['location'] ?? '';
          _deadline.text = row['application_deadline'] ?? '';
          _status = row['status'] ?? 'draft';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final descChanged = _description.text != (_data?['description'] ?? '');
      final updates = <String, dynamic>{
        'title': _title.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'location':
            _location.text.trim().isEmpty ? null : _location.text.trim(),
        'application_deadline':
            _deadline.text.trim().isEmpty ? null : _deadline.text.trim(),
        'status': _status,
      };
      if (descChanged) updates['manual_description'] = true;

      await supabase
          .from('tournaments')
          .update(updates)
          .eq('id', widget.tournamentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 완료')),
        );
        context.go('/admin/drafts');
      }
    } on AuthException {
      if (mounted) {
        await Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('대회 편집')),
        body: const Center(child: Text('대회를 찾을 수 없습니다')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 편집'),
        actions: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('저장'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_data!['sport']} · ${_data!['region'] ?? ''} · ${_data!['start_date']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_data!['source_url'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _data!['source_url'],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 24),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '대회명'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '필수' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: '장소'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _deadline,
                  decoration: const InputDecoration(
                    labelText: '신청 마감일 (YYYY-MM-DD)',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(
                        value: 'published', child: Text('Published')),
                    DropdownMenuItem(
                        value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'draft'),
                ),
                const SizedBox(height: 16),
                if (_data!['eligible_grades'] != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final g in (_data!['eligible_grades'] as List))
                        Chip(
                          label: Text(g.toString(),
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
