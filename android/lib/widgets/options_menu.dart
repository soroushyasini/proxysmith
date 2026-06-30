import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'legionary_logo.dart';

// External links — change here if they ever move.
const String _kTelegramFeedbackUrl = 'https://t.me/romanlegioner';
const String _kCoffeeBedeUrl = 'https://www.coffeebede.com/romanlegioner';
const String _kCoffeeBedeBannerUrl =
    'https://coffeebede.ir/DashboardTemplateV2/app-assets/images/banner/default-yellow.svg';
const String _kUsdtErc20Address = '0x189E983fd42AA7d2c79e23351dD2bDD83E1fA20B';

/// Top-bar "..." menu button. Opens a popup with About / Feedback / Donate.
class OptionsMenuButton extends StatelessWidget {
  final String currentVersion;

  const OptionsMenuButton({super.key, required this.currentVersion});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ext = Theme.of(context).extension<ProxySmithColors>()!;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: ext.mutedText, size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'about':
            showDialog(
              context: context,
              builder: (_) => AboutDialogContent(version: currentVersion),
            );
          case 'feedback':
            _launch(_kTelegramFeedbackUrl);
          case 'donate':
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const DonateSheet(),
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'about',
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18),
            const SizedBox(width: 10),
            Text(l10n.menuAbout),
          ]),
        ),
        PopupMenuItem(
          value: 'feedback',
          child: Row(children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            const SizedBox(width: 10),
            Text(l10n.menuFeedback),
          ]),
        ),
        PopupMenuItem(
          value: 'donate',
          child: Row(children: [
            const Icon(Icons.favorite_outline_rounded, size: 18),
            const SizedBox(width: 10),
            Text(l10n.menuDonate),
          ]),
        ),
      ],
    );
  }
}

Future<void> _launch(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

/// Donate bottom sheet — CoffeeBede link/banner plus the USDT (ERC20)
/// address with a tap-to-copy QR code.
///
/// Note: renders the QR live via QrImageView (package: qr_flutter) rather
/// than bundling a static QR image asset — keeps the address change a
/// one-line edit (_kUsdtErc20Address above) instead of a regenerate-and-
/// re-bundle step.
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

          // CoffeeBede banner — clickable, opens the donation page
          InkWell(
            onTap: () => _launch(_kCoffeeBedeUrl),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _kCoffeeBedeBannerUrl,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 60,
                  color: const Color(0xFFFFC107),
                  alignment: Alignment.center,
                  child: Text(
                    l10n.donateCoffeeButton,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            l10n.donateUsdtLabel,
            style: TextStyle(fontSize: 11, color: ext.mutedText, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),

          // QR code — generated live from the address constant above.
          // Requires the qr_flutter package in pubspec.yaml.
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.donateAddressCopied)),
              );
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
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
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
