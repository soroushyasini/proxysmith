import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One result row: optional selection checkbox, rank, latency chip,
/// protocol tag, URI, copy button.
///
/// Supports two modes:
///  - Normal: tap copies the URI (existing behavior)
///  - Selection: a checkbox appears on the left; tap toggles selection
///    instead of copying (used for the "select configs to export" flow)
class ProxyResultCard extends StatelessWidget {
  final int rank;
  final int ms;
  final String uri;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;

  const ProxyResultCard({
    super.key,
    required this.rank,
    required this.ms,
    required this.uri,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  /// Extracts the scheme (vless, trojan, vmess, ...) from the URI for
  /// display as a protocol tag.
  String get _protocol {
    final idx = uri.indexOf('://');
    if (idx <= 0) return '?';
    return uri.substring(0, idx);
  }

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final (chipBg, chipFg) = _latencyColors(isDark);

    return InkWell(
      onTap: selectionMode ? () => onSelectedChanged?.call(!selected) : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        color: selectionMode && selected ? primary.withValues(alpha: 0.08) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (selectionMode) ...[
                Checkbox(
                  value: selected,
                  onChanged: onSelectedChanged,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 2),
              ],
              _rankBadge(ext),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _chip('${ms}ms', chipBg, chipFg),
                        const SizedBox(width: 6),
                        _chip(_protocol, ext.subtleBackground, ext.mutedText),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      uri,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: ext.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!selectionMode) Icon(Icons.copy_rounded, size: 16, color: ext.mutedText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(ProxySmithColors ext) {
    final isFirst = rank == 1;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isFirst ? ext.goldBadge : ext.subtleBackground,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isFirst ? ext.goldBadgeText : ext.mutedText,
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: fg),
        ),
      );

  /// Returns (background, foreground) for the latency chip based on
  /// thresholds defined in AppPalette.
  (Color, Color) _latencyColors(bool isDark) {
    if (ms < 150) {
      return isDark
          ? (const Color(0xFF1A2E14), const Color(0xFF8FC96A))
          : (const Color(0xFFE8F5E0), const Color(0xFF4A8030));
    } else if (ms < 400) {
      return isDark
          ? (const Color(0xFF332817), const Color(0xFFE8B860))
          : (const Color(0xFFFEF3E0), const Color(0xFF9A6820));
    } else {
      return isDark
          ? (const Color(0xFF3A1A16), const Color(0xFFE89080))
          : (const Color(0xFFFCE8E6), const Color(0xFF9A3020));
    }
  }
}
