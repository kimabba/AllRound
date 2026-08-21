import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/regulation_body_lines.dart';
import '../../models/regulation_document.dart';
import '../../theme/tokens.dart';

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
