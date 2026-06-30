// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appName => 'پراکسی‌اسمیت';

  @override
  String get appTagline => 'سریع‌ترین پراکسی خود را پیدا کنید';

  @override
  String get configSourceLabel => 'منبع کانفیگ';

  @override
  String get sourceCustomUrl => 'آدرس سفارشی';

  @override
  String get sourceCustomUrlHint => 'لینک سابسکریپشن را وارد کنید';

  @override
  String get testCountLabel => 'تعداد کانفیگ برای تست';

  @override
  String get statusReady => 'آماده';

  @override
  String get statusFetching => 'در حال دریافت سابسکریپشن...';

  @override
  String statusFetched(int count) {
    return '$count کانفیگ دریافت شد';
  }

  @override
  String get statusRound1 => 'تست پراکسی‌ها (دور ۱ از ۳)';

  @override
  String get statusRound2 => 'بهبود نتایج (دور ۲ از ۳)';

  @override
  String get statusRound3 => 'رتبه‌بندی نهایی (دور ۳ از ۳)';

  @override
  String statusProgress(int done, int total) {
    return '$done / $total';
  }

  @override
  String statusDone(int count) {
    return 'تمام شد — $count نتیجه';
  }

  @override
  String get statusStopped => 'متوقف شد';

  @override
  String get errorEmptyBody =>
      'آدرس سابسکریپشن پاسخ خالی برگرداند. آدرس و سرور را بررسی کنید.';

  @override
  String get errorDecodeFailure =>
      'محتوای سابسکریپشن قابل خواندن نبود. ممکن است صفحه ورود یا فرمت پشتیبانی‌نشده باشد.';

  @override
  String get errorNoValidSchemes =>
      'سابسکریپشن هیچ نوع پراکسی پشتیبانی‌شده‌ای ندارد. پشتیبانی‌شده‌ها: VMess، VLESS، Trojan، Shadowsocks، TUIC، Hysteria2.';

  @override
  String errorNetwork(String message) {
    return 'اتصال به سرور سابسکریپشن پس از ۳ تلاش برقرار نشد: $message';
  }

  @override
  String errorTimeout(int minutes) {
    return 'زمان اجرا از $minutes دقیقه بیشتر شد و متوقف گردید.';
  }

  @override
  String errorGeneric(String message) {
    return 'خطا: $message';
  }

  @override
  String get runButton => 'اجرای تست';

  @override
  String get stopButton => 'توقف تست';

  @override
  String get resultsTitle => 'بهترین نتایج';

  @override
  String get copyAll => 'کپی همه';

  @override
  String copiedAll(int count) {
    return '$count آدرس کپی شد';
  }

  @override
  String copiedOne(int index) {
    return 'مورد #$index کپی شد';
  }

  @override
  String get noResultsYet => 'هنوز نتیجه‌ای نیست';

  @override
  String get noResultsHint => 'برای یافتن پراکسی‌های فعال، تست را اجرا کنید';

  @override
  String get menuAbout => 'درباره برنامه';

  @override
  String get menuFeedback => 'ارسال بازخورد';

  @override
  String get menuDonate => 'حمایت از پروژه';

  @override
  String get menuSources => 'مدیریت منابع';

  @override
  String get sourcesManagerTitle => 'منابع سابسکریپشن';

  @override
  String get sourcesBuiltInLabel => 'پیش‌فرض';

  @override
  String get sourcesCustomLabel => 'منابع شما';

  @override
  String get sourcesEmptyHint =>
      'هنوز منبع سفارشی اضافه نکرده‌اید. برای افزودن، روی + بزنید.';

  @override
  String get sourcesAddTitle => 'افزودن منبع';

  @override
  String get sourcesEditTitle => 'ویرایش منبع';

  @override
  String get sourcesAliasLabel => 'نام';

  @override
  String get sourcesUrlLabel => 'آدرس سابسکریپشن';

  @override
  String get sourcesAddButton => 'افزودن';

  @override
  String get sourcesSaveButton => 'ذخیره';

  @override
  String get aboutTitle => 'درباره پراکسی‌اسمیت';

  @override
  String aboutVersion(String version) {
    return 'نسخه $version';
  }

  @override
  String get aboutDescription =>
      'پراکسی‌اسمیت لیست سابسکریپشن پراکسی شما را تست کرده و بر اساس تأخیر، رتبه‌بندی می‌کند تا سریع‌ترین سرور فعال را پیدا کنید.';

  @override
  String get donateTitle => 'حمایت از پروژه';

  @override
  String get donateDescription =>
      'اگر پراکسی‌اسمیت در وقت شما صرفه‌جویی کرد، می‌توانید با یک قهوه یا مبلغی حمایت کنید.';

  @override
  String get donateCoffeeButton => 'خرید قهوه برای من';

  @override
  String get donateUsdtLabel => 'تتر (شبکه ERC20)';

  @override
  String get donateAddressCopied => 'آدرس کپی شد';

  @override
  String get feedbackTitle => 'ارسال بازخورد';

  @override
  String get feedbackDescription =>
      'باگی پیدا کردید یا پیشنهادی دارید؟ از طریق تلگرام در ارتباط باشید.';

  @override
  String get feedbackButton => 'باز کردن تلگرام';

  @override
  String get linkLaunchFailed =>
      'باز کردن لینک ممکن نشد. برنامه‌ای برای این کار پیدا نشد.';

  @override
  String warningPartialResults(String message) {
    return '$message';
  }

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePersian => 'فارسی';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';
}
