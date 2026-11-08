// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appName => 'سرنوشت‌ساز';

  @override
  String get appTagline => 'شخصیت تو کسی نیست که نقشش را بازی می‌کنی؛ کسی است که به آن تبدیل می‌شوی.';

  @override
  String get navCharacter => 'شخصیت';

  @override
  String get navQuests => 'مأموریت‌ها';

  @override
  String get navGuilds => 'انجمن‌ها';

  @override
  String get navChronicle => 'وقایع‌نامه';

  @override
  String get navSettings => 'تنظیمات';

  @override
  String get quickAdd => 'مأموریت تازه';

  @override
  String get actionSave => 'ذخیره';

  @override
  String get actionCancel => 'انصراف';

  @override
  String get actionDelete => 'حذف';

  @override
  String get actionEdit => 'ویرایش';

  @override
  String get actionRetry => 'دوباره تلاش کن';

  @override
  String get actionUndo => 'بازگردانی';

  @override
  String get actionDone => 'تمام';

  @override
  String get actionContinue => 'ادامه';

  @override
  String get actionSkip => 'رد شدن';

  @override
  String get actionBack => 'بازگشت';

  @override
  String get actionClose => 'بستن';

  @override
  String get actionCopy => 'رونوشت';

  @override
  String get copied => 'رونوشت گرفته شد';

  @override
  String get offlineBanner => 'در حالت آفلاین کار می‌کنی؛ تغییرات پس از اتصال همگام می‌شوند.';

  @override
  String get errorGeneric => 'مشکلی از سمت ما پیش آمد. داده‌هایت در امان است.';

  @override
  String get actionRateLimited => 'تغییرها پشت سر هم زیاد بود. یک دقیقه صبر کن و دوباره امتحان کن.';

  @override
  String get commentRateLimited => 'در یک ساعت گذشته در این انجمن زیاد نظر گذاشتی. کمی بعد دوباره امتحان کن.';

  @override
  String get loadingLabel => 'در حال بارگذاری';

  @override
  String get attributeStrength => 'قدرت';

  @override
  String get attributeIntelligence => 'هوش';

  @override
  String get attributeDiscipline => 'انضباط';

  @override
  String get attributeCreativity => 'خلاقیت';

  @override
  String get attributeVitality => 'سرزندگی';

  @override
  String get attributeSocial => 'ارتباط';

  @override
  String get attributeStrengthDesc => 'توان جسمی که با تمرین و تحرک ساخته می‌شود.';

  @override
  String get attributeIntelligenceDesc => 'دانش و فهمی که با مطالعه و یادگیری ساخته می‌شود.';

  @override
  String get attributeDisciplineDesc => 'پیوستگی و پایبندی: برنامه بریز و به قولت عمل کن.';

  @override
  String get attributeCreativityDesc => 'ساختن و حل مسئله به شیوه‌های تازه.';

  @override
  String get attributeVitalityDesc => 'استراحت، بازیابی و عادت‌هایی که سالم نگهت می‌دارند.';

  @override
  String get attributeSocialDesc => 'پیوند، گفت‌وگو و حضور برای دیگران.';

  @override
  String characterLevel(String level) {
    return 'سطح $level';
  }

  @override
  String xpProgress(String current, String total) {
    return '$current / $total تجربه';
  }

  @override
  String xpToNextLevel(String xp, String level) {
    return '$xp تجربه تا سطح $level';
  }

  @override
  String attributeRank(String rank) {
    return 'رتبه $rank';
  }

  @override
  String xpToday(String xp) {
    return '‎+$xp امروز';
  }

  @override
  String totalXp(String xp) {
    return '$xp تجربه';
  }

  @override
  String get conditionLabel => 'وضعیت';

  @override
  String get conditionRested => 'سرحال';

  @override
  String get conditionSteady => 'پایدار';

  @override
  String get conditionStrained => 'خسته';

  @override
  String get conditionRestedHelp =>
      'به خوبی بازیابی شده‌ای. وضعیت فقط با زیاده‌روی کم می‌شود، نه با مأموریت‌های انجام‌نشده.';

  @override
  String get conditionSteadyHelp => 'روزهای اخیر پرفشار بوده‌اند. یک روز آرام یا روز استراحت وضعیت را بازمی‌گرداند.';

  @override
  String get conditionStrainedHelp => 'خیلی به خودت فشار آورده‌ای. به یک روز استراحت فکر کن؛ پیشرفتت محفوظ است.';

  @override
  String get sectionAttributes => 'ویژگی‌ها';

  @override
  String get sectionToday => 'امروز';

  @override
  String get sectionRecentGrowth => 'رشد اخیر';

  @override
  String get sectionAchievements => 'دستاوردها';

  @override
  String get sectionConsistency => 'پیوستگی';

  @override
  String get todayEmpty => 'برای امروز عهدی نبسته‌ای.';

  @override
  String get todayEmptyAction => 'عهد یک مأموریت';

  @override
  String get growthEmpty => 'یک مأموریت را انجام بده تا رشدت این‌جا ثبت شود.';

  @override
  String get achievementsEmpty => 'دستاوردها نقطه‌های عطف را نشان می‌دهند. نخستینش تنها یک مأموریت فاصله دارد.';

  @override
  String get classUnrevealed => 'طبقه‌ات در سطح ۵ آشکار می‌شود.';

  @override
  String get noTitle => 'لقبی برنگزیده‌ای';

  @override
  String get equipTitle => 'برگزیدن لقب';

  @override
  String weeklyTargetProgress(String active, String target) {
    return '$active از $target روز در این هفته';
  }

  @override
  String weeksKept(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText هفته پایبندی',
      zero: 'هنوز هفته‌ای کامل نشده',
    );
    return '$_temp0';
  }

  @override
  String chainDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'زنجیره‌ی $countText روزه',
      zero: 'هنوز زنجیره‌ای نیست',
    );
    return '$_temp0';
  }

  @override
  String bestRecord(String value) {
    return 'بهترین: $value';
  }

  @override
  String get levelLabel => 'سطح';

  @override
  String get className_scholar => 'دانشور';

  @override
  String get className_warden => 'نگهبان';

  @override
  String get className_artisan => 'هنرور';

  @override
  String get className_vanguard => 'پیشتاز';

  @override
  String get className_envoy => 'سفیر';

  @override
  String get className_druid => 'شفاگر';

  @override
  String get className_explorer => 'جهانگرد';

  @override
  String get className_strategist => 'تدبیرگر';

  @override
  String get className_arcanist => 'رازدان';

  @override
  String get classDesc_scholar => 'مسیر اخیرت، راه مطالعه و فهم بوده است.';

  @override
  String get classDesc_warden => 'برنامه می‌ریزی، به قولت پایبندی و استوار می‌مانی.';

  @override
  String get classDesc_artisan => 'دست و ذهنت سرگرم ساختن بوده‌اند.';

  @override
  String get classDesc_vanguard => 'تن را پرورده‌ای و با قدرت پیش می‌روی.';

  @override
  String get classDesc_envoy => 'روی آدم‌ها و پیوندهای میانشان سرمایه گذاشته‌ای.';

  @override
  String get classDesc_druid => 'به استراحت، بازیابی و سلامت رسیدگی کرده‌ای.';

  @override
  String get classDesc_explorer => 'هم‌زمان در جهت‌های گوناگون رشد کرده‌ای.';

  @override
  String get classDesc_strategist => 'یادگیری همراه با اجرای پیوسته.';

  @override
  String get classDesc_arcanist => 'دانشی که به آفرینش بدل شده است.';

  @override
  String get questsTitle => 'مأموریت‌ها';

  @override
  String get tabToday => 'امروز';

  @override
  String get tabUpcoming => 'پیش رو';

  @override
  String get tabContracts => 'قراردادها';

  @override
  String get tabObjectives => 'اهداف';

  @override
  String get tabCompleted => 'انجام‌شده';

  @override
  String get tierDaily => 'مأموریت روزانه';

  @override
  String get tierContract => 'قرارداد';

  @override
  String get tierObjective => 'هدف بلندمدت';

  @override
  String get tierDailyHelp => 'کاری کوچک و مشخص برای امروز.';

  @override
  String get tierContractHelp => 'کاری بزرگ‌تر که چند گام دارد.';

  @override
  String get tierObjectiveHelp => 'هدفی بزرگ که مأموریت‌ها و قراردادها به سویش می‌روند.';

  @override
  String get newQuest => 'مأموریت تازه';

  @override
  String get editQuest => 'ویرایش مأموریت';

  @override
  String get fieldTitle => 'چه کاری انجام می‌دهی؟';

  @override
  String get fieldTitleHint => 'مثلاً ۹۰ دقیقه مطالعه‌ی الکترونیک';

  @override
  String get fieldTitleRequired => 'برای مأموریت نامی بنویس.';

  @override
  String fieldTooLong(String max) {
    return 'خیلی طولانی است؛ حداکثر $max کاراکتر بنویس.';
  }

  @override
  String get fieldNotes => 'یادداشت';

  @override
  String get fieldTier => 'نوع';

  @override
  String get fieldCategory => 'دسته';

  @override
  String get categoryAuto => 'خودت تشخیص بده';

  @override
  String get category_study => 'مطالعه';

  @override
  String get category_work => 'کار';

  @override
  String get category_fitness => 'ورزش';

  @override
  String get category_health => 'سلامت';

  @override
  String get category_creative => 'آفرینش';

  @override
  String get category_social => 'ارتباط';

  @override
  String get category_chores => 'خانه';

  @override
  String get category_admin => 'امور اداری';

  @override
  String get category_mindfulness => 'ذهن‌آگاهی';

  @override
  String get category_reading => 'کتاب‌خوانی';

  @override
  String get category_other => 'سایر';

  @override
  String get fieldDue => 'تاریخ';

  @override
  String get fieldDueNone => 'بدون تاریخ';

  @override
  String get fieldEstimate => 'زمان تخمینی (دقیقه)';

  @override
  String fieldEstimateInvalid(String min, String max) {
    return 'یک عدد صحیح از $min تا $max دقیقه بنویس.';
  }

  @override
  String get fieldIntention => 'کی و کجا انجامش می‌دهی؟';

  @override
  String get fieldIntentionHint => 'مثلاً بعد از شام، پشت میزم';

  @override
  String get fieldIntentionHelp => 'تعیین زمان و مکان، احتمال انجام دادن را بیشتر می‌کند.';

  @override
  String get fieldReminder => 'یادآوری';

  @override
  String get reminderNone => 'بدون یادآوری';

  @override
  String get reminderBody => 'هر وقت آماده بودی، این مأموریت منتظر توست.';

  @override
  String get reminderClear => 'حذف یادآوری';

  @override
  String get fieldRecurrence => 'تکرار';

  @override
  String get recurrenceNone => 'تکرار نمی‌شود';

  @override
  String get recurrenceDaily => 'هر روز';

  @override
  String get recurrenceWeekdays => 'روزهای کاری';

  @override
  String get recurrenceWeekly => 'هر هفته';

  @override
  String get fieldPriority => 'اولویت';

  @override
  String get priorityLow => 'کم';

  @override
  String get priorityNormal => 'عادی';

  @override
  String get priorityHigh => 'زیاد';

  @override
  String get fieldParent => 'بخشی از یک هدف';

  @override
  String get parentNone => 'مستقل';

  @override
  String get fieldSharing => 'اشتراک با انجمن‌ها';

  @override
  String get share_full => 'عنوان و پاداش';

  @override
  String get share_titleOnly => 'فقط عنوان';

  @override
  String get share_completionOnly => 'فقط انجام شدن';

  @override
  String get share_private => 'خصوصی';

  @override
  String get moreOptions => 'گزینه‌های بیشتر';

  @override
  String get swearQuest => 'عهد می‌بندم';

  @override
  String get saveChanges => 'ذخیره‌ی تغییرات';

  @override
  String get deleteQuestTitle => 'این مأموریت حذف شود؟';

  @override
  String get deleteQuestBody => 'مأموریت حذف می‌شود. پاداش‌های ثبت‌شده در وقایع‌نامه‌ات می‌مانند.';

  @override
  String get questDeleted => 'مأموریت حذف شد';

  @override
  String get questsEmptyToday => 'برای امروز عهدی نبسته‌ای. یک مأموریت کوچک کافی است.';

  @override
  String get questsEmptyUpcoming => 'مأموریتی در پیش نیست.';

  @override
  String get questsEmptyContracts =>
      'هنوز قراردادی نداری. قراردادها کارهای بزرگ‌تر و چندمرحله‌ای را در خود جا می‌دهند.';

  @override
  String get questsEmptyObjectives => 'هنوز هدفی نداری. اهداف به مأموریت‌هایت جهت می‌دهند.';

  @override
  String get questsEmptyCompleted => 'مأموریت‌های انجام‌شده این‌جا گرد می‌آیند.';

  @override
  String get dueToday => 'امروز';

  @override
  String get dueTomorrow => 'فردا';

  @override
  String get dueYesterday => 'دیروز';

  @override
  String get dueEarlier => 'تاریخ گذشته';

  @override
  String estimateMinutes(String minutes) {
    return '$minutes دقیقه';
  }

  @override
  String get completeQuest => 'انجام شد';

  @override
  String get completedLabel => 'انجام‌شده';

  @override
  String get subtasks => 'گام‌ها';

  @override
  String get addSubtask => 'افزودن گام';

  @override
  String get subtaskHint => 'گام بعدی';

  @override
  String objectiveProgress(String done, String total) {
    return '$done از $total انجام شده';
  }

  @override
  String get completeSheetTitle => 'مُهر کردن این کردار';

  @override
  String get completeSheetMinutes => 'چند دقیقه طول کشید؟';

  @override
  String get completeSheetMinutesHelp => 'اختیاری. عددهای صادقانه، شخصیتت را صادق نگه می‌دارند.';

  @override
  String completeSheetMinutesInvalid(String max) {
    return 'یک عدد صحیح تا سقف $max دقیقه بنویس.';
  }

  @override
  String get completeSheetConfirm => 'مُهر کن';

  @override
  String get timerStart => 'شروع زمان‌سنج';

  @override
  String get timerStop => 'توقف';

  @override
  String timerRunning(String elapsed) {
    return 'زمان‌سنج روشن است · $elapsed';
  }

  @override
  String get questCompletedToast => 'کردار مُهر شد';

  @override
  String get completionUndone => 'انجام شدن بازگردانده شد';

  @override
  String get rewardTitle => 'کردار ثبت شد';

  @override
  String get rewardProvisional => 'موقت — پس از اتصال به اینترنت تأیید می‌شود.';

  @override
  String rewardTotal(String xp) {
    return '‎+$xp تجربه';
  }

  @override
  String get rewardWhy => 'چرا این پاداش؟';

  @override
  String get rewardSourceAi => 'تفسیر از پیشگو، تصمیم با قواعد.';

  @override
  String get rewardSourceHeuristic => 'تفسیر با قواعد، روی همین دستگاه.';

  @override
  String get rewardNone => 'این بار تجربه‌ای در کار نیست — دلیلش در پایین آمده است.';

  @override
  String levelUp(String level) {
    return 'به سطح $level رسیدی';
  }

  @override
  String rankUp(String attribute, String rank) {
    return '$attribute به رتبه‌ی $rank رسید';
  }

  @override
  String reasonDefault(String attribute, String category) {
    return '$attribute از راه $category رشد کرد.';
  }

  @override
  String creditedMinutes(String minutes) {
    return '$minutes دقیقه محاسبه شد';
  }

  @override
  String adj_duration_plausibility(String credited, String declared) {
    return '$credited دقیقه از $declared دقیقه محاسبه شد؛ این کار معمولاً این‌قدر طول نمی‌کشد.';
  }

  @override
  String adj_tier_minutes_cap(String cap) {
    return 'هر مأموریت حداکثر تا $cap دقیقه محاسبه می‌شود.';
  }

  @override
  String get adj_daily_budget => 'سهم تلاش امروز پر شده است. استراحت هم بخشی از رشد است.';

  @override
  String adj_tier_bonus(String tier) {
    return 'پاداش $tier برای کار بزرگ‌تر.';
  }

  @override
  String get adj_trivial_floor => 'کاری بسیار کوچک، اندکی حساب می‌شود.';

  @override
  String get adj_trivial_limit => 'کارهای کوچک امروز پیش‌تر حساب شده‌اند.';

  @override
  String adj_repetition(String count) {
    return 'کردار مشابه شماره‌ی $count در امروز — تلاش تکراری کمتر حساب می‌شود.';
  }

  @override
  String get adj_low_confidence => 'توضیح روشن نبود؛ با جزئیات بیشتر، تفسیر کامل‌تری به دست می‌آید.';

  @override
  String get adj_follow_through => 'برنامه‌ریزی کردی و انجامش دادی: پاداش انضباط.';

  @override
  String get adj_follow_through_intention =>
      'برنامه‌ریزی کردی، انجامش دادی و زمان و مکانش را هم تعیین کرده بودی: پاداش بیشتر انضباط.';

  @override
  String adj_soft_cap(String attribute) {
    return '$attribute به سقف امروز نزدیک است، پس آهسته‌تر رشد می‌کند.';
  }

  @override
  String adj_hard_cap(String attribute) {
    return '$attribute به سقف امروز رسیده است و فردا دوباره رشد می‌کند.';
  }

  @override
  String get adj_weights_defaulted => 'ویژگی‌ها بر اساس دسته انتخاب شدند.';

  @override
  String achievementUnlocked(String name) {
    return 'دستاورد: $name';
  }

  @override
  String titleUnlocked(String title) {
    return 'لقب تازه: $title';
  }

  @override
  String get achievement_first_oath_name => 'نخستین سوگند';

  @override
  String get achievement_first_oath_desc => 'نخستین مأموریتت را انجام بده.';

  @override
  String get achievement_deeds_10_name => 'ده کردار';

  @override
  String get achievement_deeds_10_desc => '۱۰ مأموریت را انجام بده.';

  @override
  String get achievement_deeds_100_name => 'صد کردار';

  @override
  String get achievement_deeds_100_desc => '۱۰۰ مأموریت را انجام بده.';

  @override
  String get achievement_deeds_1000_name => 'هزار کردار';

  @override
  String get achievement_deeds_1000_desc => '۱٬۰۰۰ مأموریت را انجام بده.';

  @override
  String get achievement_first_contract_name => 'قرارداد مُهرشده';

  @override
  String get achievement_first_contract_desc => 'نخستین قراردادت را به پایان برسان.';

  @override
  String get achievement_first_objective_name => 'راه دراز';

  @override
  String get achievement_first_objective_desc => 'یک هدف بلندمدت را به پایان برسان.';

  @override
  String get achievement_level_5_name => 'آبدیده';

  @override
  String get achievement_level_5_desc => 'به سطح ۵ برس.';

  @override
  String get achievement_level_10_name => 'کارآزموده';

  @override
  String get achievement_level_10_desc => 'به سطح ۱۰ برس.';

  @override
  String get achievement_level_25_name => 'کهنه‌کار';

  @override
  String get achievement_level_25_desc => 'به سطح ۲۵ برس.';

  @override
  String get achievement_rank_10_strength_name => 'پولاد در استخوان';

  @override
  String get achievement_rank_10_strength_desc => 'در قدرت به رتبه‌ی ۱۰ برس.';

  @override
  String get achievement_rank_10_intelligence_name => 'نگهبان دانش';

  @override
  String get achievement_rank_10_intelligence_desc => 'در هوش به رتبه‌ی ۱۰ برس.';

  @override
  String get achievement_rank_10_discipline_name => 'اراده‌ی خم‌نشدنی';

  @override
  String get achievement_rank_10_discipline_desc => 'در انضباط به رتبه‌ی ۱۰ برس.';

  @override
  String get achievement_rank_10_creativity_name => 'رؤیاساز';

  @override
  String get achievement_rank_10_creativity_desc => 'در خلاقیت به رتبه‌ی ۱۰ برس.';

  @override
  String get achievement_rank_10_vitality_name => 'همیشه‌سبز';

  @override
  String get achievement_rank_10_vitality_desc => 'در سرزندگی به رتبه‌ی ۱۰ برس.';

  @override
  String get achievement_rank_10_social_name => 'یار هم‌دل';

  @override
  String get achievement_rank_10_social_desc => 'در ارتباط به رتبه‌ی ۱۰ برس.';

  @override
  String get achievement_kept_weeks_4_name => 'یک ماه پایبندی';

  @override
  String get achievement_kept_weeks_4_desc => 'چهار هفته پشت سر هم به هدف هفتگی‌ات برس.';

  @override
  String get achievement_kept_weeks_12_name => 'ثابت‌قدم';

  @override
  String get achievement_kept_weeks_12_desc => 'دوازده هفته پشت سر هم به هدف هفتگی‌ات برس.';

  @override
  String get achievement_kept_weeks_52_name => 'پیمان‌دار';

  @override
  String get achievement_kept_weeks_52_desc => 'یک سال تمام به هدف هفتگی‌ات پایبند بمان.';

  @override
  String get achievement_the_return_name => 'بازگشت';

  @override
  String get achievement_the_return_desc => 'پس از یک هفته دوری برگرد و مأموریتی انجام بده.';

  @override
  String get achievement_balanced_name => 'یکپارچه';

  @override
  String get achievement_balanced_desc => 'در همه‌ی ویژگی‌ها به رتبه‌ی ۳ برس.';

  @override
  String get achievement_hours_100_name => 'صد ساعت';

  @override
  String get achievement_hours_100_desc => '۱۰۰ ساعت تلاش محاسبه‌شده گرد آور.';

  @override
  String get title_sworn => 'سوگندخورده';

  @override
  String get title_centurion => 'یوزباشی';

  @override
  String get title_pathfinder => 'راه‌یاب';

  @override
  String get title_seasoned => 'کارآزموده';

  @override
  String get title_ironbound => 'پولادین';

  @override
  String get title_adept_of_lore => 'دانای اسرار';

  @override
  String get title_unbending => 'سرسخت';

  @override
  String get title_dreamwright => 'رؤیاساز';

  @override
  String get title_evergreen => 'همیشه‌سبز';

  @override
  String get title_kindred => 'هم‌دل';

  @override
  String get title_steadfast => 'ثابت‌قدم';

  @override
  String get title_oathkeeper => 'پیمان‌دار';

  @override
  String get title_returned => 'بازگشته';

  @override
  String get title_whole => 'یکپارچه';

  @override
  String get chronicleTitle => 'وقایع‌نامه';

  @override
  String get periodWeek => 'هفته';

  @override
  String get periodMonth => 'ماه';

  @override
  String get periodYear => 'سال';

  @override
  String get periodWeekNoun => 'هفته';

  @override
  String get periodMonthNoun => 'ماه';

  @override
  String get periodYearNoun => 'سال';

  @override
  String comparedToSamePoint(Object change) {
    return '$change نسبت به همین زمان در دوره‌ی قبل';
  }

  @override
  String get previousPeriod => 'دوره‌ی قبل';

  @override
  String get nextPeriod => 'دوره‌ی بعد';

  @override
  String get statCompletions => 'کردارها';

  @override
  String get statMinutes => 'زمان صرف‌شده';

  @override
  String get statXp => 'تجربه‌ی کسب‌شده';

  @override
  String get statActiveDays => 'روزهای فعال';

  @override
  String get chartXpByAttribute => 'رشد بر پایه‌ی ویژگی';

  @override
  String get chartDistribution => 'تلاشت کجا رفت';

  @override
  String get chartConsistency => 'آهنگ روزها';

  @override
  String get chronicleEmpty => 'در این دوره کرداری ثبت نشده است.';

  @override
  String get writtenChronicle => 'وقایع‌نامه';

  @override
  String chronicleLocalSummary(String period, String count, String time, String attribute) {
    return 'در این $period $count کردار انجام دادی و $time وقت گذاشتی. بیشترین رشد از آنِ $attribute بود.';
  }

  @override
  String get chronicleNeedsAccount => 'وقایع‌نامه‌ی نوشتاری را پیشگو می‌نگارد و به حساب کاربری نیاز دارد.';

  @override
  String get ledgerTitle => 'دفتر پاداش‌ها';

  @override
  String get ledgerEmpty => 'هر پاداشی که می‌گیری با دلایلش این‌جا ثبت می‌شود.';

  @override
  String comparedToPrevious(String change) {
    return '$change نسبت به دوره‌ی قبل';
  }

  @override
  String get strongestArea => 'پرتمرین‌ترین';

  @override
  String get quietestArea => 'کم‌تمرین‌ترین';

  @override
  String durationHoursMinutes(String hours, String minutes) {
    return '$hours ساعت و $minutes دقیقه';
  }

  @override
  String durationMinutes(String minutes) {
    return '$minutes دقیقه';
  }

  @override
  String get legendActive => 'فعال';

  @override
  String get legendRest => 'استراحت';

  @override
  String get legendQuiet => 'آرام';

  @override
  String get guildsTitle => 'انجمن‌ها';

  @override
  String get guildsIntro => 'انجمن‌ها حلقه‌های کوچکی از آدم‌ها هستند که یکدیگر را در پیشرفت واقعی دلگرم می‌کنند.';

  @override
  String get guildsRequireAccount =>
      'انجمن‌ها آدم‌ها را به هم پیوند می‌دهند، پس به حساب کاربری نیاز دارند. شخصیت و تاریخچه‌ات از آنِ خودت می‌ماند.';

  @override
  String get guildsBackendMissing =>
      'قابلیت‌های آنلاین در این نسخه پیکربندی نشده‌اند. بقیه‌ی بخش‌ها روی همین دستگاه کار می‌کنند.';

  @override
  String get guildsEmpty => 'هنوز عضو هیچ انجمنی نیستی.';

  @override
  String get createGuild => 'بنیان‌گذاری انجمن';

  @override
  String get joinGuild => 'پیوستن با کد';

  @override
  String get guildName => 'نام انجمن';

  @override
  String get guildDescription => 'این انجمن درباره‌ی چیست؟';

  @override
  String get guildVisibility => 'دیده‌شدن';

  @override
  String get visibilityPrivate => 'خصوصی — فقط با دعوت';

  @override
  String get visibilityPublic => 'عمومی — قابل جست‌وجو';

  @override
  String get inviteCode => 'کد دعوت';

  @override
  String get inviteCodeHint => 'مثلاً IRON-PACT-7Q2K';

  @override
  String get shareInvite => 'اشتراک دعوت‌نامه';

  @override
  String get guildFeed => 'تالار';

  @override
  String get guildChallenges => 'چالش‌ها';

  @override
  String get guildMembers => 'اعضا';

  @override
  String get feedEmpty => 'تالار آرام است. مأموریت‌هایی که با این انجمن به اشتراک گذاشته شوند این‌جا می‌آیند.';

  @override
  String memberCount(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$countText عضو');
    return '$_temp0';
  }

  @override
  String get role_guild_master => 'سرپرست انجمن';

  @override
  String get role_officer => 'معاون';

  @override
  String get role_member => 'عضو';

  @override
  String get react_honour => 'احترام';

  @override
  String get react_steel => 'پولاد';

  @override
  String get react_flame => 'شعله';

  @override
  String get react_laurel => 'پیروزی';

  @override
  String commentsCount(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$countText نظر', zero: 'نظر');
    return '$_temp0';
  }

  @override
  String get commentHint => 'یک جمله‌ی دلگرم‌کننده بنویس';

  @override
  String feedCompletedFull(String name, String title, String xp) {
    return '$name «$title» را انجام داد · ‎+$xp تجربه';
  }

  @override
  String feedCompletedTitle(String name, String title) {
    return '$name «$title» را انجام داد';
  }

  @override
  String feedCompletedOnly(String name, String tier) {
    return '$name یک $tier را انجام داد';
  }

  @override
  String feedMilestone(String percent, String challenge) {
    return 'انجمن به $percent از «$challenge» رسید';
  }

  @override
  String feedMemberJoined(Object name) {
    return '$name به انجمن پیوست';
  }

  @override
  String feedChallengeCreated(Object challenge, Object name) {
    return '$name چالش «$challenge» را آغاز کرد';
  }

  @override
  String get formerMember => 'عضو پیشین';

  @override
  String challengeProgress(String current, String target) {
    return '$current از $target';
  }

  @override
  String get challengesEmpty => 'هنوز چالشی نیست. معاونان می‌توانند چالشی جمعی آغاز کنند.';

  @override
  String get newChallenge => 'چالش تازه';

  @override
  String get challengeTitle => 'نام چالش';

  @override
  String get challengeMetricMinutes => 'دقیقه در یک دسته';

  @override
  String get challengeMetricCompletions => 'شمار کردارها';

  @override
  String get challengeTarget => 'هدف جمعی';

  @override
  String get challengeDays => 'مدت به روز';

  @override
  String get challengeNoPenalty => 'اگر به هدف نرسید، هیچ‌کس جریمه نمی‌شود.';

  @override
  String get leaveGuild => 'ترک انجمن';

  @override
  String get muteGuild => 'بی‌صدا کردن اعلان‌ها';

  @override
  String get blockUser => 'مسدود کردن';

  @override
  String get reportContent => 'گزارش';

  @override
  String get reportSent => 'گزارش برای معاونان و ناظران انجمن فرستاده شد.';

  @override
  String get guildCreated => 'انجمن بنیان نهاده شد';

  @override
  String get guildJoined => 'به انجمن خوش آمدی';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get sectionLanguageRegion => 'زبان و منطقه';

  @override
  String get language => 'زبان';

  @override
  String get calendar => 'تقویم';

  @override
  String get calendarGregorian => 'میلادی';

  @override
  String get calendarJalali => 'هجری خورشیدی';

  @override
  String get digits => 'ارقام';

  @override
  String get digitsLatin => '0123456789';

  @override
  String get digitsNative => '۰۱۲۳۴۵۶۷۸۹';

  @override
  String get firstDayOfWeek => 'آغاز هفته';

  @override
  String get sectionProgress => 'پیشرفت';

  @override
  String get weeklyTarget => 'هدف هفتگی';

  @override
  String get weeklyTargetHelp => 'چند روز فعال، یک هفته‌ی کامل به حساب بیاید. عددی واقع‌بینانه بگذار، نه قهرمانانه.';

  @override
  String weeklyTargetValue(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$countText روز');
    return '$_temp0';
  }

  @override
  String get restDayToday => 'امروز را روز استراحت اعلام کن';

  @override
  String get restDayDeclared => 'امروز روز استراحت است. بازیابی هم به حساب می‌آید.';

  @override
  String get pauseMode => 'حالت توقف';

  @override
  String get pauseModeHelp => 'برای سفر، بیماری یا فصل امتحان. پیوستگی منجمد می‌شود و چیزی از دست نمی‌رود.';

  @override
  String get sectionMotivation => 'انگیزه';

  @override
  String get motivationTone => 'دلگرمی‌ها چه لحنی داشته باشند؟';

  @override
  String get toneDirect => 'مستقیم و کوتاه';

  @override
  String get toneGentle => 'حمایتگر و ملایم';

  @override
  String get toneAchievement => 'دستاوردمحور';

  @override
  String get toneAnalytical => 'تحلیلی';

  @override
  String get motivationDrivers => 'بیشتر چه چیزی انگیزه‌ات را می‌سازد؟';

  @override
  String get driverAchievement => 'دستاورد';

  @override
  String get driverSocial => 'دلگرمی از سوی دیگران';

  @override
  String get driverProgress => 'پیشرفت دیدنی';

  @override
  String get driverLongTerm => 'اهداف بلندمدت';

  @override
  String get driverExploration => 'کاوش و شخصی‌سازی';

  @override
  String get driverRoutine => 'برنامه‌های منظم';

  @override
  String get motivationPrivacy => 'فقط برای تنظیم لحن و پیشنهادها به کار می‌رود. هر زمان بخواهی تغییرش بده یا پاکش کن.';

  @override
  String get sectionAi => 'هوش مصنوعی';

  @override
  String get aiEvaluation => 'هوش مصنوعی مأموریت‌های انجام‌شده را تفسیر کند';

  @override
  String get aiEvaluationHelp => 'اگر خاموش باشد، پاداش‌ها فقط از قواعد داخلی می‌آیند.';

  @override
  String get aiLanguage => 'زبان توضیحات هوش مصنوعی';

  @override
  String get aiSameAsApp => 'همان زبان برنامه';

  @override
  String get aiTransparency => 'هوش مصنوعی چه می‌بیند';

  @override
  String get aiTransparencyBody =>
      'فقط عنوان، یادداشت، نوع، دسته، دقیقه‌ها و هدف والای مأموریت انجام‌شده، به‌علاوه‌ی این‌که این هفته چند بار کارهای مشابه انجام داده‌ای. هرگز انجمن‌ها، دیگران یا اطلاعات حسابت را نمی‌بیند. هوش مصنوعی پیشنهاد می‌دهد؛ قواعد ثابت درباره‌ی هر پاداش تصمیم می‌گیرند و سقفش را تعیین می‌کنند.';

  @override
  String get aiProvider => 'هوش مصنوعی خودت';

  @override
  String get aiProviderSummaryNone => 'تنظیم نشده — قواعد داخلی به کار می‌روند (یا هوش مصنوعی سرور، وقتی وارد شده‌ای).';

  @override
  String get aiProviderHelp =>
      'حساب Anthropic، OpenAI، Google Gemini یا یک سرویس سازگار را وصل کن. کلیدت روی همین دستگاه می‌ماند و فقط برای سرویسی که انتخاب می‌کنی فرستاده می‌شود؛ هزینه را همان سرویس مستقیم از تو می‌گیرد.';

  @override
  String get aiProviderKind => 'سرویس‌دهنده';

  @override
  String get aiProviderAnthropic => 'Anthropic (Claude)';

  @override
  String get aiProviderOpenai => 'OpenAI';

  @override
  String get aiProviderGemini => 'Google Gemini';

  @override
  String get aiProviderAnthropicCompatible => 'سرویس سازگار با Anthropic';

  @override
  String get aiProviderOpenaiCompatible => 'سرویس سازگار با OpenAI (OpenRouter، Groq، Ollama…)';

  @override
  String get aiBaseUrl => 'نشانی پایه‌ی API';

  @override
  String get aiBaseUrlHint => 'مثلاً https://openrouter.ai/api/v1';

  @override
  String get aiModel => 'مدل';

  @override
  String get aiModelHint => 'نام مدل، دقیقاً همان‌طور که سرویس‌دهنده‌ات نوشته است';

  @override
  String get aiApiKey => 'کلید API';

  @override
  String get aiApiKeySaved => 'یک کلید روی این دستگاه ذخیره شده است. برای نگه داشتنش، این بخش را خالی بگذار.';

  @override
  String get aiWebKeyNote =>
      'در مرورگر، کلید در فضای رمزگذاری‌شده‌ی همین مرورگر نگه داشته می‌شود. بهتر است از کلیدی با سقف هزینه استفاده کنی.';

  @override
  String get aiTest => 'آزمایش اتصال';

  @override
  String aiTestOk(String category) {
    return 'متصل شد — هوش مصنوعی‌ات یک مأموریت نمونه را «$category» تشخیص داد.';
  }

  @override
  String aiTestFailed(String reason) {
    return 'اتصال برقرار نشد: $reason';
  }

  @override
  String get aiErrAuth => 'کلید پذیرفته نشد';

  @override
  String get aiErrRate => 'درخواست‌ها زیاد است — کمی بعد دوباره امتحان کن';

  @override
  String get aiErrNetwork => 'اتصالی برقرار نیست، یا سرویس‌دهنده درخواست‌های مرورگر را مسدود می‌کند';

  @override
  String get aiErrRefused => 'مدل از پاسخ دادن خودداری کرد';

  @override
  String get aiErrBadResponse => 'پاسخ، ارزیابی معتبری نبود';

  @override
  String aiErrHttp(String status) {
    return 'سرویس‌دهنده خطا داد ($status)';
  }

  @override
  String get aiRemove => 'حذف سرویس‌دهنده و کلید';

  @override
  String get aiSaved => 'ذخیره شد';

  @override
  String get aiInterpreting => 'هوش مصنوعی‌ات در حال تفسیر این کردار است…';

  @override
  String get aiFallbackUsed => 'به هوش مصنوعی‌ات دسترسی نبود، پس قواعد داخلی به کار رفت.';

  @override
  String get sectionNotifications => 'اعلان‌ها';

  @override
  String get notifReminders => 'یادآوری مأموریت‌ها';

  @override
  String get notifGuild => 'واکنش‌ها و نظرهای انجمن';

  @override
  String get notifWeekly => 'وقایع‌نامه‌ی هفتگی';

  @override
  String get pushDevice => 'اعلان‌ها روی این دستگاه';

  @override
  String get pushDeviceOn => 'روشن است. اعلان‌ها حتی وقتی سرنوشت‌ساز بسته است به دستت می‌رسند.';

  @override
  String get pushDeviceOff => 'خاموش است. اجازه بده تا وقتی سرنوشت‌ساز بسته است هم خبرها به دستت برسند.';

  @override
  String get pushDeviceBlocked => 'مسدود است. در تنظیمات مرورگر یا دستگاهت به سرنوشت‌ساز اجازه‌ی اعلان بده.';

  @override
  String get pushAllow => 'اجازه بده';

  @override
  String get pushUnsupported => 'این مرورگر نمی‌تواند اعلان دریافت کند.';

  @override
  String get pushUnsupportedDevice => 'این دستگاه نمی‌تواند اعلان دریافت کند.';

  @override
  String get pushInstallHint =>
      'روی آیفون، سرنوشت‌ساز را به صفحه‌ی اصلی اضافه کن (Share و بعد Add to Home Screen) و از همان‌جا بازش کن تا اعلان‌ها به دستت برسد.';

  @override
  String get pushInAppFallback => 'خبر تازه‌ای منتظرت است.';

  @override
  String get pushOpen => 'باز کن';

  @override
  String get pushChannelName => 'انجمن و وقایع‌نامه';

  @override
  String get pushChannelDescription => 'واکنش‌ها، نظرها و وقایع‌نامه‌ی هفتگی‌ات.';

  @override
  String get quietHours => 'ساعات سکوت';

  @override
  String quietHoursValue(String from, String to) {
    return '$from تا $to';
  }

  @override
  String get notificationsWebNote => 'در مرورگر، یادآوری‌ها فقط وقتی برنامه باز است نمایش داده می‌شوند.';

  @override
  String get sectionAppearance => 'ظاهر';

  @override
  String get installHintTitle => 'برنامه را به صفحه‌ی اصلی اضافه کن';

  @override
  String get installHintBody =>
      'دکمه‌ی Share را بزن (شاید زیر ••• باشد) و بعد «Add to Home Screen» را انتخاب کن. وقتی از صفحه‌ی اصلی بازش کنی، برنامه تمام‌صفحه اجرا می‌شود و می‌تواند برایت اعلان بفرستد.';

  @override
  String get reducedMotion => 'کاهش حرکت';

  @override
  String get reducedEffects => 'کاهش جلوه‌های دیداری';

  @override
  String get themeLabel => 'پوسته';

  @override
  String get themeAuto => 'خودکار';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get languageAuto => 'خودکار';

  @override
  String languageFollowsDevice(String language) {
    return 'مطابق زبان دستگاه: $language';
  }

  @override
  String get deviceLanguage => 'زبان دستگاه شما';

  @override
  String get sectionAccount => 'حساب کاربری';

  @override
  String get guestMode => 'به عنوان مهمان بازی می‌کنی. داده‌هایت روی همین دستگاه است.';

  @override
  String signedInAs(String email) {
    return 'واردشده با $email';
  }

  @override
  String get signIn => 'ورود';

  @override
  String get signOut => 'خروج';

  @override
  String get authHeadline => 'افسانه‌ات را امن نگه دار';

  @override
  String get authIntro =>
      'وارد شو تا شخصیتت روی همه‌ی دستگاه‌هایت همگام شود و بتوانی به انجمن‌ها بپیوندی. هر چه به عنوان مهمان ساخته‌ای، همراهت می‌آید.';

  @override
  String get authContinueEmail => 'ادامه با ایمیل';

  @override
  String get authContinueGoogle => 'ادامه با گوگل';

  @override
  String get authContinueGithub => 'ادامه با گیت‌هاب';

  @override
  String get authOr => 'یا';

  @override
  String get authUsePassword => 'به جایش با گذرواژه وارد شو';

  @override
  String get authUseCode => 'به جایش برایم کد بفرست';

  @override
  String get authCodeTitle => 'ایمیلت را ببین';

  @override
  String authCodeSent(String email) {
    return 'یک کد ۶ رقمی به $email فرستادیم. تا یک ساعت اعتبار دارد.';
  }

  @override
  String get authCodeLabel => 'کد ۶ رقمی';

  @override
  String get authPasteCode => 'چسباندن کد';

  @override
  String get authVerify => 'تأیید';

  @override
  String get authResend => 'فرستادن کد تازه';

  @override
  String authResendIn(String seconds) {
    return 'کد تازه تا $seconds ثانیه‌ی دیگر';
  }

  @override
  String get authCodeResent => 'کد تازه در راه است.';

  @override
  String get authChangeEmail => 'ایمیل دیگری وارد کن';

  @override
  String get authForgotPassword => 'گذرواژه‌ات را فراموش کرده‌ای؟';

  @override
  String get authResetTitle => 'بازنشانی گذرواژه';

  @override
  String get authResetBody => 'ایمیلت را وارد کن تا یک کد ۶ رقمی برای گذاشتن گذرواژه‌ی تازه برایت بفرستیم.';

  @override
  String get authSendCode => 'فرستادن کد';

  @override
  String get authNewPasswordTitle => 'گذرواژه‌ی تازه‌ات را انتخاب کن';

  @override
  String get authNewPassword => 'گذرواژه‌ی تازه';

  @override
  String get authSavePassword => 'ذخیره‌ی گذرواژه';

  @override
  String get authPasswordSaved => 'گذرواژه ذخیره شد. وارد شده‌ای.';

  @override
  String get authPasswordRules => 'دست‌کم ۸ کاراکتر، با حروف و اعداد انگلیسی.';

  @override
  String get authShowPassword => 'نمایش گذرواژه';

  @override
  String get authHidePassword => 'پنهان کردن گذرواژه';

  @override
  String get authErrEmail => 'یک نشانی ایمیل درست وارد کن.';

  @override
  String get authErrCodeLength => 'هر ۶ رقم را وارد کن.';

  @override
  String get authErrCode => 'این کد اشتباه است یا منقضی شده. دوباره نگاهش کن یا کد تازه بخواه.';

  @override
  String get authErrNotConfirmed => 'اول ایمیلت را تأیید کن. یک کد تازه برایت فرستادیم.';

  @override
  String get authErrRateLimit => 'تلاش‌ها زیاد شد. یک دقیقه صبر کن و دوباره امتحان کن.';

  @override
  String get authErrWeakPassword => 'گذرواژه‌ی محکم‌تری انتخاب کن: دست‌کم ۸ کاراکتر، با حروف و اعداد انگلیسی.';

  @override
  String get authErrSamePassword => 'این همان گذرواژه‌ی فعلی‌ات است. یکی تازه انتخاب کن.';

  @override
  String get authErrAccountExists => 'با این ایمیل از قبل حسابی ساخته شده. به جایش وارد شو.';

  @override
  String get authErrProvider => 'این روش ورود الان در دسترس نیست.';

  @override
  String get authErrNetwork => 'به سرور دسترسی نداریم. اتصالت را بررسی کن و دوباره امتحان کن.';

  @override
  String get authErrCancelled => 'ورود لغو شد.';

  @override
  String get deleteAccount => 'حذف حساب';

  @override
  String get deleteAccountBody =>
      'این کار حسابت و هر چه برایش نگه داشته‌ایم را برای همیشه پاک می‌کند، بعد از حساب خارج می‌شوی و این دستگاه هم پاک می‌شود. نظرهایت در انجمن‌ها با نام «عضو پیشین» می‌مانند. این کار برگشت‌پذیر نیست.';

  @override
  String get accountDeleted => 'حسابت حذف شد.';

  @override
  String get createAccount => 'ساخت حساب';

  @override
  String get exportData => 'برون‌بری داده‌هایم';

  @override
  String get exportReady => 'داده‌هایت به صورت JSON رونوشت شد.';

  @override
  String get deleteAllData => 'حذف همه‌ی داده‌ها';

  @override
  String get deleteAllDataBody => 'این کار شخصیت، مأموریت‌ها و تاریخچه‌ات را برای همیشه از این دستگاه پاک می‌کند.';

  @override
  String get signOutClearDevice => 'خروج و پاک‌کردن این دستگاه';

  @override
  String get signOutClearDeviceBody =>
      'از حسابت خارج می‌شوی و این دستگاه شخصیت، مأموریت‌ها و تاریخچه‌ات را فراموش می‌کند. هرچه همگام شده در حسابت می‌ماند؛ تغییرهایی که هنوز همگام نشده‌اند از بین می‌روند.';

  @override
  String get deviceCleared => 'خارج شدی. دیگر داده‌ای از تو روی این دستگاه نیست.';

  @override
  String get handoverTitle => 'تغییرهای ذخیره‌نشده‌ی یک حساب دیگر';

  @override
  String handoverBody(String email, String changes) {
    return '$email روی این دستگاه $changes دارد که هنوز در آن حساب ذخیره نشده است. اگر ادامه دهی، از این دستگاه پاک می‌شوند. برای نگه‌داشتنشان، الان خارج شو، با $email وارد شو و بگذار همگام شوند.';
  }

  @override
  String handoverBodyNoEmail(String changes) {
    return 'حساب دیگری روی این دستگاه $changes دارد که هنوز در آن ذخیره نشده است. اگر ادامه دهی، از این دستگاه پاک می‌شوند. برای نگه‌داشتنشان، الان خارج شو، با همان حساب وارد شو و بگذار همگام شوند.';
  }

  @override
  String get handoverOneChange => 'یک تغییر';

  @override
  String handoverChanges(String count) {
    return '$count تغییر';
  }

  @override
  String get handoverKeep => 'نگه‌شان دار و خارج شو';

  @override
  String get handoverRemove => 'پاکشان کن و ادامه بده';

  @override
  String get dataDeleted => 'همه‌ی داده‌ها حذف شد.';

  @override
  String get aboutLicense => 'کد منبع با مجوز PolyForm Strict 1.0.0 در دسترس است.';

  @override
  String get legalPrivacy => 'حریم خصوصی';

  @override
  String get legalTerms => 'شرایط استفاده';

  @override
  String get authTitle => 'حساب تو';

  @override
  String get authEmail => 'ایمیل';

  @override
  String get authPassword => 'گذرواژه';

  @override
  String get authInvalid => 'ایمیل و گذرواژه با هم جور نیستند.';

  @override
  String get authBackendMissing => 'قابلیت‌های آنلاین در این نسخه پیکربندی نشده‌اند.';

  @override
  String get onbWelcomeBody =>
      'تلاش واقعی، شخصیتی را می‌سازد که همراهت رشد می‌کند — و آنچه به دست آورده هرگز از دست نمی‌دهد.';

  @override
  String get onbChooseLanguage => 'زبانت را برگزین';

  @override
  String get onbNameTitle => 'نامی برای شخصیتت برگزین';

  @override
  String get onbNameHint => 'نام شخصیت';

  @override
  String get onbSigilTitle => 'نشانی برگزین';

  @override
  String get onbAreasTitle => 'می‌خواهی در چه چیزی رشد کنی؟';

  @override
  String get onbAreasHelp => 'تا سه مورد برگزین. هر زمان می‌توانی تغییرش دهی.';

  @override
  String get onbFirstQuestTitle => 'نخستین عهدت را ببند';

  @override
  String get onbFirstQuestHelp => 'کاری واقعی و کوچک که امروز می‌توانی انجام دهی — یا انجامش داده‌ای.';

  @override
  String get onbHowItWorksTitle => 'رشد چگونه رخ می‌دهد';

  @override
  String get onbHowItWorksBody =>
      'کارهای واقعی را انجام می‌دهی. پیشگو هر کدام را تفسیر می‌کند؛ قواعد ثابت پاداش را تعیین می‌کنند، منصفانه سقفش را می‌گذارند و دلیلش را توضیح می‌دهند. هیچ‌چیزی که به دست آورده‌ای از تو گرفته نمی‌شود.';

  @override
  String get onbBegin => 'آغاز';

  @override
  String get onbCompleteNow => 'انجامش داده‌ام — همین حالا مُهرش کن';

  @override
  String get onbLater => 'امروز بعداً انجامش می‌دهم';

  @override
  String get suggestStudy => '۳۰ دقیقه مطالعه';

  @override
  String get suggestWalk => '۲۰ دقیقه پیاده‌روی';

  @override
  String get suggestRead => 'خواندن ۱۰ صفحه کتاب';

  @override
  String get suggestCall => 'تماس با کسی که برایت عزیز است';

  @override
  String get suggestTidy => '۱۵ دقیقه مرتب کردن میز کار';

  @override
  String get suggestCreate => '۲۰ دقیقه طراحی یا نوشتن';

  @override
  String get returnTitle => 'خوش برگشتی';

  @override
  String get returnBody => 'چند روزی دور بودی. اشکالی ندارد. سفرت پاک نشده است. یک هدف کوچک برگزین و ادامه بده.';

  @override
  String get returnAction => 'یک مأموریت کوچک برگزین';

  @override
  String get jalaliMonth1 => 'فروردین';

  @override
  String get jalaliMonth2 => 'اردیبهشت';

  @override
  String get jalaliMonth3 => 'خرداد';

  @override
  String get jalaliMonth4 => 'تیر';

  @override
  String get jalaliMonth5 => 'مرداد';

  @override
  String get jalaliMonth6 => 'شهریور';

  @override
  String get jalaliMonth7 => 'مهر';

  @override
  String get jalaliMonth8 => 'آبان';

  @override
  String get jalaliMonth9 => 'آذر';

  @override
  String get jalaliMonth10 => 'دی';

  @override
  String get jalaliMonth11 => 'بهمن';

  @override
  String get jalaliMonth12 => 'اسفند';
}
