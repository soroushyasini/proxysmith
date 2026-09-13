import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:async';
import '../l10n/app_localizations.dart';
import '../screens/sources_manager_screen.dart';
import '../theme/app_theme.dart';
import 'legionary_logo.dart';
import '../utils/version_utils.dart';

// External links — change here if they ever move.
const String _kTelegramFeedbackUrl = 'https://t.me/romanlegioner';
const String _kReymitUrl = 'https://reymit.ir/romanlegioner';
const String _kUsdtErc20Address = '0x189E983fd42AA7d2c79e23351dD2bDD83E1fA20B';
const String _kReleasesApiUrl =
    'https://api.github.com/repos/soroushyasini/proxysmith/releases/latest';
const String _kReleasesPageUrl =
    'https://github.com/soroushyasini/proxysmith/releases/latest';
const String _kPrivacyPolicyUrl =
    'https://soroushyasini.github.io/proxysmith/privacy-policy/';

Widget _menuItem(IconData icon, String label) => Row(
  children: [
    Icon(icon, size: 18),
    const SizedBox(width: 10),
    Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
  ],
);

/// Top-bar "..." menu button. Opens a popup with About / Sources / Feedback
/// / Donate / Check for updates.
class OptionsMenuButton extends StatelessWidget {
  final String currentVersion;
  final Future<void> Function({String? preferredId})? onSourcesChanged;

  const OptionsMenuButton({
    super.key,
    required this.currentVersion,
    this.onSourcesChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ext = Theme.of(context).extension<ProxySmithColors>()!;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: ext.mutedText, size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: l10n.optionsButton,
      onSelected: (value) async {
        switch (value) {
          case 'about':
            showDialog(
              context: context,
              builder: (_) => AboutDialogContent(version: currentVersion),
            );
          case 'privacy':
            _launch(context, _kPrivacyPolicyUrl);
          case 'sources':
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SourcesManagerScreen()),
            );
            await onSourcesChanged?.call();
          case 'feedback':
            _launch(context, _kTelegramFeedbackUrl);
          case 'donate':
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const DonateSheet(),
            );
          case 'update':
            _checkForUpdate(context, currentVersion);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'about',
          child: _menuItem(Icons.info_outline_rounded, l10n.menuAbout),
        ),
        PopupMenuItem(
          value: 'privacy',
          child: _menuItem(Icons.privacy_tip_outlined, l10n.menuPrivacy),
        ),
        PopupMenuItem(
          value: 'sources',
          child: _menuItem(Icons.list_alt_rounded, l10n.menuSources),
        ),
        PopupMenuItem(
          value: 'update',
          child: _menuItem(
            Icons.system_update_alt_rounded,
            l10n.menuCheckUpdate,
          ),
        ),
        PopupMenuItem(
          value: 'feedback',
          child: _menuItem(
            Icons.chat_bubble_outline_rounded,
            l10n.menuFeedback,
          ),
        ),
        PopupMenuItem(
          value: 'donate',
          child: _menuItem(Icons.favorite_outline_rounded, l10n.menuDonate),
        ),
      ],
    );
  }
}

/// Attempts to open [url] externally. Returns true on success.
/// Surfaces failure to the caller instead of silently doing nothing —
/// canLaunchUrl can under-report on Android when the `queries` manifest
/// block isn't present, so we attempt launchUrl directly and treat a
/// thrown PlatformException as the real failure signal.
Future<bool> _launch(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      _showLaunchFailure(context);
    }
    return launched;
  } catch (_) {
    if (context.mounted) _showLaunchFailure(context);
    return false;
  }
}

void _showLaunchFailure(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(l10n.linkLaunchFailed)));
}

/// Checks GitHub's "latest release" API and compares the tag against the
/// running app version. Shows a dialog if a newer version exists, or a
/// snackbar for "up to date" / "check failed".
Future<void> _checkForUpdate(
  BuildContext context,
  String currentVersion,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final res = await http
        .get(Uri.parse(_kReleasesApiUrl))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
    final tag = (jsonDecode(res.body)['tag_name'] as String).replaceFirst(
      'v',
      '',
    );
    if (!context.mounted) return;

    if (isNewerVersion(tag, currentVersion)) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(l10n.updateAvailableTitle),
          content: Text(l10n.updateAvailableBody(tag, currentVersion)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateLaterButton),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _launch(context, _kReleasesPageUrl);
              },
              child: Text(l10n.updateOpenGithubButton),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.updateUpToDate)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.updateCheckFailed)));
    }
  }
}

class AboutDialogContent extends StatelessWidget {
  final String version;
  const AboutDialogContent({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LegionaryLogo(size: 56),
          const SizedBox(height: 12),
          Text(l10n.aboutTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.aboutVersion(version),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.aboutDescription,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Donate bottom sheet — Reymit link plus the USDT (ERC20) address with a
/// tap-to-copy QR code.
class DonateSheet extends StatelessWidget {
  const DonateSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ext = Theme.of(context).extension<ProxySmithColors>()!;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ext.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.donateTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.donateDescription,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ext.mutedText),
          ),
          const SizedBox(height: 16),

          // Reymit support button
          ElevatedButton.icon(
            onPressed: () => _launch(context, _kReymitUrl),
            icon: const Icon(Icons.favorite_rounded),
            label: Text(l10n.donateSupportButton),
          ),
          const SizedBox(height: 20),

          Text(
            l10n.donateUsdtLabel,
            style: TextStyle(
              fontSize: 11,
              color: ext.mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),

          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ext.cardBorder, width: 0.5),
              ),
              child: SizedBox(
                width: 140,
                height: 140,
                child: QrImageView(
                  data: _kUsdtErc20Address,
                  version: QrVersions.auto,
                  size: 140,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () {
              Clipboard.setData(const ClipboardData(text: _kUsdtErc20Address));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.donateAddressCopied)));
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ext.subtleBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ext.cardBorder, width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _kUsdtErc20Address,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_rounded, size: 16, color: ext.mutedText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
