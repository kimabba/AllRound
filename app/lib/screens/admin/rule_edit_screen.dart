import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

class RuleEditScreen extends ConsumerStatefulWidget {
  final RuleArticle? rule; // null = 신규
  final List<String> existingCategories; // 자동완성 제안
  const RuleEditScreen({super.key, this.rule, this.existingCategories = const []});

  @override
  ConsumerState<RuleEditScreen> createState() => _RuleEditScreenState();
}

class _RuleEditScreenState extends ConsumerState<RuleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _sport = widget.rule?.sport ?? 'tennis';
  late final _category = TextEditingController(text: widget.rule?.category ?? '');
  late final _title = TextEditingController(text: widget.rule?.title ?? '');
  late final _body = TextEditingController(text: widget.rule?.body ?? '');
  late final _orderIdx =
      TextEditingController(text: (widget.rule?.orderIdx ?? 0).toString());
  late bool _published = widget.rule?.published ?? true;
  bool _preview = false;
  bool _saving = false;

  bool get _isNew => widget.rule == null;

  @override
  void dispose() {
    _category.dispose();
    _title.dispose();
    _body.dispose();
    _orderIdx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final api = ref.read(apiProvider);
    try {
      final data = {
        'sport': _sport,
        'category': _category.text.trim(),
        'title': _title.text.trim(),
        'body': _body.text,
        'order_idx': int.tryParse(_orderIdx.text.trim()) ?? 0,
        'published': _published,
      };
      if (_isNew) {
        await api.createRule(data);
      } else {
        await api.updateRule(widget.rule!.id, data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recompute() async {
    if (_isNew) return;
    try {
      await ref.read(apiProvider).recomputeRuleEmbedding(widget.rule!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재임베딩 요청 완료')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('재계산 실패: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('문서 삭제'),
        content: const Text(
          '영구 삭제됩니다. 보통은 삭제 대신 "게시" 토글을 끄세요.\n정말 삭제할까요?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteRule(widget.rule!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '문서 작성' : '문서 수정'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: '재임베딩',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _recompute,
            ),
          if (!_isNew)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'tennis', label: Text(sportLabelFromString('tennis'))),
                ButtonSegment(value: 'futsal', label: Text(sportLabelFromString('futsal'))),
              ],
              selected: {_sport},
              onSelectionChanged: (s) => setState(() => _sport = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _category.text),
              optionsBuilder: (v) {
                if (v.text.isEmpty) return widget.existingCategories;
                return widget.existingCategories
                    .where((c) => c.contains(v.text));
              },
              onSelected: (s) => _category.text = s,
              fieldViewBuilder: (context, controller, focus, _) {
                controller.text = _category.text;
                return TextFormField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: '카테고리 *'),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty) ? '카테고리 필수' : null,
                  onChanged: (val) => _category.text = val,
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: '제목 *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '제목 필수' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _orderIdx,
              decoration: const InputDecoration(labelText: '표시 순서 (숫자)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              title: const Text('게시'),
              value: _published,
              onChanged: (v) => setState(() => _published = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('편집')),
                ButtonSegment(value: true, label: Text('미리보기')),
              ],
              selected: {_preview},
              onSelectionChanged: (s) => setState(() => _preview = s.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_preview)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 200),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.card,
                ),
                child: MarkdownBody(data: '# ${_title.text}\n\n${_body.text}'),
              )
            else
              TextFormField(
                controller: _body,
                decoration: const InputDecoration(
                  labelText: '본문 (마크다운)',
                  alignLabelWithHint: true,
                ),
                maxLines: 14,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '본문 필수' : null,
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
