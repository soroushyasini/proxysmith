import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Two distinct pieces of feedback, addressing the difference between
/// "which round are we in" (discrete, 3 steps) and "how far along are we"
/// (continuous, 0.0-1.0):
///
///  1. A real LinearProgressIndicator-style bar showing continuous overall
///     progress (0-100%), animated.
///  2. A compact 3-dot step indicator showing which round is active/done,
///     completely separate from the progress bar so neither is doing both
///     jobs at once.
class StageProgress extends StatelessWidget {
  final double progress; // 0.0 - 1.0 overall, continuous
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
            // -- Step indicator: which round is active --
            Row(
              children: List.generate(3, (i) {
                final stage = i + 1;
                final isDone = round > stage;
                final isActive = round == stage;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: isDone
                          ? primary
                          : isActive
                              ? primary.withValues(alpha: 0.5)
                              : ext.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),

            // -- Real continuous progress bar --
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 250),
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: ext.subtleBackground,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              ),
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
