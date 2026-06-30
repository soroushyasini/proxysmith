import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A labeled horizontal switch — looks like a standard Material Switch
/// with a small text label on each side, used for theme (light/dark) and
/// language (EN/FA) toggles in the top bar.
///
/// This replaces the earlier two-button "pill" toggle, which read more
/// like a segmented control than a simple on/off switch.
class LabeledSwitch extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool value; // true = right side active
  final ValueChanged<bool> onChanged;
  final IconData? leftIcon;
  final IconData? rightIcon;

  const LabeledSwitch({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    required this.onChanged,
    this.leftIcon,
    this.rightIcon,
  });

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    final activeColor = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sideLabel(leftLabel, leftIcon, !value, activeColor, ext),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: activeColor,
                activeTrackColor: activeColor.withValues(alpha: 0.3),
                inactiveThumbColor: ext.mutedText,
                inactiveTrackColor: ext.subtleBackground,
                trackOutlineColor: WidgetStateProperty.all(ext.cardBorder),
              ),
            ),
            const SizedBox(width: 4),
            _sideLabel(rightLabel, rightIcon, value, activeColor, ext),
          ],
        ),
      ),
    );
  }

  Widget _sideLabel(
    String label,
    IconData? icon,
    bool active,
    Color activeColor,
    ProxySmithColors ext,
  ) {
    final color = active ? activeColor : ext.mutedText;
    if (icon != null) {
      return Icon(icon, size: 14, color: color);
    }
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    );
  }
}
