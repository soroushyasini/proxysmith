import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'ProxySmith'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Find your fastest proxy'**
  String get appTagline;

  /// Label above the subscription source dropdown
  ///
  /// In en, this message translates to:
  /// **'CONFIG SOURCE'**
  String get configSourceLabel;

  /// No description provided for @sourceCustomUrl.
  ///
  /// In en, this message translates to:
  /// **'Custom URL'**
  String get sourceCustomUrl;

  /// No description provided for @sourceCustomUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a subscription URL'**
  String get sourceCustomUrlHint;

  /// No description provided for @testCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Configs to test'**
  String get testCountLabel;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusReady;

  /// No description provided for @statusFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching subscription...'**
  String get statusFetching;

  /// No description provided for @statusFetched.
  ///
  /// In en, this message translates to:
  /// **'Fetched {count} configs'**
  String statusFetched(int count);

  /// No description provided for @statusRound1.
  ///
  /// In en, this message translates to:
  /// **'Testing proxies (round 1 of 3)'**
  String get statusRound1;

  /// No description provided for @statusRound2.
  ///
  /// In en, this message translates to:
  /// **'Refining results (round 2 of 3)'**
  String get statusRound2;

  /// No description provided for @statusRound3.
  ///
  /// In en, this message translates to:
  /// **'Final ranking (round 3 of 3)'**
  String get statusRound3;

  /// No description provided for @statusProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String statusProgress(int done, int total);

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Done — {count} results'**
  String statusDone(int count);

  /// No description provided for @statusStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get statusStopped;

  /// No description provided for @errorEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'The subscription URL returned an empty response. Check the URL is correct and the server is up.'**
  String get errorEmptyBody;

  /// No description provided for @errorDecodeFailure.
  ///
  /// In en, this message translates to:
  /// **'The subscription content could not be decoded. It may be a login page or an unsupported format.'**
  String get errorDecodeFailure;

  /// No description provided for @errorNoValidSchemes.
  ///
  /// In en, this message translates to:
  /// **'The subscription has no supported proxy types. Supported: VMess, VLESS, Trojan, Shadowsocks, TUIC, Hysteria2.'**
  String get errorNoValidSchemes;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the subscription server after 3 attempts: {message}'**
  String errorNetwork(String message);

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Pipeline exceeded the {minutes}-minute time limit and was stopped.'**
  String errorTimeout(int minutes);

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorGeneric(String message);

  /// No description provided for @runButton.
  ///
  /// In en, this message translates to:
  /// **'Run pipeline'**
  String get runButton;

  /// No description provided for @stopButton.
  ///
  /// In en, this message translates to:
  /// **'Stop testing'**
  String get stopButton;

  /// No description provided for @resultsTitle.
  ///
  /// In en, this message translates to:
  /// **'TOP RESULTS'**
  String get resultsTitle;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @copiedAll.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} URIs'**
  String copiedAll(int count);

  /// No description provided for @copiedOne.
  ///
  /// In en, this message translates to:
  /// **'Copied #{index}'**
  String copiedOne(int index);

  /// No description provided for @noResultsYet.
  ///
  /// In en, this message translates to:
  /// **'No results yet'**
  String get noResultsYet;

  /// No description provided for @noResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Run the pipeline to find working proxies'**
  String get noResultsHint;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// No description provided for @menuFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get menuFeedback;

  /// No description provided for @menuDonate.
  ///
  /// In en, this message translates to:
  /// **'Support the project'**
  String get menuDonate;

  /// No description provided for @menuSources.
  ///
  /// In en, this message translates to:
  /// **'Manage sources'**
  String get menuSources;

  /// No description provided for @sourcesManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription sources'**
  String get sourcesManagerTitle;

  /// No description provided for @sourcesBuiltInLabel.
  ///
  /// In en, this message translates to:
  /// **'BUILT-IN'**
  String get sourcesBuiltInLabel;

  /// No description provided for @sourcesCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'YOUR SOURCES'**
  String get sourcesCustomLabel;

  /// No description provided for @sourcesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No custom sources yet. Tap + to add one.'**
  String get sourcesEmptyHint;

  /// No description provided for @sourcesAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get sourcesAddTitle;

  /// No description provided for @sourcesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit source'**
  String get sourcesEditTitle;

  /// No description provided for @sourcesAliasLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sourcesAliasLabel;

  /// No description provided for @sourcesUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Subscription URL'**
  String get sourcesUrlLabel;

  /// No description provided for @sourcesAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get sourcesAddButton;

  /// No description provided for @sourcesSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get sourcesSaveButton;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About ProxySmith'**
  String get aboutTitle;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'ProxySmith tests proxy subscription lists and ranks them by latency so you can find the fastest working server.'**
  String get aboutDescription;

  /// No description provided for @donateTitle.
  ///
  /// In en, this message translates to:
  /// **'Support the project'**
  String get donateTitle;

  /// No description provided for @donateDescription.
  ///
  /// In en, this message translates to:
  /// **'If ProxySmith saved you time, consider buying me a coffee or sending a tip.'**
  String get donateDescription;

  /// No description provided for @donateCoffeeButton.
  ///
  /// In en, this message translates to:
  /// **'Buy me a coffee'**
  String get donateCoffeeButton;

  /// No description provided for @donateUsdtLabel.
  ///
  /// In en, this message translates to:
  /// **'USDT (ERC20)'**
  String get donateUsdtLabel;

  /// No description provided for @donateAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get donateAddressCopied;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackDescription.
  ///
  /// In en, this message translates to:
  /// **'Found a bug or have a suggestion? Reach out on Telegram.'**
  String get feedbackDescription;

  /// No description provided for @feedbackButton.
  ///
  /// In en, this message translates to:
  /// **'Open Telegram'**
  String get feedbackButton;

  /// No description provided for @linkLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link. No app found to handle it.'**
  String get linkLaunchFailed;

  /// No description provided for @warningPartialResults.
  ///
  /// In en, this message translates to:
  /// **'{message}'**
  String warningPartialResults(String message);

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languagePersian.
  ///
  /// In en, this message translates to:
  /// **'فارسی'**
  String get languagePersian;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
