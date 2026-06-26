import 'package:flutter/material.dart';
import '../../models/admin.dart';

// ── Log card widget ───────────────────────────────────────────────────────────

class LogCard extends StatelessWidget {
  const LogCard({super.key, required this.log});
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
