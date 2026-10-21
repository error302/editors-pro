import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Phase F: Batch Export Queue panel.
///
/// Renders the state of the batch export queue (engine/src/export_engine/batch.rs).
/// Users can add jobs (with preset + output path), see progress, cancel,
/// and clear finished jobs.
///
/// The amateur move is to export one version, then another, manually,
/// for hours. The pro move is to queue master + platform encodes, start
/// the queue, walk away. See persona/skills/batch-export/SKILL.md.
class BatchExportQueue extends StatefulWidget {
  const BatchExportQueue({
    required this.jobs,
    required this.onAddJob,
    required this.onCancelJob,
    required this.onClearFinished,
    super.key,
  });
  final List<BatchJob> jobs;
  final VoidCallback onAddJob;
  final void Function(String jobId) onCancelJob;
  final VoidCallback onClearFinished;

  @override
  State<BatchExportQueue> createState() => _BatchExportQueueState();
}

class _BatchExportQueueState extends State<BatchExportQueue> {
  @override
  Widget build(BuildContext context) {
    final queued =
        widget.jobs.where((j) => j.status == BatchJobStatus.queued).length;
    final running =
        widget.jobs.where((j) => j.status == BatchJobStatus.running).length;
    final completed =
        widget.jobs.where((j) => j.status == BatchJobStatus.completed).length;
    final failed =
        widget.jobs.where((j) => j.status == BatchJobStatus.failed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Batch Export Queue',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: 'Clear finished',
              onPressed: widget.onClearFinished,
            ),
            const SizedBox(width: AppTheme.spacing4),
            ElevatedButton.icon(
              onPressed: widget.onAddJob,
              icon: const Icon(Icons.add),
              label: const Text('Add job'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing8),
        // Summary
        Row(
          children: [
            _StatusChip('Queued', queued, Colors.grey),
            const SizedBox(width: AppTheme.spacing4),
            _StatusChip('Running', running, Colors.blue),
            const SizedBox(width: AppTheme.spacing4),
            _StatusChip('Completed', completed, Colors.green),
            const SizedBox(width: AppTheme.spacing4),
            _StatusChip('Failed', failed, Colors.red),
          ],
        ),
        const SizedBox(height: AppTheme.spacing16),
        // Job list
        Expanded(
          child: widget.jobs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.queue_music_outlined,
                        size: 48,
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(height: AppTheme.spacing8),
                      Text(
                        'No jobs queued. Add one to start.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: widget.jobs.length,
                  itemBuilder: (context, i) => _JobTile(
                    job: widget.jobs[i],
                    onCancel: () => widget.onCancelJob(widget.jobs[i].id),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onCancel});
  final BatchJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = _statusInfo(job.status);
    return Card(
      child: ListTile(
        leading: Icon(status.icon, color: status.color),
        title: Text(job.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${job.preset} • ${job.outputPath}',
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (job.status == BatchJobStatus.running) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: job.progress),
              const SizedBox(height: 2),
              Text(
                '${(job.progress * 100).round()}%',
                style: const TextStyle(fontSize: 11),
              ),
            ] else if (job.status == BatchJobStatus.failed) ...[
              const SizedBox(height: 4),
              Text(
                job.error ?? 'Unknown error',
                style: TextStyle(fontSize: 11, color: status.color),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: (job.status == BatchJobStatus.queued ||
                job.status == BatchJobStatus.running)
            ? IconButton(
                icon: const Icon(Icons.cancel_outlined),
                onPressed: onCancel,
                tooltip: 'Cancel',
              )
            : null,
      ),
    );
  }

  _StatusInfo _statusInfo(BatchJobStatus s) {
    switch (s) {
      case BatchJobStatus.queued:
        return const _StatusInfo(Icons.schedule, Colors.grey, 'Queued');
      case BatchJobStatus.running:
        return const _StatusInfo(Icons.play_arrow, Colors.blue, 'Running');
      case BatchJobStatus.completed:
        return const _StatusInfo(Icons.check_circle, Colors.green, 'Completed');
      case BatchJobStatus.failed:
        return const _StatusInfo(Icons.error, Colors.red, 'Failed');
      case BatchJobStatus.cancelled:
        return const _StatusInfo(Icons.cancel, Colors.grey, 'Cancelled');
    }
  }
}

class _StatusInfo {
  const _StatusInfo(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;
}

/// Mirrors the Rust `ExportJob` / `JobStatus` from batch.rs.
class BatchJob {
  BatchJob({
    required this.id,
    required this.name,
    required this.projectPath,
    required this.outputPath,
    required this.preset,
    required this.status,
    required this.progress,
    this.error,
  });
  final String id;
  final String name;
  final String projectPath;
  final String outputPath;
  final String preset;
  final BatchJobStatus status;
  final double progress;
  final String? error;
}

enum BatchJobStatus { queued, running, completed, failed, cancelled }
