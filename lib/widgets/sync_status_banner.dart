import 'package:flutter/material.dart';
import 'package:trideta_v2/services/offline_queue.dart';

/// Shows "3 changes waiting to sync" while saves are waiting for internet,
/// and a red warning if the server refused a change. Shows nothing otherwise.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final q = OfflineQueue.instance;
    return ValueListenableBuilder<int>(
      valueListenable: q.pendingCount,
      builder: (context, pending, _) {
        return ValueListenableBuilder<int>(
          valueListenable: q.failedCount,
          builder: (context, failed, _) {
            if (pending == 0 && failed == 0) return const SizedBox.shrink();
            final hasFailed = failed > 0;
            final bg = hasFailed ? Colors.red.shade50 : Colors.orange.shade50;
            final fg = hasFailed ? Colors.red.shade800 : Colors.orange.shade900;
            final text = hasFailed
                ? "$failed change${failed == 1 ? '' : 's'} could not be saved. Tap to review."
                : "$pending change${pending == 1 ? '' : 's'} waiting to sync. Tap to try now.";
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (hasFailed) {
                      _review(context);
                    } else {
                      q.flush();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasFailed
                              ? Icons.error_outline_rounded
                              : Icons.sync_rounded,
                          color: fg,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _review(BuildContext context) {
    final labels = OfflineQueue.instance.failedJobs
        .map((j) => '- ${j.label}')
        .join('\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changes not saved'),
        content: Text(
          'The server refused these changes. This can happen if the school '
          'subscription is paused or your access changed.\n\n$labels',
        ),
        actions: [
          TextButton(
            onPressed: () {
              OfflineQueue.instance.discardFailed();
              Navigator.of(ctx).pop();
            },
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () {
              OfflineQueue.instance.retryFailed();
              Navigator.of(ctx).pop();
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
