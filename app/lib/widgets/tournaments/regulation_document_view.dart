import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/regulation_body_lines.dart';
import '../../models/regulation_document.dart';
import '../../theme/tokens.dart';

enum _RegulationTabKey {
  eligibility,
  schedule,
  registration,
  match,
  guidance,
}

class _RegulationTabGroup {
  const _RegulationTabGroup({
    required this.key,
    required this.label,
    required this.sectionCodes,
  });

  final _RegulationTabKey key;
  final String label;
  final List<RegulationSectionCode> sectionCodes;
}

const _regulationTabGroups = <_RegulationTabGroup>[
  _RegulationTabGroup(
    key: _RegulationTabKey.eligibility,
    label: '참가',
    sectionCodes: [RegulationSectionCode.eligibility],
  ),
  _RegulationTabGroup(
    key: _RegulationTabKey.schedule,
    label: '일정',
    sectionCodes: [RegulationSectionCode.scheduleVenue],
  ),
  _RegulationTabGroup(
    key: _RegulationTabKey.registration,
    label: '신청',
    sectionCodes: [
      RegulationSectionCode.registrationPayment,
      RegulationSectionCode.refundChanges,
    ],
  ),
  _RegulationTabGroup(
    key: _RegulationTabKey.match,
    label: '경기',
    sectionCodes: [
      RegulationSectionCode.matchOperations,
      RegulationSectionCode.awards,
    ],
  ),
  _RegulationTabGroup(
    key: _RegulationTabKey.guidance,
    label: '안내',
    sectionCodes: [
      RegulationSectionCode.noticesContact,
      RegulationSectionCode.other,
    ],
  ),
];

/// 대회 상세에서 요강을 자주 찾는 5개 묶음으로 나눠 표시한다.
///
/// 저장된 [RegulationDocument]는 바꾸지 않고, 현재 탭에 해당하는
/// 섹션만 [RegulationDocumentView]에 넘긴다. 명시적인 미공지·해당 없음
/// 상태는 내용이 비어 있어도 탭을 유지한다.
class RegulationTabbedDocumentView extends StatefulWidget {
  const RegulationTabbedDocumentView({
    super.key,
    required this.document,
    this.hidePublicMetadata = false,
  });

  final RegulationDocument document;
  final bool hidePublicMetadata;

  @override
  State<RegulationTabbedDocumentView> createState() =>
      _RegulationTabbedDocumentViewState();
}

class _RegulationTabbedDocumentViewState
    extends State<RegulationTabbedDocumentView> {
  _RegulationTabKey? _selectedKey;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visibleSections = widget.document.sections
        .where(
          (section) =>
              !widget.hidePublicMetadata || _hasVisiblePublicContent(section),
        )
        .toList(growable: false);
    final availableGroups = _regulationTabGroups
        .where(
          (group) => visibleSections.any(
            (section) => group.sectionCodes.contains(section.code),
          ),
        )
        .toList(growable: false);
    final selectedGroup = availableGroups.isEmpty
        ? null
        : _effectiveSelectedGroup(availableGroups);
    void showAll() => setState(() => _showAll = true);

    final header = Row(
      children: [
        Expanded(
          child: Text(
            '대회 요강',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (availableGroups.isNotEmpty)
          Semantics(
            excludeSemantics: true,
            button: true,
            selected: _showAll,
            label: _showAll ? '전체 요강 보기, 선택됨' : '전체 요강 보기',
            onTap: showAll,
            child: TextButton(
              onPressed: showAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSizes.touchTarget),
                foregroundColor: _showAll
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              child: Text(
                '전체보기',
                style: TextStyle(
                  fontWeight: _showAll ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );

    if (selectedGroup == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: AppSpacing.sm),
          Text(
            '상세 요강이 아직 공지되지 않았습니다.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: AppSpacing.sm),
        _RegulationTabBar(
          groups: availableGroups,
          selectedKey: _showAll ? null : selectedGroup.key,
          onSelected: (key) {
            setState(() {
              _selectedKey = key;
              _showAll = false;
            });
          },
        ),
        if (widget.document.summary != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            widget.document.summary!,
            style: textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        RegulationDocumentView(
          key: ValueKey(_showAll ? 'all' : selectedGroup.key),
          document: RegulationDocument(
            schemaVersion: widget.document.schemaVersion,
            sections: _showAll
                ? visibleSections
                : visibleSections
                    .where(
                      (section) =>
                          selectedGroup.sectionCodes.contains(section.code),
                    )
                    .toList(growable: false),
          ),
          showSummary: false,
          hidePublicMetadata: widget.hidePublicMetadata,
        ),
      ],
    );
  }

  _RegulationTabGroup _effectiveSelectedGroup(
    List<_RegulationTabGroup> availableGroups,
  ) {
    final selectedKey = _selectedKey;
    if (selectedKey != null) {
      for (final group in availableGroups) {
        if (group.key == selectedKey) return group;
      }
    }
    return availableGroups.first;
  }
}

class _RegulationTabBar extends StatelessWidget {
  const _RegulationTabBar({
    required this.groups,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<_RegulationTabGroup> groups;
  final _RegulationTabKey? selectedKey;
  final ValueChanged<_RegulationTabKey> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: AppSizes.touchTarget,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              for (final group in groups)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: selectedKey == group.key,
                    label:
                        '${group.label} 요강 탭${selectedKey == group.key ? ', 선택됨' : ''}',
                    child: Material(
                      color: selectedKey == group.key
                          ? colorScheme.primaryContainer
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => onSelected(group.key),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                width: 2,
                                color: selectedKey == group.key
                                    ? colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Center(
                            child: ExcludeSemantics(
                              child: Text(
                                group.label,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: textTheme.labelLarge?.copyWith(
                                  color: selectedKey == group.key
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: selectedKey == group.key
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegulationDocumentView extends StatelessWidget {
  const RegulationDocumentView({
    super.key,
    required this.document,
    this.showSummary = true,
    this.hidePublicMetadata = false,
  });

  final RegulationDocument document;
  final bool showSummary;
  final bool hidePublicMetadata;

  @override
  Widget build(BuildContext context) {
    final summary = document.summary;
    final sections = document.sections
        .where(
          (section) => !hidePublicMetadata || _hasVisiblePublicContent(section),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSummary && summary != null) ...[
          Text(
            summary,
            style:
                Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) ...[
            const SizedBox(height: AppSpacing.xl),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.xl),
          ],
          _RegulationSectionView(
            section: sections[index],
            hidePublicMetadata: hidePublicMetadata,
          ),
        ],
      ],
    );
  }
}

class _RegulationSectionView extends StatelessWidget {
  const _RegulationSectionView({
    required this.section,
    required this.hidePublicMetadata,
  });

  final RegulationSection section;
  final bool hidePublicMetadata;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final blocks = section.blocks
        .where(
          (block) =>
              !hidePublicMetadata || _hasVisiblePublicBlockContent(block),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.code.label,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (section.availability != RegulationAvailability.present)
          Text(
            section.availability == RegulationAvailability.notAnnounced
                ? '아직 공지되지 않았습니다.'
                : '이 대회에는 해당하지 않습니다.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          )
        else
          for (var index = 0; index < blocks.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            _RegulationBlockView(
              block: blocks[index],
              hidePublicMetadata: hidePublicMetadata,
            ),
          ],
      ],
    );
  }
}

class _RegulationBlockView extends StatelessWidget {
  const _RegulationBlockView({
    required this.block,
    required this.hidePublicMetadata,
  });

  final RegulationBlock block;
  final bool hidePublicMetadata;

  @override
  Widget build(BuildContext context) => switch (block.type) {
        RegulationBlockType.paragraph => _Paragraph(text: block.text!),
        RegulationBlockType.subheading => _Subheading(text: block.text!),
        RegulationBlockType.bullets => _BulletList(items: block.items),
        RegulationBlockType.keyValues => _KeyValueList(
            entries: hidePublicMetadata
                ? _visiblePublicEntries(block.entries)
                : block.entries,
          ),
        RegulationBlockType.table => _RegulationTable(
            columns: block.columns,
            rows: block.rows,
          ),
        RegulationBlockType.notice => _Notice(text: block.text!),
        RegulationBlockType.divisionSchedule =>
          _DivisionSchedule(items: block.divisions),
      };
}

List<RegulationEntry> _visiblePublicEntries(List<RegulationEntry> entries) =>
    entries
        .where((entry) => !isHiddenPublicRegulationLabel(entry.label))
        .toList(growable: false);

bool _hasVisiblePublicBlockContent(RegulationBlock block) =>
    block.type != RegulationBlockType.keyValues ||
    _visiblePublicEntries(block.entries).isNotEmpty;

bool _hasVisiblePublicContent(RegulationSection section) =>
    section.availability != RegulationAvailability.present ||
    section.blocks.any(_hasVisiblePublicBlockContent);

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
      );
}

class _Subheading extends StatelessWidget {
  const _Subheading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
      );
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style =
        Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55);
    return Column(
      children: [
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: EdgeInsets.only(
                bottom: index == items.length - 1 ? 0 : AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 4),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(items[index], style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyValueList extends StatelessWidget {
  const _KeyValueList({required this.entries});

  final List<RegulationEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < entries.length; index++)
          Padding(
            padding: EdgeInsets.only(
                bottom: index == entries.length - 1 ? 0 : AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entries[index].label,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  entries[index].value,
                  style: textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RegulationTable extends StatelessWidget {
  const _RegulationTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<RegulationTableRow> rows;

  @override
  Widget build(BuildContext context) {
    final columnCount = math.max(
      columns.length,
      rows.fold<int>(0, (count, row) => math.max(count, row.cells.length)),
    );
    if (columnCount == 0) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, columnCount * 144.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: colorScheme.outlineVariant),
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                if (columns.isNotEmpty)
                  TableRow(
                    decoration:
                        BoxDecoration(color: colorScheme.surfaceContainerLow),
                    children: [
                      for (var index = 0; index < columnCount; index++)
                        _TableCell(
                          text: index < columns.length ? columns[index] : '',
                          style: textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                for (final row in rows)
                  TableRow(
                    children: [
                      for (var index = 0; index < columnCount; index++)
                        _TableCell(
                          text:
                              index < row.cells.length ? row.cells[index] : '',
                          style: textTheme.bodySmall?.copyWith(height: 1.45),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Text(text, style: style),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
        ),
      ),
    );
  }
}

class _DivisionSchedule extends StatelessWidget {
  const _DivisionSchedule({required this.items});

  final List<RegulationDivisionItem> items;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.lg),
            _DivisionItem(item: items[index]),
          ],
        ],
      );
}

class _DivisionItem extends StatelessWidget {
  const _DivisionItem({required this.item});

  final RegulationDivisionItem item;

  @override
  Widget build(BuildContext context) {
    final facts = <RegulationEntry>[
      if (item.date != null) RegulationEntry(label: '일정', value: item.date!),
      if (item.venue != null) RegulationEntry(label: '장소', value: item.venue!),
      if (item.fee != null) RegulationEntry(label: '참가비', value: item.fee!),
      if (item.account != null)
        RegulationEntry(label: '입금계좌', value: item.account!),
      if (item.capacity != null)
        RegulationEntry(label: '모집 규모', value: item.capacity!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Subheading(text: item.name),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _KeyValueList(entries: facts),
        ],
      ],
    );
  }
}
