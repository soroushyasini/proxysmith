import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows which of the 3 pipeline rounds is active via 3 horizontal segments,
/// plus the human-readable status text passed in by the caller.
class StageProgress extends StatelessWidget {
  final double progress; // 0.0 - 1.0 overall
  final int round; // 0 (not started), 1, 2, or 3
  final String statusText;

  const StageProgress({
    super.key,
    required this.progress,
    required this.round,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(3, (i) {
                final stage = i + 1;
                final isDone = round > stage || (round == 0 && progress >= 1.0);
                final isActive = round == stage;
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: isDone || isActive ? primary : ext.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(fontSize: 11, color: ext.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}
