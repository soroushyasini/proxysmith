// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ProxySmith';

  @override
  String get appTagline => 'Find your fastest proxy';

  @override
  String get configSourceLabel => 'CONFIG SOURCE';

  @override
  String get sourceCustomUrl => 'Custom URL';

  @override
  String get sourceCustomUrlHint => 'Paste a subscription URL';

  @override
  String get testCountLabel => 'Configs to test';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusFetching => 'Fetching subscription...';

  @override
  String statusFetched(int count) {
    return 'Fetched $count configs';
  }

  @override
  String get statusRound1 => 'Testing proxies (round 1 of 3)';

  @override
  String get statusRound2 => 'Refining results (round 2 of 3)';

  @override
  String get statusRound3 => 'Final ranking (round 3 of 3)';

  @override
  String statusProgress(int done, int total) {
    return '$done / $total';
  }

  @override
  String statusDone(int count) {
    return 'Done — $count results';
  }

  @override
  String get statusStopped => 'Stopped';

  @override
  String get errorEmptyBody =>
      'The subscription URL returned an empty response. Check the URL is correct and the server is up.';

  @override
  String get errorDecodeFailure =>
      'The subscription content could not be decoded. It may be a login page or an unsupported format.';

  @override
  String get errorNoValidSchemes =>
      'The subscription has no supported proxy types. Supported: VMess, VLESS, Trojan, Shadowsocks, TUIC, Hysteria2.';

  @override
  String errorNetwork(String message) {
    return 'Could not reach the subscription server after 3 attempts: $message';
  }

  @override
  String errorTimeout(int minutes) {
    return 'Pipeline exceeded the $minutes-minute time limit and was stopped.';
  }

  @override
  String errorGeneric(String message) {
    return 'Error: $message';
  }

  @override
  String get runButton => 'Run pipeline';

  @override
  String get stopButton => 'Stop testing';

  @override
  String get resultsTitle => 'TOP RESULTS';

  @override
  String get copyAll => 'Copy all';

  @override
  String copiedAll(int count) {
    return 'Copied $count URIs';
  }

  @override
  String copiedOne(int index) {
    return 'Copied #$index';
  }

  @override
  String get noResultsYet => 'No results yet';

  @override
  String get noResultsHint => 'Run the pipeline to find working proxies';

  @override
  String get selectButton => 'Select';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get copySelected => 'Copy selected';

  @override
  String get cancelSelection => 'Cancel';

  @override
  String get menuAbout => 'About';

  @override
  String get menuFeedback => 'Send feedback';

  @override
  String get menuDonate => 'Support the project';

  @override
  String get menuSources => 'Manage sources';

  @override
  String get sourcesManagerTitle => 'Subscription sources';

  @override
  String get sourcesBuiltInLabel => 'BUILT-IN';

  @override
  String get sourcesCustomLabel => 'YOUR SOURCES';

  @override
  String get sourcesEmptyHint => 'No custom sources yet. Tap + to add one.';

  @override
  String get sourcesAddTitle => 'Add source';

  @override
  String get sourcesEditTitle => 'Edit source';

  @override
  String get sourcesAliasLabel => 'Name';

  @override
  String get sourcesUrlLabel => 'Subscription URL';

  @override
  String get sourcesAddButton => 'Add';

  @override
  String get sourcesSaveButton => 'Save';

  @override
  String get aboutTitle => 'About ProxySmith';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'ProxySmith tests proxy subscription lists and ranks them by latency so you can find the fastest working server.';

  @override
  String get donateTitle => 'Support the project';

  @override
  String get donateDescription =>
      'If ProxySmith saved you time, consider buying me a coffee or sending a tip.';

  @override
  String get donateCoffeeButton => 'Buy me a coffee';

  @override
  String get donateUsdtLabel => 'USDT (ERC20)';

  @override
  String get donateAddressCopied => 'Address copied';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get feedbackDescription =>
      'Found a bug or have a suggestion? Reach out on Telegram.';

  @override
  String get feedbackButton => 'Open Telegram';

  @override
  String get linkLaunchFailed =>
      'Couldn\'t open the link. No app found to handle it.';

  @override
  String warningPartialResults(String message) {
    return '$message';
  }

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePersian => 'فارسی';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';
}
