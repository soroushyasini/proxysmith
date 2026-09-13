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
  String get appTagline => 'پایدارترین و سریع‌ترین سرورهای رایگان را پیدا کنید';

  @override
  String get configSourceLabel => 'منبع کانفیگ';

  @override
  String get sourceCustomUrl => 'آدرس سفارشی';

  @override
  String get sourceCustomUrlHint => 'لینک سابسکریپشن را وارد کنید';

  @override
  String get testCountLabel => 'تعداد کانفیگ برای تست';

  @override
  String get advancedSettings => 'تنظیمات پیشرفته تست';

  @override
  String get maxLatencyLabel => 'حداکثر تأخیر (میلی‌ثانیه)';

  @override
  String get concurrencyLabel => 'تست‌های هم‌زمان';

  @override
  String get testEndpointLabel => 'سرور سنجش';

  @override
  String get statusReady => 'آماده برای تست';

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
  String statusDoneTimed(int count, int seconds) {
    return 'تمام شد — $count نتیجه در $seconds ثانیه';
  }

  @override
  String get statusStopped => 'متوقف شد';

  @override
  String get errorEmptyBody =>
      'کانفیگی از لینک سابسکریپشن دریافت نشد. آدرس و سرور را بررسی کنید.';

  @override
  String get errorDecodeFailure =>
      'محتوای سابسکریپشن قابل خواندن نبود. ممکن است صفحه ورود یا فرمت، پشتیبانی‌نشده باشد.';

  @override
  String get errorNoValidSchemes =>
      'سابسکریپشن هیچ نوع پراکسی پشتیبانی‌شده‌ای ندارد. پشتیبانی‌شده‌ها: VMess، VLESS، Trojan، Shadowsocks و Hysteria2.';

  @override
  String get errorSubscriptionTooLarge =>
      'حجم سابسکریپشن از حد ایمنی ۱۰ مگابایت برای پاسخ یا ۶۴ کیلوبایت برای هر خط بیشتر بود.';

  @override
  String get errorNoResults =>
      'هیچ کانفیگی پذیرفته نشد. حد تأخیر یا تعداد کانفیگ‌های آزمایشی را افزایش دهید.';

  @override
  String get errorInvalidOptions =>
      'پیش از شروع، آدرس‌های HTTP(S) و محدودیت‌های تست را درست وارد کنید.';

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
  String get noResultsYet => 'هنوز نتیجه‌ای یافت نشد';

  @override
  String get noResultsHint => 'برای یافتن پراکسی‌های فعال، تست را اجرا کنید';

  @override
  String get selectButton => 'انتخاب';

  @override
  String selectedCount(int count) {
    return '$count مورد انتخاب شد';
  }

  @override
  String get copySelected => 'کپی موارد انتخابی';

  @override
  String get cancelSelection => 'انصراف';

  @override
  String get dismissButton => 'بستن';

  @override
  String get closeButton => 'بستن';

  @override
  String get optionsButton => 'گزینه‌های بیشتر';

  @override
  String get qrButton => 'نمایش کد QR';

  @override
  String resultQrTitle(int index) {
    return 'نتیجه شماره $index';
  }

  @override
  String get menuAbout => 'درباره برنامه';

  @override
  String get menuPrivacy => 'حریم خصوصی';

  @override
  String get menuFeedback => 'ارسال بازخورد';

  @override
  String get menuDonate => 'حمایت از پروژه';

  @override
  String get menuSources => 'مدیریت منابع';

  @override
  String get menuCheckUpdate => 'بررسی به‌روزرسانی';

  @override
  String get updateAvailableTitle => 'به‌روزرسانی موجود است';

  @override
  String updateAvailableBody(String latest, String current) {
    return 'نسخه جدیدتری ($latest) موجود است. نسخه فعلی شما $current است.';
  }

  @override
  String get updateLaterButton => 'بعداً';

  @override
  String get updateOpenGithubButton => 'باز کردن گیت‌هاب';

  @override
  String get updateUpToDate => 'شما از آخرین نسخه استفاده می‌کنید';

  @override
  String get updateCheckFailed => 'بررسی به‌روزرسانی ممکن نشد';

  @override
  String get donateSupportButton => 'حمایت از طریق ریمیت';

  @override
  String get sourcesManagerTitle => 'مخازن سابسکریپشن';

  @override
  String get sourcesBuiltInLabel => 'پیش‌فرض';

  @override
  String get sourcesCustomLabel => 'مخازن شما';

  @override
  String get sourcesEmptyHint =>
      'هنوز مخزن سفارشی اضافه نکرده‌اید. برای افزودن، روی + بزنید.';

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
  String get sourcesDeleteTitle => 'منبع حذف شود؟';

  @override
  String sourcesDeleteBody(String name) {
    return 'منبع «$name» حذف شود؟';
  }

  @override
  String get sourcesDeleteButton => 'حذف';

  @override
  String sourcesDeleted(String name) {
    return '«$name» حذف شد';
  }

  @override
  String get sourcesNameRequired => 'یک نام وارد کنید';

  @override
  String get sourcesUrlInvalid => 'یک آدرس معتبر HTTP یا HTTPS وارد کنید';

  @override
  String get undoButton => 'بازگردانی';

  @override
  String get aboutTitle => 'درباره پراکسی‌اسمیت';

  @override
  String aboutVersion(String version) {
    return 'نسخه $version';
  }

  @override
  String get aboutDescription =>
      'پراکسی‌اسمیت کانفیگ‌های لینک سابسکریپشن شما را طی چند مرحله غربال می‌کند و بر اساس پایداری و تأخیر رتبه‌بندی می‌کند تا یک سرور سریع و پایدار پیدا کنید.';

  @override
  String get donateTitle => 'حمایت از پروژه';

  @override
  String get donateDescription =>
      'اگر پراکسی‌اسمیت در زمان شما صرفه‌جویی کرد و به اتصال پایدار شما کمک کرد، می‌توانید از توسعه‌دهنده این برنامه حمایت کنید.';

  @override
  String get donateUsdtLabel => 'تتر (شبکه ERC20)';

  @override
  String get donateAddressCopied => 'آدرس کپی شد';

  @override
  String get feedbackTitle => 'ارسال بازخورد';

  @override
  String get feedbackDescription =>
      'باگی پیدا کردید یا پیشنهادی دارید؟ از طریق تلگرام با توسعه دهنده در ارتباط باشید.';

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
