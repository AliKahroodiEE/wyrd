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
/// import 'generated/app_localizations.dart';
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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('fa')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Wyrd'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Your character is not someone you play. Your character is who you become.'**
  String get appTagline;

  /// No description provided for @navCharacter.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get navCharacter;

  /// No description provided for @navQuests.
  ///
  /// In en, this message translates to:
  /// **'Quests'**
  String get navQuests;

  /// No description provided for @navGuilds.
  ///
  /// In en, this message translates to:
  /// **'Guilds'**
  String get navGuilds;

  /// No description provided for @navChronicle.
  ///
  /// In en, this message translates to:
  /// **'Chronicle'**
  String get navChronicle;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @quickAdd.
  ///
  /// In en, this message translates to:
  /// **'New quest'**
  String get quickAdd;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Working offline — changes will sync when you reconnect.'**
  String get offlineBanner;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Your data is safe.'**
  String get errorGeneric;

  /// No description provided for @actionRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many changes in a row. Wait a minute, then try again.'**
  String get actionRateLimited;

  /// No description provided for @commentRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You\'ve posted a lot in this guild in the last hour. Try again later.'**
  String get commentRateLimited;

  /// No description provided for @loadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loadingLabel;

  /// No description provided for @attributeStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get attributeStrength;

  /// No description provided for @attributeIntelligence.
  ///
  /// In en, this message translates to:
  /// **'Intelligence'**
  String get attributeIntelligence;

  /// No description provided for @attributeDiscipline.
  ///
  /// In en, this message translates to:
  /// **'Discipline'**
  String get attributeDiscipline;

  /// No description provided for @attributeCreativity.
  ///
  /// In en, this message translates to:
  /// **'Creativity'**
  String get attributeCreativity;

  /// No description provided for @attributeVitality.
  ///
  /// In en, this message translates to:
  /// **'Vitality'**
  String get attributeVitality;

  /// No description provided for @attributeSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get attributeSocial;

  /// No description provided for @attributeStrengthDesc.
  ///
  /// In en, this message translates to:
  /// **'Physical capability built through training and movement.'**
  String get attributeStrengthDesc;

  /// No description provided for @attributeIntelligenceDesc.
  ///
  /// In en, this message translates to:
  /// **'Knowledge and understanding built through study and learning.'**
  String get attributeIntelligenceDesc;

  /// No description provided for @attributeDisciplineDesc.
  ///
  /// In en, this message translates to:
  /// **'Consistency and follow-through: planning, then keeping your word.'**
  String get attributeDisciplineDesc;

  /// No description provided for @attributeCreativityDesc.
  ///
  /// In en, this message translates to:
  /// **'Making things and solving problems in new ways.'**
  String get attributeCreativityDesc;

  /// No description provided for @attributeVitalityDesc.
  ///
  /// In en, this message translates to:
  /// **'Rest, recovery and the habits that keep you well.'**
  String get attributeVitalityDesc;

  /// No description provided for @attributeSocialDesc.
  ///
  /// In en, this message translates to:
  /// **'Connection, communication and showing up for others.'**
  String get attributeSocialDesc;

  /// No description provided for @characterLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String characterLevel(String level);

  /// No description provided for @xpProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total} XP'**
  String xpProgress(String current, String total);

  /// No description provided for @xpToNextLevel.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to level {level}'**
  String xpToNextLevel(String xp, String level);

  /// No description provided for @attributeRank.
  ///
  /// In en, this message translates to:
  /// **'Rank {rank}'**
  String attributeRank(String rank);

  /// No description provided for @xpToday.
  ///
  /// In en, this message translates to:
  /// **'+{xp} today'**
  String xpToday(String xp);

  /// No description provided for @totalXp.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP'**
  String totalXp(String xp);

  /// No description provided for @conditionLabel.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get conditionLabel;

  /// No description provided for @conditionRested.
  ///
  /// In en, this message translates to:
  /// **'Rested'**
  String get conditionRested;

  /// No description provided for @conditionSteady.
  ///
  /// In en, this message translates to:
  /// **'Steady'**
  String get conditionSteady;

  /// No description provided for @conditionStrained.
  ///
  /// In en, this message translates to:
  /// **'Strained'**
  String get conditionStrained;

  /// No description provided for @conditionRestedHelp.
  ///
  /// In en, this message translates to:
  /// **'You are well recovered. Condition only falls from overexertion — never from missed quests.'**
  String get conditionRestedHelp;

  /// No description provided for @conditionSteadyHelp.
  ///
  /// In en, this message translates to:
  /// **'Recent days have been demanding. A calm day or a rest day restores condition.'**
  String get conditionSteadyHelp;

  /// No description provided for @conditionStrainedHelp.
  ///
  /// In en, this message translates to:
  /// **'You have been pushing very hard. Consider a rest day; your progress is safe.'**
  String get conditionStrainedHelp;

  /// No description provided for @sectionAttributes.
  ///
  /// In en, this message translates to:
  /// **'Attributes'**
  String get sectionAttributes;

  /// No description provided for @sectionToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get sectionToday;

  /// No description provided for @sectionRecentGrowth.
  ///
  /// In en, this message translates to:
  /// **'Recent growth'**
  String get sectionRecentGrowth;

  /// No description provided for @sectionAchievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get sectionAchievements;

  /// No description provided for @sectionConsistency.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get sectionConsistency;

  /// No description provided for @todayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No quests sworn for today.'**
  String get todayEmpty;

  /// No description provided for @todayEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Swear a quest'**
  String get todayEmptyAction;

  /// No description provided for @growthEmpty.
  ///
  /// In en, this message translates to:
  /// **'Complete a quest and your growth will be recorded here.'**
  String get growthEmpty;

  /// No description provided for @achievementsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Achievements mark milestones. Your first one is a single quest away.'**
  String get achievementsEmpty;

  /// No description provided for @classUnrevealed.
  ///
  /// In en, this message translates to:
  /// **'Your class reveals itself at level 5.'**
  String get classUnrevealed;

  /// No description provided for @noTitle.
  ///
  /// In en, this message translates to:
  /// **'No title equipped'**
  String get noTitle;

  /// No description provided for @equipTitle.
  ///
  /// In en, this message translates to:
  /// **'Equip title'**
  String get equipTitle;

  /// No description provided for @weeklyTargetProgress.
  ///
  /// In en, this message translates to:
  /// **'{active} of {target} days this week'**
  String weeklyTargetProgress(String active, String target);

  /// No description provided for @weeksKept.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No weeks kept yet} =1{{countText} week kept} other{{countText} weeks kept}}'**
  String weeksKept(int count, String countText);

  /// No description provided for @chainDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No chain yet} =1{{countText}-day chain} other{{countText}-day chain}}'**
  String chainDays(int count, String countText);

  /// No description provided for @bestRecord.
  ///
  /// In en, this message translates to:
  /// **'Best: {value}'**
  String bestRecord(String value);

  /// No description provided for @levelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get levelLabel;

  /// No description provided for @className_scholar.
  ///
  /// In en, this message translates to:
  /// **'Scholar'**
  String get className_scholar;

  /// No description provided for @className_warden.
  ///
  /// In en, this message translates to:
  /// **'Warden'**
  String get className_warden;

  /// No description provided for @className_artisan.
  ///
  /// In en, this message translates to:
  /// **'Artisan'**
  String get className_artisan;

  /// No description provided for @className_vanguard.
  ///
  /// In en, this message translates to:
  /// **'Vanguard'**
  String get className_vanguard;

  /// No description provided for @className_envoy.
  ///
  /// In en, this message translates to:
  /// **'Envoy'**
  String get className_envoy;

  /// No description provided for @className_druid.
  ///
  /// In en, this message translates to:
  /// **'Druid'**
  String get className_druid;

  /// No description provided for @className_explorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get className_explorer;

  /// No description provided for @className_strategist.
  ///
  /// In en, this message translates to:
  /// **'Strategist'**
  String get className_strategist;

  /// No description provided for @className_arcanist.
  ///
  /// In en, this message translates to:
  /// **'Arcanist'**
  String get className_arcanist;

  /// No description provided for @classDesc_scholar.
  ///
  /// In en, this message translates to:
  /// **'Your recent path has been one of study and understanding.'**
  String get classDesc_scholar;

  /// No description provided for @classDesc_warden.
  ///
  /// In en, this message translates to:
  /// **'You plan, you keep your word, and you hold the line.'**
  String get classDesc_warden;

  /// No description provided for @classDesc_artisan.
  ///
  /// In en, this message translates to:
  /// **'Your hands and mind have been busy making things.'**
  String get classDesc_artisan;

  /// No description provided for @classDesc_vanguard.
  ///
  /// In en, this message translates to:
  /// **'You have been training the body and leading with strength.'**
  String get classDesc_vanguard;

  /// No description provided for @classDesc_envoy.
  ///
  /// In en, this message translates to:
  /// **'You have invested in people and the bonds between them.'**
  String get classDesc_envoy;

  /// No description provided for @classDesc_druid.
  ///
  /// In en, this message translates to:
  /// **'You have tended rest, recovery and wellbeing.'**
  String get classDesc_druid;

  /// No description provided for @classDesc_explorer.
  ///
  /// In en, this message translates to:
  /// **'You have grown in many directions at once.'**
  String get classDesc_explorer;

  /// No description provided for @classDesc_strategist.
  ///
  /// In en, this message translates to:
  /// **'Learning paired with steady execution.'**
  String get classDesc_strategist;

  /// No description provided for @classDesc_arcanist.
  ///
  /// In en, this message translates to:
  /// **'Knowledge turned into creation.'**
  String get classDesc_arcanist;

  /// No description provided for @questsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quests'**
  String get questsTitle;

  /// No description provided for @tabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tabToday;

  /// No description provided for @tabUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get tabUpcoming;

  /// No description provided for @tabContracts.
  ///
  /// In en, this message translates to:
  /// **'Contracts'**
  String get tabContracts;

  /// No description provided for @tabObjectives.
  ///
  /// In en, this message translates to:
  /// **'Objectives'**
  String get tabObjectives;

  /// No description provided for @tabCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tabCompleted;

  /// No description provided for @tierDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily Quest'**
  String get tierDaily;

  /// No description provided for @tierContract.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get tierContract;

  /// No description provided for @tierObjective.
  ///
  /// In en, this message translates to:
  /// **'Long-Term Objective'**
  String get tierObjective;

  /// No description provided for @tierDailyHelp.
  ///
  /// In en, this message translates to:
  /// **'A small, concrete action for today.'**
  String get tierDailyHelp;

  /// No description provided for @tierContractHelp.
  ///
  /// In en, this message translates to:
  /// **'A larger piece of work with steps.'**
  String get tierContractHelp;

  /// No description provided for @tierObjectiveHelp.
  ///
  /// In en, this message translates to:
  /// **'A major goal that quests and contracts build toward.'**
  String get tierObjectiveHelp;

  /// No description provided for @newQuest.
  ///
  /// In en, this message translates to:
  /// **'New quest'**
  String get newQuest;

  /// No description provided for @editQuest.
  ///
  /// In en, this message translates to:
  /// **'Edit quest'**
  String get editQuest;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'What will you do?'**
  String get fieldTitle;

  /// No description provided for @fieldTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Study electronics for 90 minutes'**
  String get fieldTitleHint;

  /// No description provided for @fieldTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the quest a name.'**
  String get fieldTitleRequired;

  /// No description provided for @fieldTooLong.
  ///
  /// In en, this message translates to:
  /// **'Too long. Keep it to {max} characters.'**
  String fieldTooLong(String max);

  /// No description provided for @fieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get fieldNotes;

  /// No description provided for @fieldTier.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get fieldTier;

  /// No description provided for @fieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get fieldCategory;

  /// No description provided for @categoryAuto.
  ///
  /// In en, this message translates to:
  /// **'Decide for me'**
  String get categoryAuto;

  /// No description provided for @category_study.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get category_study;

  /// No description provided for @category_work.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get category_work;

  /// No description provided for @category_fitness.
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get category_fitness;

  /// No description provided for @category_health.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get category_health;

  /// No description provided for @category_creative.
  ///
  /// In en, this message translates to:
  /// **'Creative'**
  String get category_creative;

  /// No description provided for @category_social.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get category_social;

  /// No description provided for @category_chores.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get category_chores;

  /// No description provided for @category_admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get category_admin;

  /// No description provided for @category_mindfulness.
  ///
  /// In en, this message translates to:
  /// **'Mindfulness'**
  String get category_mindfulness;

  /// No description provided for @category_reading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get category_reading;

  /// No description provided for @category_other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get category_other;

  /// No description provided for @fieldDue.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get fieldDue;

  /// No description provided for @fieldDueNone.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get fieldDueNone;

  /// No description provided for @fieldEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated minutes'**
  String get fieldEstimate;

  /// No description provided for @fieldEstimateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter whole minutes from {min} to {max}.'**
  String fieldEstimateInvalid(String min, String max);

  /// No description provided for @fieldIntention.
  ///
  /// In en, this message translates to:
  /// **'When and where will you do it?'**
  String get fieldIntention;

  /// No description provided for @fieldIntentionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. After dinner, at my desk'**
  String get fieldIntentionHint;

  /// No description provided for @fieldIntentionHelp.
  ///
  /// In en, this message translates to:
  /// **'Naming a time and place makes follow-through more likely.'**
  String get fieldIntentionHelp;

  /// No description provided for @fieldReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get fieldReminder;

  /// No description provided for @reminderNone.
  ///
  /// In en, this message translates to:
  /// **'No reminder'**
  String get reminderNone;

  /// No description provided for @reminderBody.
  ///
  /// In en, this message translates to:
  /// **'This quest is ready whenever you are.'**
  String get reminderBody;

  /// No description provided for @reminderClear.
  ///
  /// In en, this message translates to:
  /// **'Remove reminder'**
  String get reminderClear;

  /// No description provided for @fieldRecurrence.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get fieldRecurrence;

  /// No description provided for @recurrenceNone.
  ///
  /// In en, this message translates to:
  /// **'Does not repeat'**
  String get recurrenceNone;

  /// No description provided for @recurrenceDaily.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get recurrenceDaily;

  /// No description provided for @recurrenceWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get recurrenceWeekdays;

  /// No description provided for @recurrenceWeekly.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get recurrenceWeekly;

  /// No description provided for @fieldPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get fieldPriority;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get priorityLow;

  /// No description provided for @priorityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get priorityNormal;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get priorityHigh;

  /// No description provided for @fieldParent.
  ///
  /// In en, this message translates to:
  /// **'Part of an objective'**
  String get fieldParent;

  /// No description provided for @parentNone.
  ///
  /// In en, this message translates to:
  /// **'Standalone'**
  String get parentNone;

  /// No description provided for @fieldSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing with guilds'**
  String get fieldSharing;

  /// No description provided for @share_full.
  ///
  /// In en, this message translates to:
  /// **'Title and reward'**
  String get share_full;

  /// No description provided for @share_titleOnly.
  ///
  /// In en, this message translates to:
  /// **'Title only'**
  String get share_titleOnly;

  /// No description provided for @share_completionOnly.
  ///
  /// In en, this message translates to:
  /// **'Completion only'**
  String get share_completionOnly;

  /// No description provided for @share_private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get share_private;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @swearQuest.
  ///
  /// In en, this message translates to:
  /// **'Swear quest'**
  String get swearQuest;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @deleteQuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this quest?'**
  String get deleteQuestTitle;

  /// No description provided for @deleteQuestBody.
  ///
  /// In en, this message translates to:
  /// **'The quest is removed. Rewards already recorded stay in your chronicle.'**
  String get deleteQuestBody;

  /// No description provided for @questDeleted.
  ///
  /// In en, this message translates to:
  /// **'Quest deleted'**
  String get questDeleted;

  /// No description provided for @questsEmptyToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing sworn for today. One small quest is enough.'**
  String get questsEmptyToday;

  /// No description provided for @questsEmptyUpcoming.
  ///
  /// In en, this message translates to:
  /// **'No upcoming quests.'**
  String get questsEmptyUpcoming;

  /// No description provided for @questsEmptyContracts.
  ///
  /// In en, this message translates to:
  /// **'No contracts yet. Contracts hold larger work with steps.'**
  String get questsEmptyContracts;

  /// No description provided for @questsEmptyObjectives.
  ///
  /// In en, this message translates to:
  /// **'No objectives yet. Objectives give your quests a direction.'**
  String get questsEmptyObjectives;

  /// No description provided for @questsEmptyCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed quests will gather here.'**
  String get questsEmptyCompleted;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dueToday;

  /// No description provided for @dueTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dueTomorrow;

  /// No description provided for @dueYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dueYesterday;

  /// No description provided for @dueEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier date'**
  String get dueEarlier;

  /// No description provided for @estimateMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String estimateMinutes(String minutes);

  /// No description provided for @completeQuest.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get completeQuest;

  /// No description provided for @completedLabel.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completedLabel;

  /// No description provided for @subtasks.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get subtasks;

  /// No description provided for @addSubtask.
  ///
  /// In en, this message translates to:
  /// **'Add step'**
  String get addSubtask;

  /// No description provided for @subtaskHint.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get subtaskHint;

  /// No description provided for @objectiveProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String objectiveProgress(String done, String total);

  /// No description provided for @completeSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Seal this deed'**
  String get completeSheetTitle;

  /// No description provided for @completeSheetMinutes.
  ///
  /// In en, this message translates to:
  /// **'How many minutes did it take?'**
  String get completeSheetMinutes;

  /// No description provided for @completeSheetMinutesHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Honest numbers keep your character honest.'**
  String get completeSheetMinutesHelp;

  /// No description provided for @completeSheetMinutesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter whole minutes, up to {max}.'**
  String completeSheetMinutesInvalid(String max);

  /// No description provided for @completeSheetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Seal'**
  String get completeSheetConfirm;

  /// No description provided for @timerStart.
  ///
  /// In en, this message translates to:
  /// **'Start timer'**
  String get timerStart;

  /// No description provided for @timerStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get timerStop;

  /// No description provided for @timerRunning.
  ///
  /// In en, this message translates to:
  /// **'Timer running · {elapsed}'**
  String timerRunning(String elapsed);

  /// No description provided for @questCompletedToast.
  ///
  /// In en, this message translates to:
  /// **'Deed sealed'**
  String get questCompletedToast;

  /// No description provided for @completionUndone.
  ///
  /// In en, this message translates to:
  /// **'Completion undone'**
  String get completionUndone;

  /// No description provided for @rewardTitle.
  ///
  /// In en, this message translates to:
  /// **'Deed recorded'**
  String get rewardTitle;

  /// No description provided for @rewardProvisional.
  ///
  /// In en, this message translates to:
  /// **'Provisional — will be confirmed when you are online.'**
  String get rewardProvisional;

  /// No description provided for @rewardTotal.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP'**
  String rewardTotal(String xp);

  /// No description provided for @rewardWhy.
  ///
  /// In en, this message translates to:
  /// **'Why this reward?'**
  String get rewardWhy;

  /// No description provided for @rewardSourceAi.
  ///
  /// In en, this message translates to:
  /// **'Interpreted by the oracle, decided by the rules.'**
  String get rewardSourceAi;

  /// No description provided for @rewardSourceHeuristic.
  ///
  /// In en, this message translates to:
  /// **'Interpreted by the rules on this device.'**
  String get rewardSourceHeuristic;

  /// No description provided for @rewardNone.
  ///
  /// In en, this message translates to:
  /// **'No XP this time — the reasons are below.'**
  String get rewardNone;

  /// No description provided for @levelUp.
  ///
  /// In en, this message translates to:
  /// **'Level {level} reached'**
  String levelUp(String level);

  /// No description provided for @rankUp.
  ///
  /// In en, this message translates to:
  /// **'{attribute} reached rank {rank}'**
  String rankUp(String attribute, String rank);

  /// No description provided for @reasonDefault.
  ///
  /// In en, this message translates to:
  /// **'{attribute} grew through {category}.'**
  String reasonDefault(String attribute, String category);

  /// No description provided for @creditedMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes credited'**
  String creditedMinutes(String minutes);

  /// No description provided for @adj_duration_plausibility.
  ///
  /// In en, this message translates to:
  /// **'Credited {credited} of {declared} minutes — longer than this activity usually takes.'**
  String adj_duration_plausibility(String credited, String declared);

  /// No description provided for @adj_tier_minutes_cap.
  ///
  /// In en, this message translates to:
  /// **'A single quest counts up to {cap} minutes.'**
  String adj_tier_minutes_cap(String cap);

  /// No description provided for @adj_daily_budget.
  ///
  /// In en, this message translates to:
  /// **'Today\'s effort budget is full. Rest is part of growth.'**
  String get adj_daily_budget;

  /// No description provided for @adj_tier_bonus.
  ///
  /// In en, this message translates to:
  /// **'{tier} bonus for larger work.'**
  String adj_tier_bonus(String tier);

  /// No description provided for @adj_trivial_floor.
  ///
  /// In en, this message translates to:
  /// **'A very small task counts for a little.'**
  String get adj_trivial_floor;

  /// No description provided for @adj_trivial_limit.
  ///
  /// In en, this message translates to:
  /// **'Today\'s small tasks have already been counted.'**
  String get adj_trivial_limit;

  /// No description provided for @adj_repetition.
  ///
  /// In en, this message translates to:
  /// **'Similar deed #{count} today — repeated effort counts for less.'**
  String adj_repetition(String count);

  /// No description provided for @adj_low_confidence.
  ///
  /// In en, this message translates to:
  /// **'The description was unclear; adding detail gives a fuller reading.'**
  String get adj_low_confidence;

  /// No description provided for @adj_follow_through.
  ///
  /// In en, this message translates to:
  /// **'Planned and kept: a Discipline bonus.'**
  String get adj_follow_through;

  /// No description provided for @adj_follow_through_intention.
  ///
  /// In en, this message translates to:
  /// **'Planned, kept, and you named when and where: a larger Discipline bonus.'**
  String get adj_follow_through_intention;

  /// No description provided for @adj_soft_cap.
  ///
  /// In en, this message translates to:
  /// **'{attribute} is near today\'s limit, so it grows more slowly.'**
  String adj_soft_cap(String attribute);

  /// No description provided for @adj_hard_cap.
  ///
  /// In en, this message translates to:
  /// **'{attribute} has reached today\'s limit. It will grow again tomorrow.'**
  String adj_hard_cap(String attribute);

  /// No description provided for @adj_weights_defaulted.
  ///
  /// In en, this message translates to:
  /// **'Attributes were chosen from the category.'**
  String get adj_weights_defaulted;

  /// No description provided for @achievementUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Achievement: {name}'**
  String achievementUnlocked(String name);

  /// No description provided for @titleUnlocked.
  ///
  /// In en, this message translates to:
  /// **'New title: {title}'**
  String titleUnlocked(String title);

  /// No description provided for @achievement_first_oath_name.
  ///
  /// In en, this message translates to:
  /// **'The First Oath'**
  String get achievement_first_oath_name;

  /// No description provided for @achievement_first_oath_desc.
  ///
  /// In en, this message translates to:
  /// **'Complete your first quest.'**
  String get achievement_first_oath_desc;

  /// No description provided for @achievement_deeds_10_name.
  ///
  /// In en, this message translates to:
  /// **'Ten Deeds'**
  String get achievement_deeds_10_name;

  /// No description provided for @achievement_deeds_10_desc.
  ///
  /// In en, this message translates to:
  /// **'Complete 10 quests.'**
  String get achievement_deeds_10_desc;

  /// No description provided for @achievement_deeds_100_name.
  ///
  /// In en, this message translates to:
  /// **'A Hundred Deeds'**
  String get achievement_deeds_100_name;

  /// No description provided for @achievement_deeds_100_desc.
  ///
  /// In en, this message translates to:
  /// **'Complete 100 quests.'**
  String get achievement_deeds_100_desc;

  /// No description provided for @achievement_deeds_1000_name.
  ///
  /// In en, this message translates to:
  /// **'A Thousand Deeds'**
  String get achievement_deeds_1000_name;

  /// No description provided for @achievement_deeds_1000_desc.
  ///
  /// In en, this message translates to:
  /// **'Complete 1,000 quests.'**
  String get achievement_deeds_1000_desc;

  /// No description provided for @achievement_first_contract_name.
  ///
  /// In en, this message translates to:
  /// **'Contract Sealed'**
  String get achievement_first_contract_name;

  /// No description provided for @achievement_first_contract_desc.
  ///
  /// In en, this message translates to:
  /// **'Complete your first contract.'**
  String get achievement_first_contract_desc;

  /// No description provided for @achievement_first_objective_name.
  ///
  /// In en, this message translates to:
  /// **'The Long Road'**
  String get achievement_first_objective_name;

  /// No description provided for @achievement_first_objective_desc.
  ///
  /// In en, this message translates to:
  /// **'Complete a long-term objective.'**
  String get achievement_first_objective_desc;

  /// No description provided for @achievement_level_5_name.
  ///
  /// In en, this message translates to:
  /// **'Tempered'**
  String get achievement_level_5_name;

  /// No description provided for @achievement_level_5_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach level 5.'**
  String get achievement_level_5_desc;

  /// No description provided for @achievement_level_10_name.
  ///
  /// In en, this message translates to:
  /// **'Seasoned'**
  String get achievement_level_10_name;

  /// No description provided for @achievement_level_10_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach level 10.'**
  String get achievement_level_10_desc;

  /// No description provided for @achievement_level_25_name.
  ///
  /// In en, this message translates to:
  /// **'Veteran'**
  String get achievement_level_25_name;

  /// No description provided for @achievement_level_25_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach level 25.'**
  String get achievement_level_25_desc;

  /// No description provided for @achievement_rank_10_strength_name.
  ///
  /// In en, this message translates to:
  /// **'Iron in the Bones'**
  String get achievement_rank_10_strength_name;

  /// No description provided for @achievement_rank_10_strength_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 10 in Strength.'**
  String get achievement_rank_10_strength_desc;

  /// No description provided for @achievement_rank_10_intelligence_name.
  ///
  /// In en, this message translates to:
  /// **'Keeper of Lore'**
  String get achievement_rank_10_intelligence_name;

  /// No description provided for @achievement_rank_10_intelligence_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 10 in Intelligence.'**
  String get achievement_rank_10_intelligence_desc;

  /// No description provided for @achievement_rank_10_discipline_name.
  ///
  /// In en, this message translates to:
  /// **'Unbending Will'**
  String get achievement_rank_10_discipline_name;

  /// No description provided for @achievement_rank_10_discipline_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 10 in Discipline.'**
  String get achievement_rank_10_discipline_desc;

  /// No description provided for @achievement_rank_10_creativity_name.
  ///
  /// In en, this message translates to:
  /// **'Dreamwright'**
  String get achievement_rank_10_creativity_name;

  /// No description provided for @achievement_rank_10_creativity_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 10 in Creativity.'**
  String get achievement_rank_10_creativity_desc;

  /// No description provided for @achievement_rank_10_vitality_name.
  ///
  /// In en, this message translates to:
  /// **'Evergreen'**
  String get achievement_rank_10_vitality_name;

  /// No description provided for @achievement_rank_10_vitality_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 10 in Vitality.'**
  String get achievement_rank_10_vitality_desc;

  /// No description provided for @achievement_rank_10_social_name.
  ///
  /// In en, this message translates to:
  /// **'Kindred Spirit'**
  String get achievement_rank_10_social_name;

  /// No description provided for @achievement_rank_10_social_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 10 in Social.'**
  String get achievement_rank_10_social_desc;

  /// No description provided for @achievement_kept_weeks_4_name.
  ///
  /// In en, this message translates to:
  /// **'A Month of Oaths'**
  String get achievement_kept_weeks_4_name;

  /// No description provided for @achievement_kept_weeks_4_desc.
  ///
  /// In en, this message translates to:
  /// **'Keep your weekly target four weeks in a row.'**
  String get achievement_kept_weeks_4_desc;

  /// No description provided for @achievement_kept_weeks_12_name.
  ///
  /// In en, this message translates to:
  /// **'Steadfast'**
  String get achievement_kept_weeks_12_name;

  /// No description provided for @achievement_kept_weeks_12_desc.
  ///
  /// In en, this message translates to:
  /// **'Keep your weekly target twelve weeks in a row.'**
  String get achievement_kept_weeks_12_desc;

  /// No description provided for @achievement_kept_weeks_52_name.
  ///
  /// In en, this message translates to:
  /// **'Oathkeeper'**
  String get achievement_kept_weeks_52_name;

  /// No description provided for @achievement_kept_weeks_52_desc.
  ///
  /// In en, this message translates to:
  /// **'Keep your weekly target for a full year.'**
  String get achievement_kept_weeks_52_desc;

  /// No description provided for @achievement_the_return_name.
  ///
  /// In en, this message translates to:
  /// **'The Return'**
  String get achievement_the_return_name;

  /// No description provided for @achievement_the_return_desc.
  ///
  /// In en, this message translates to:
  /// **'Come back after a week away and complete a quest.'**
  String get achievement_the_return_desc;

  /// No description provided for @achievement_balanced_name.
  ///
  /// In en, this message translates to:
  /// **'The Whole'**
  String get achievement_balanced_name;

  /// No description provided for @achievement_balanced_desc.
  ///
  /// In en, this message translates to:
  /// **'Reach rank 3 in every attribute.'**
  String get achievement_balanced_desc;

  /// No description provided for @achievement_hours_100_name.
  ///
  /// In en, this message translates to:
  /// **'A Hundred Hours'**
  String get achievement_hours_100_name;

  /// No description provided for @achievement_hours_100_desc.
  ///
  /// In en, this message translates to:
  /// **'Invest 100 hours of credited effort.'**
  String get achievement_hours_100_desc;

  /// No description provided for @title_sworn.
  ///
  /// In en, this message translates to:
  /// **'the Sworn'**
  String get title_sworn;

  /// No description provided for @title_centurion.
  ///
  /// In en, this message translates to:
  /// **'the Centurion'**
  String get title_centurion;

  /// No description provided for @title_pathfinder.
  ///
  /// In en, this message translates to:
  /// **'the Pathfinder'**
  String get title_pathfinder;

  /// No description provided for @title_seasoned.
  ///
  /// In en, this message translates to:
  /// **'the Seasoned'**
  String get title_seasoned;

  /// No description provided for @title_ironbound.
  ///
  /// In en, this message translates to:
  /// **'the Ironbound'**
  String get title_ironbound;

  /// No description provided for @title_adept_of_lore.
  ///
  /// In en, this message translates to:
  /// **'Adept of Lore'**
  String get title_adept_of_lore;

  /// No description provided for @title_unbending.
  ///
  /// In en, this message translates to:
  /// **'the Unbending'**
  String get title_unbending;

  /// No description provided for @title_dreamwright.
  ///
  /// In en, this message translates to:
  /// **'the Dreamwright'**
  String get title_dreamwright;

  /// No description provided for @title_evergreen.
  ///
  /// In en, this message translates to:
  /// **'the Evergreen'**
  String get title_evergreen;

  /// No description provided for @title_kindred.
  ///
  /// In en, this message translates to:
  /// **'the Kindred'**
  String get title_kindred;

  /// No description provided for @title_steadfast.
  ///
  /// In en, this message translates to:
  /// **'the Steadfast'**
  String get title_steadfast;

  /// No description provided for @title_oathkeeper.
  ///
  /// In en, this message translates to:
  /// **'the Oathkeeper'**
  String get title_oathkeeper;

  /// No description provided for @title_returned.
  ///
  /// In en, this message translates to:
  /// **'the Returned'**
  String get title_returned;

  /// No description provided for @title_whole.
  ///
  /// In en, this message translates to:
  /// **'the Whole'**
  String get title_whole;

  /// No description provided for @chronicleTitle.
  ///
  /// In en, this message translates to:
  /// **'Chronicle'**
  String get chronicleTitle;

  /// No description provided for @periodWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get periodWeek;

  /// No description provided for @periodMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get periodMonth;

  /// No description provided for @periodYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get periodYear;

  /// No description provided for @periodWeekNoun.
  ///
  /// In en, this message translates to:
  /// **'week'**
  String get periodWeekNoun;

  /// No description provided for @periodMonthNoun.
  ///
  /// In en, this message translates to:
  /// **'month'**
  String get periodMonthNoun;

  /// No description provided for @periodYearNoun.
  ///
  /// In en, this message translates to:
  /// **'year'**
  String get periodYearNoun;

  /// No description provided for @comparedToSamePoint.
  ///
  /// In en, this message translates to:
  /// **'{change} vs the same point last period'**
  String comparedToSamePoint(Object change);

  /// No description provided for @previousPeriod.
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get previousPeriod;

  /// No description provided for @nextPeriod.
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get nextPeriod;

  /// No description provided for @statCompletions.
  ///
  /// In en, this message translates to:
  /// **'Deeds'**
  String get statCompletions;

  /// No description provided for @statMinutes.
  ///
  /// In en, this message translates to:
  /// **'Time invested'**
  String get statMinutes;

  /// No description provided for @statXp.
  ///
  /// In en, this message translates to:
  /// **'XP earned'**
  String get statXp;

  /// No description provided for @statActiveDays.
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get statActiveDays;

  /// No description provided for @chartXpByAttribute.
  ///
  /// In en, this message translates to:
  /// **'Growth by attribute'**
  String get chartXpByAttribute;

  /// No description provided for @chartDistribution.
  ///
  /// In en, this message translates to:
  /// **'Where your effort went'**
  String get chartDistribution;

  /// No description provided for @chartConsistency.
  ///
  /// In en, this message translates to:
  /// **'Rhythm'**
  String get chartConsistency;

  /// No description provided for @chronicleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deeds recorded in this period.'**
  String get chronicleEmpty;

  /// No description provided for @writtenChronicle.
  ///
  /// In en, this message translates to:
  /// **'The chronicle'**
  String get writtenChronicle;

  /// No description provided for @chronicleLocalSummary.
  ///
  /// In en, this message translates to:
  /// **'This {period} you completed {count} deeds and invested {time}. {attribute} grew the most.'**
  String chronicleLocalSummary(String period, String count, String time, String attribute);

  /// No description provided for @chronicleNeedsAccount.
  ///
  /// In en, this message translates to:
  /// **'Written chronicles are composed by the oracle and need an account.'**
  String get chronicleNeedsAccount;

  /// No description provided for @ledgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Reward ledger'**
  String get ledgerTitle;

  /// No description provided for @ledgerEmpty.
  ///
  /// In en, this message translates to:
  /// **'Every reward you earn is recorded here with its reasons.'**
  String get ledgerEmpty;

  /// No description provided for @comparedToPrevious.
  ///
  /// In en, this message translates to:
  /// **'{change} vs previous'**
  String comparedToPrevious(String change);

  /// No description provided for @strongestArea.
  ///
  /// In en, this message translates to:
  /// **'Most practiced'**
  String get strongestArea;

  /// No description provided for @quietestArea.
  ///
  /// In en, this message translates to:
  /// **'Least practiced'**
  String get quietestArea;

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String durationHoursMinutes(String hours, String minutes);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(String minutes);

  /// No description provided for @legendActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get legendActive;

  /// No description provided for @legendRest.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get legendRest;

  /// No description provided for @legendQuiet.
  ///
  /// In en, this message translates to:
  /// **'Quiet'**
  String get legendQuiet;

  /// No description provided for @guildsTitle.
  ///
  /// In en, this message translates to:
  /// **'Guilds'**
  String get guildsTitle;

  /// No description provided for @guildsIntro.
  ///
  /// In en, this message translates to:
  /// **'Guilds are small circles of people who encourage each other\'s real-world progress.'**
  String get guildsIntro;

  /// No description provided for @guildsRequireAccount.
  ///
  /// In en, this message translates to:
  /// **'Guilds connect people, so they need an account. Your character and history stay yours.'**
  String get guildsRequireAccount;

  /// No description provided for @guildsBackendMissing.
  ///
  /// In en, this message translates to:
  /// **'Online features are not configured in this build. Everything else works on this device.'**
  String get guildsBackendMissing;

  /// No description provided for @guildsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You are not part of a guild yet.'**
  String get guildsEmpty;

  /// No description provided for @createGuild.
  ///
  /// In en, this message translates to:
  /// **'Found a guild'**
  String get createGuild;

  /// No description provided for @joinGuild.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get joinGuild;

  /// No description provided for @guildName.
  ///
  /// In en, this message translates to:
  /// **'Guild name'**
  String get guildName;

  /// No description provided for @guildDescription.
  ///
  /// In en, this message translates to:
  /// **'What is this guild about?'**
  String get guildDescription;

  /// No description provided for @guildVisibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get guildVisibility;

  /// No description provided for @visibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private — invitation only'**
  String get visibilityPrivate;

  /// No description provided for @visibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'Public — discoverable'**
  String get visibilityPublic;

  /// No description provided for @inviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invitation code'**
  String get inviteCode;

  /// No description provided for @inviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. IRON-PACT-7Q2K'**
  String get inviteCodeHint;

  /// No description provided for @shareInvite.
  ///
  /// In en, this message translates to:
  /// **'Share invitation'**
  String get shareInvite;

  /// No description provided for @guildFeed.
  ///
  /// In en, this message translates to:
  /// **'Hall'**
  String get guildFeed;

  /// No description provided for @guildChallenges.
  ///
  /// In en, this message translates to:
  /// **'Challenges'**
  String get guildChallenges;

  /// No description provided for @guildMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get guildMembers;

  /// No description provided for @feedEmpty.
  ///
  /// In en, this message translates to:
  /// **'The hall is quiet. Completed quests shared with this guild appear here.'**
  String get feedEmpty;

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{countText} member} other{{countText} members}}'**
  String memberCount(int count, String countText);

  /// No description provided for @role_guild_master.
  ///
  /// In en, this message translates to:
  /// **'Guild Master'**
  String get role_guild_master;

  /// No description provided for @role_officer.
  ///
  /// In en, this message translates to:
  /// **'Officer'**
  String get role_officer;

  /// No description provided for @role_member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get role_member;

  /// No description provided for @react_honour.
  ///
  /// In en, this message translates to:
  /// **'Honour'**
  String get react_honour;

  /// No description provided for @react_steel.
  ///
  /// In en, this message translates to:
  /// **'Steel'**
  String get react_steel;

  /// No description provided for @react_flame.
  ///
  /// In en, this message translates to:
  /// **'Flame'**
  String get react_flame;

  /// No description provided for @react_laurel.
  ///
  /// In en, this message translates to:
  /// **'Laurel'**
  String get react_laurel;

  /// No description provided for @commentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Comment} =1{{countText} comment} other{{countText} comments}}'**
  String commentsCount(int count, String countText);

  /// No description provided for @commentHint.
  ///
  /// In en, this message translates to:
  /// **'Write an encouraging word'**
  String get commentHint;

  /// No description provided for @feedCompletedFull.
  ///
  /// In en, this message translates to:
  /// **'{name} completed “{title}” · +{xp} XP'**
  String feedCompletedFull(String name, String title, String xp);

  /// No description provided for @feedCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} completed “{title}”'**
  String feedCompletedTitle(String name, String title);

  /// No description provided for @feedCompletedOnly.
  ///
  /// In en, this message translates to:
  /// **'{name} completed a {tier}'**
  String feedCompletedOnly(String name, String tier);

  /// No description provided for @feedMilestone.
  ///
  /// In en, this message translates to:
  /// **'The guild reached {percent} of “{challenge}”'**
  String feedMilestone(String percent, String challenge);

  /// No description provided for @feedMemberJoined.
  ///
  /// In en, this message translates to:
  /// **'{name} joined the guild'**
  String feedMemberJoined(Object name);

  /// No description provided for @feedChallengeCreated.
  ///
  /// In en, this message translates to:
  /// **'{name} started “{challenge}”'**
  String feedChallengeCreated(Object challenge, Object name);

  /// No description provided for @formerMember.
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get formerMember;

  /// No description provided for @challengeProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} of {target}'**
  String challengeProgress(String current, String target);

  /// No description provided for @challengesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No challenges yet. Officers can start a collective challenge.'**
  String get challengesEmpty;

  /// No description provided for @newChallenge.
  ///
  /// In en, this message translates to:
  /// **'New challenge'**
  String get newChallenge;

  /// No description provided for @challengeTitle.
  ///
  /// In en, this message translates to:
  /// **'Challenge name'**
  String get challengeTitle;

  /// No description provided for @challengeMetricMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes in a category'**
  String get challengeMetricMinutes;

  /// No description provided for @challengeMetricCompletions.
  ///
  /// In en, this message translates to:
  /// **'Number of deeds'**
  String get challengeMetricCompletions;

  /// No description provided for @challengeTarget.
  ///
  /// In en, this message translates to:
  /// **'Collective target'**
  String get challengeTarget;

  /// No description provided for @challengeDays.
  ///
  /// In en, this message translates to:
  /// **'Duration in days'**
  String get challengeDays;

  /// No description provided for @challengeNoPenalty.
  ///
  /// In en, this message translates to:
  /// **'No one is penalised if the target is not reached.'**
  String get challengeNoPenalty;

  /// No description provided for @leaveGuild.
  ///
  /// In en, this message translates to:
  /// **'Leave guild'**
  String get leaveGuild;

  /// No description provided for @muteGuild.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get muteGuild;

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockUser;

  /// No description provided for @reportContent.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportContent;

  /// No description provided for @reportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent to the guild\'s officers and moderators.'**
  String get reportSent;

  /// No description provided for @guildCreated.
  ///
  /// In en, this message translates to:
  /// **'Guild founded'**
  String get guildCreated;

  /// No description provided for @guildJoined.
  ///
  /// In en, this message translates to:
  /// **'Welcome to the guild'**
  String get guildJoined;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionLanguageRegion.
  ///
  /// In en, this message translates to:
  /// **'Language and region'**
  String get sectionLanguageRegion;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @calendarGregorian.
  ///
  /// In en, this message translates to:
  /// **'Gregorian'**
  String get calendarGregorian;

  /// No description provided for @calendarJalali.
  ///
  /// In en, this message translates to:
  /// **'Solar Hijri (Jalali)'**
  String get calendarJalali;

  /// No description provided for @digits.
  ///
  /// In en, this message translates to:
  /// **'Digits'**
  String get digits;

  /// No description provided for @digitsLatin.
  ///
  /// In en, this message translates to:
  /// **'0123456789'**
  String get digitsLatin;

  /// No description provided for @digitsNative.
  ///
  /// In en, this message translates to:
  /// **'Native digits'**
  String get digitsNative;

  /// No description provided for @firstDayOfWeek.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get firstDayOfWeek;

  /// No description provided for @sectionProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get sectionProgress;

  /// No description provided for @weeklyTarget.
  ///
  /// In en, this message translates to:
  /// **'Weekly target'**
  String get weeklyTarget;

  /// No description provided for @weeklyTargetHelp.
  ///
  /// In en, this message translates to:
  /// **'How many active days make a kept week. Set what is realistic, not heroic.'**
  String get weeklyTargetHelp;

  /// No description provided for @weeklyTargetValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{countText} day} other{{countText} days}}'**
  String weeklyTargetValue(int count, String countText);

  /// No description provided for @restDayToday.
  ///
  /// In en, this message translates to:
  /// **'Declare today a rest day'**
  String get restDayToday;

  /// No description provided for @restDayDeclared.
  ///
  /// In en, this message translates to:
  /// **'Today is a rest day. Recovery counts.'**
  String get restDayDeclared;

  /// No description provided for @pauseMode.
  ///
  /// In en, this message translates to:
  /// **'Pause mode'**
  String get pauseMode;

  /// No description provided for @pauseModeHelp.
  ///
  /// In en, this message translates to:
  /// **'For travel, illness or exams. Consistency is frozen and nothing is lost.'**
  String get pauseModeHelp;

  /// No description provided for @sectionMotivation.
  ///
  /// In en, this message translates to:
  /// **'Motivation'**
  String get sectionMotivation;

  /// No description provided for @motivationTone.
  ///
  /// In en, this message translates to:
  /// **'How should encouragement sound?'**
  String get motivationTone;

  /// No description provided for @toneDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct and concise'**
  String get toneDirect;

  /// No description provided for @toneGentle.
  ///
  /// In en, this message translates to:
  /// **'Supportive and gentle'**
  String get toneGentle;

  /// No description provided for @toneAchievement.
  ///
  /// In en, this message translates to:
  /// **'Achievement-focused'**
  String get toneAchievement;

  /// No description provided for @toneAnalytical.
  ///
  /// In en, this message translates to:
  /// **'Analytical'**
  String get toneAnalytical;

  /// No description provided for @motivationDrivers.
  ///
  /// In en, this message translates to:
  /// **'What motivates you most?'**
  String get motivationDrivers;

  /// No description provided for @driverAchievement.
  ///
  /// In en, this message translates to:
  /// **'Achievement'**
  String get driverAchievement;

  /// No description provided for @driverSocial.
  ///
  /// In en, this message translates to:
  /// **'Encouragement from others'**
  String get driverSocial;

  /// No description provided for @driverProgress.
  ///
  /// In en, this message translates to:
  /// **'Visible progress'**
  String get driverProgress;

  /// No description provided for @driverLongTerm.
  ///
  /// In en, this message translates to:
  /// **'Long-term goals'**
  String get driverLongTerm;

  /// No description provided for @driverExploration.
  ///
  /// In en, this message translates to:
  /// **'Exploration and customisation'**
  String get driverExploration;

  /// No description provided for @driverRoutine.
  ///
  /// In en, this message translates to:
  /// **'Structured routines'**
  String get driverRoutine;

  /// No description provided for @motivationPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Used only to adjust tone and suggestions. Change or clear it at any time.'**
  String get motivationPrivacy;

  /// No description provided for @sectionAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get sectionAi;

  /// No description provided for @aiEvaluation.
  ///
  /// In en, this message translates to:
  /// **'Let AI interpret completed quests'**
  String get aiEvaluation;

  /// No description provided for @aiEvaluationHelp.
  ///
  /// In en, this message translates to:
  /// **'When off, rewards come from the built-in rules only.'**
  String get aiEvaluationHelp;

  /// No description provided for @aiLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language for AI explanations'**
  String get aiLanguage;

  /// No description provided for @aiSameAsApp.
  ///
  /// In en, this message translates to:
  /// **'Same as the app'**
  String get aiSameAsApp;

  /// No description provided for @aiTransparency.
  ///
  /// In en, this message translates to:
  /// **'What the AI sees'**
  String get aiTransparency;

  /// No description provided for @aiTransparencyBody.
  ///
  /// In en, this message translates to:
  /// **'Only the completed quest\'s title, notes, kind, category, minutes and parent objective, plus how often you did similar things this week. Never your guilds, other people, or account details. The AI suggests; fixed rules decide and cap every reward.'**
  String get aiTransparencyBody;

  /// No description provided for @aiProvider.
  ///
  /// In en, this message translates to:
  /// **'Your own AI'**
  String get aiProvider;

  /// No description provided for @aiProviderSummaryNone.
  ///
  /// In en, this message translates to:
  /// **'Not set — the built-in rules are used (or the server\'s AI when you\'re signed in).'**
  String get aiProviderSummaryNone;

  /// No description provided for @aiProviderHelp.
  ///
  /// In en, this message translates to:
  /// **'Connect your own Anthropic, OpenAI, Google Gemini or compatible account. Your key stays on this device and is sent only to the provider you choose, which bills you directly.'**
  String get aiProviderHelp;

  /// No description provided for @aiProviderKind.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiProviderKind;

  /// No description provided for @aiProviderAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic (Claude)'**
  String get aiProviderAnthropic;

  /// No description provided for @aiProviderOpenai.
  ///
  /// In en, this message translates to:
  /// **'OpenAI'**
  String get aiProviderOpenai;

  /// No description provided for @aiProviderGemini.
  ///
  /// In en, this message translates to:
  /// **'Google Gemini'**
  String get aiProviderGemini;

  /// No description provided for @aiProviderAnthropicCompatible.
  ///
  /// In en, this message translates to:
  /// **'Anthropic-compatible service'**
  String get aiProviderAnthropicCompatible;

  /// No description provided for @aiProviderOpenaiCompatible.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible service (OpenRouter, Groq, Ollama…)'**
  String get aiProviderOpenaiCompatible;

  /// No description provided for @aiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get aiBaseUrl;

  /// No description provided for @aiBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://openrouter.ai/api/v1'**
  String get aiBaseUrlHint;

  /// No description provided for @aiModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModel;

  /// No description provided for @aiModelHint.
  ///
  /// In en, this message translates to:
  /// **'The model name exactly as your provider lists it'**
  String get aiModelHint;

  /// No description provided for @aiApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiApiKey;

  /// No description provided for @aiApiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'A key is saved on this device. Leave this empty to keep it.'**
  String get aiApiKeySaved;

  /// No description provided for @aiWebKeyNote.
  ///
  /// In en, this message translates to:
  /// **'In the browser, the key is kept in this browser\'s encrypted storage. Prefer a key with a spending limit.'**
  String get aiWebKeyNote;

  /// No description provided for @aiTest.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get aiTest;

  /// No description provided for @aiTestOk.
  ///
  /// In en, this message translates to:
  /// **'Connected — your AI read a sample quest as {category}.'**
  String aiTestOk(String category);

  /// No description provided for @aiTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect: {reason}'**
  String aiTestFailed(String reason);

  /// No description provided for @aiErrAuth.
  ///
  /// In en, this message translates to:
  /// **'the key was rejected'**
  String get aiErrAuth;

  /// No description provided for @aiErrRate.
  ///
  /// In en, this message translates to:
  /// **'too many requests — try again shortly'**
  String get aiErrRate;

  /// No description provided for @aiErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'no connection, or the provider blocks requests from browsers'**
  String get aiErrNetwork;

  /// No description provided for @aiErrRefused.
  ///
  /// In en, this message translates to:
  /// **'the model declined to answer'**
  String get aiErrRefused;

  /// No description provided for @aiErrBadResponse.
  ///
  /// In en, this message translates to:
  /// **'the reply wasn\'t a valid evaluation'**
  String get aiErrBadResponse;

  /// No description provided for @aiErrHttp.
  ///
  /// In en, this message translates to:
  /// **'the provider returned an error ({status})'**
  String aiErrHttp(String status);

  /// No description provided for @aiRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove provider and key'**
  String get aiRemove;

  /// No description provided for @aiSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get aiSaved;

  /// No description provided for @aiInterpreting.
  ///
  /// In en, this message translates to:
  /// **'Your AI is interpreting this deed…'**
  String get aiInterpreting;

  /// No description provided for @aiFallbackUsed.
  ///
  /// In en, this message translates to:
  /// **'Your AI couldn\'t be reached, so the built-in rules were used.'**
  String get aiFallbackUsed;

  /// No description provided for @sectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get sectionNotifications;

  /// No description provided for @notifReminders.
  ///
  /// In en, this message translates to:
  /// **'Quest reminders'**
  String get notifReminders;

  /// No description provided for @notifGuild.
  ///
  /// In en, this message translates to:
  /// **'Guild reactions and comments'**
  String get notifGuild;

  /// No description provided for @notifWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly chronicle'**
  String get notifWeekly;

  /// No description provided for @pushDevice.
  ///
  /// In en, this message translates to:
  /// **'Notifications on this device'**
  String get pushDevice;

  /// No description provided for @pushDeviceOn.
  ///
  /// In en, this message translates to:
  /// **'On. Notifications reach you here even while Wyrd is closed.'**
  String get pushDeviceOn;

  /// No description provided for @pushDeviceOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Allow them so news reaches you while Wyrd is closed.'**
  String get pushDeviceOff;

  /// No description provided for @pushDeviceBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked. Allow notifications for Wyrd in your browser or system settings.'**
  String get pushDeviceBlocked;

  /// No description provided for @pushAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get pushAllow;

  /// No description provided for @pushUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This browser can\'t receive notifications.'**
  String get pushUnsupported;

  /// No description provided for @pushUnsupportedDevice.
  ///
  /// In en, this message translates to:
  /// **'This device can\'t receive notifications.'**
  String get pushUnsupportedDevice;

  /// No description provided for @pushInstallHint.
  ///
  /// In en, this message translates to:
  /// **'On iPhone, add Wyrd to your Home Screen (Share, then Add to Home Screen) and open it from there to get notifications.'**
  String get pushInstallHint;

  /// No description provided for @pushInAppFallback.
  ///
  /// In en, this message translates to:
  /// **'Something new is waiting for you.'**
  String get pushInAppFallback;

  /// No description provided for @pushOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get pushOpen;

  /// No description provided for @pushChannelName.
  ///
  /// In en, this message translates to:
  /// **'Guild and chronicle'**
  String get pushChannelName;

  /// No description provided for @pushChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Reactions, comments and your weekly chronicle.'**
  String get pushChannelDescription;

  /// No description provided for @quietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get quietHours;

  /// No description provided for @quietHoursValue.
  ///
  /// In en, this message translates to:
  /// **'{from} – {to}'**
  String quietHoursValue(String from, String to);

  /// No description provided for @notificationsWebNote.
  ///
  /// In en, this message translates to:
  /// **'In the browser, reminders appear only while the app is open.'**
  String get notificationsWebNote;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @installHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Wyrd to your Home Screen'**
  String get installHintTitle;

  /// No description provided for @installHintBody.
  ///
  /// In en, this message translates to:
  /// **'Tap Share (it may be under •••), then Add to Home Screen. Opened from there, Wyrd runs full screen and can send you notifications.'**
  String get installHintBody;

  /// No description provided for @reducedMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reducedMotion;

  /// No description provided for @reducedEffects.
  ///
  /// In en, this message translates to:
  /// **'Reduce visual effects'**
  String get reducedEffects;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

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

  /// No description provided for @languageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get languageAuto;

  /// No description provided for @languageFollowsDevice.
  ///
  /// In en, this message translates to:
  /// **'Following your device: {language}'**
  String languageFollowsDevice(String language);

  /// No description provided for @deviceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Your device\'s language'**
  String get deviceLanguage;

  /// No description provided for @sectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get sectionAccount;

  /// No description provided for @guestMode.
  ///
  /// In en, this message translates to:
  /// **'Playing as a guest. Your data lives on this device.'**
  String get guestMode;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String signedInAs(String email);

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @authHeadline.
  ///
  /// In en, this message translates to:
  /// **'Keep your legend safe'**
  String get authHeadline;

  /// No description provided for @authIntro.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your character across devices and join guilds. Everything you made as a guest comes with you.'**
  String get authIntro;

  /// No description provided for @authContinueEmail.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get authContinueEmail;

  /// No description provided for @authContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueGoogle;

  /// No description provided for @authContinueGithub.
  ///
  /// In en, this message translates to:
  /// **'Continue with GitHub'**
  String get authContinueGithub;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// No description provided for @authUsePassword.
  ///
  /// In en, this message translates to:
  /// **'Use a password instead'**
  String get authUsePassword;

  /// No description provided for @authUseCode.
  ///
  /// In en, this message translates to:
  /// **'Email me a code instead'**
  String get authUseCode;

  /// No description provided for @authCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authCodeTitle;

  /// No description provided for @authCodeSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}. It works for an hour.'**
  String authCodeSent(String email);

  /// No description provided for @authCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get authCodeLabel;

  /// No description provided for @authPasteCode.
  ///
  /// In en, this message translates to:
  /// **'Paste code'**
  String get authPasteCode;

  /// No description provided for @authVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get authVerify;

  /// No description provided for @authResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get authResend;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'New code in {seconds}s'**
  String authResendIn(String seconds);

  /// No description provided for @authCodeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get authCodeResent;

  /// No description provided for @authChangeEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get authChangeEmail;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authResetTitle;

  /// No description provided for @authResetBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send a 6-digit code to set a new password.'**
  String get authResetBody;

  /// No description provided for @authSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// No description provided for @authNewPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get authNewPasswordTitle;

  /// No description provided for @authNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPassword;

  /// No description provided for @authSavePassword.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get authSavePassword;

  /// No description provided for @authPasswordSaved.
  ///
  /// In en, this message translates to:
  /// **'Password saved. You\'re signed in.'**
  String get authPasswordSaved;

  /// No description provided for @authPasswordRules.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters, with letters and numbers.'**
  String get authPasswordRules;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @authErrEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authErrEmail;

  /// No description provided for @authErrCodeLength.
  ///
  /// In en, this message translates to:
  /// **'Enter all 6 digits.'**
  String get authErrCodeLength;

  /// No description provided for @authErrCode.
  ///
  /// In en, this message translates to:
  /// **'That code is wrong or has expired. Check it, or ask for a new one.'**
  String get authErrCode;

  /// No description provided for @authErrNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first. We\'ve sent you a new code.'**
  String get authErrNotConfirmed;

  /// No description provided for @authErrRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a minute, then try again.'**
  String get authErrRateLimit;

  /// No description provided for @authErrWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password: at least 8 characters, with letters and numbers.'**
  String get authErrWeakPassword;

  /// No description provided for @authErrSamePassword.
  ///
  /// In en, this message translates to:
  /// **'That\'s your current password. Choose a new one.'**
  String get authErrSamePassword;

  /// No description provided for @authErrAccountExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Sign in instead.'**
  String get authErrAccountExists;

  /// No description provided for @authErrProvider.
  ///
  /// In en, this message translates to:
  /// **'This sign-in option isn\'t available right now.'**
  String get authErrProvider;

  /// No description provided for @authErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get authErrNetwork;

  /// No description provided for @authErrCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled.'**
  String get authErrCancelled;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and everything we store for it, then signs you out and clears this device. Your comments in guilds stay, shown as from a former member. This can\'t be undone.'**
  String get deleteAccountBody;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get accountDeleted;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get exportData;

  /// No description provided for @exportReady.
  ///
  /// In en, this message translates to:
  /// **'Your data has been copied as JSON.'**
  String get exportReady;

  /// No description provided for @deleteAllData.
  ///
  /// In en, this message translates to:
  /// **'Delete all data'**
  String get deleteAllData;

  /// No description provided for @deleteAllDataBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your character, quests and history from this device.'**
  String get deleteAllDataBody;

  /// No description provided for @signOutClearDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign out and clear this device'**
  String get signOutClearDevice;

  /// No description provided for @signOutClearDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be signed out and this device forgets your character, quests and history. Everything already synced stays in your account; changes not synced yet are lost.'**
  String get signOutClearDeviceBody;

  /// No description provided for @deviceCleared.
  ///
  /// In en, this message translates to:
  /// **'Signed out. This device no longer holds your data.'**
  String get deviceCleared;

  /// No description provided for @handoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes from another account'**
  String get handoverTitle;

  /// No description provided for @handoverBody.
  ///
  /// In en, this message translates to:
  /// **'{email} has {changes} on this device not yet saved to that account. If you continue, they are removed from this device. To keep them, sign out now, sign in with {email} and let them sync.'**
  String handoverBody(String email, String changes);

  /// No description provided for @handoverBodyNoEmail.
  ///
  /// In en, this message translates to:
  /// **'Another account has {changes} on this device not yet saved to it. If you continue, they are removed from this device. To keep them, sign out now, sign in with that account and let them sync.'**
  String handoverBodyNoEmail(String changes);

  /// No description provided for @handoverOneChange.
  ///
  /// In en, this message translates to:
  /// **'1 change'**
  String get handoverOneChange;

  /// No description provided for @handoverChanges.
  ///
  /// In en, this message translates to:
  /// **'{count} changes'**
  String handoverChanges(String count);

  /// No description provided for @handoverKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep them and sign out'**
  String get handoverKeep;

  /// No description provided for @handoverRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove them and continue'**
  String get handoverRemove;

  /// No description provided for @dataDeleted.
  ///
  /// In en, this message translates to:
  /// **'All data deleted.'**
  String get dataDeleted;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'Source-available under the PolyForm Strict License 1.0.0.'**
  String get aboutLicense;

  /// No description provided for @legalPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get legalPrivacy;

  /// No description provided for @legalTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get legalTerms;

  /// No description provided for @authTitle.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get authTitle;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authInvalid.
  ///
  /// In en, this message translates to:
  /// **'That email and password don\'t match.'**
  String get authInvalid;

  /// No description provided for @authBackendMissing.
  ///
  /// In en, this message translates to:
  /// **'Online features are not configured in this build.'**
  String get authBackendMissing;

  /// No description provided for @onbWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Real effort shapes a character that grows with you — and never loses what it has earned.'**
  String get onbWelcomeBody;

  /// No description provided for @onbChooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get onbChooseLanguage;

  /// No description provided for @onbNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Name your character'**
  String get onbNameTitle;

  /// No description provided for @onbNameHint.
  ///
  /// In en, this message translates to:
  /// **'Character name'**
  String get onbNameHint;

  /// No description provided for @onbSigilTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a sigil'**
  String get onbSigilTitle;

  /// No description provided for @onbAreasTitle.
  ///
  /// In en, this message translates to:
  /// **'What do you want to grow?'**
  String get onbAreasTitle;

  /// No description provided for @onbAreasHelp.
  ///
  /// In en, this message translates to:
  /// **'Pick up to three. You can change this any time.'**
  String get onbAreasHelp;

  /// No description provided for @onbFirstQuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Swear your first quest'**
  String get onbFirstQuestTitle;

  /// No description provided for @onbFirstQuestHelp.
  ///
  /// In en, this message translates to:
  /// **'Something real and small you can do today — or already did.'**
  String get onbFirstQuestHelp;

  /// No description provided for @onbHowItWorksTitle.
  ///
  /// In en, this message translates to:
  /// **'How growth works'**
  String get onbHowItWorksTitle;

  /// No description provided for @onbHowItWorksBody.
  ///
  /// In en, this message translates to:
  /// **'You complete real tasks. An oracle interprets each one; fixed rules decide the reward, cap it fairly, and explain it. Nothing you earn is ever taken away.'**
  String get onbHowItWorksBody;

  /// No description provided for @onbBegin.
  ///
  /// In en, this message translates to:
  /// **'Begin'**
  String get onbBegin;

  /// No description provided for @onbCompleteNow.
  ///
  /// In en, this message translates to:
  /// **'I\'ve done it — seal it now'**
  String get onbCompleteNow;

  /// No description provided for @onbLater.
  ///
  /// In en, this message translates to:
  /// **'I\'ll do it later today'**
  String get onbLater;

  /// No description provided for @suggestStudy.
  ///
  /// In en, this message translates to:
  /// **'Study for 30 minutes'**
  String get suggestStudy;

  /// No description provided for @suggestWalk.
  ///
  /// In en, this message translates to:
  /// **'Take a 20-minute walk'**
  String get suggestWalk;

  /// No description provided for @suggestRead.
  ///
  /// In en, this message translates to:
  /// **'Read 10 pages'**
  String get suggestRead;

  /// No description provided for @suggestCall.
  ///
  /// In en, this message translates to:
  /// **'Call someone you care about'**
  String get suggestCall;

  /// No description provided for @suggestTidy.
  ///
  /// In en, this message translates to:
  /// **'Tidy your workspace for 15 minutes'**
  String get suggestTidy;

  /// No description provided for @suggestCreate.
  ///
  /// In en, this message translates to:
  /// **'Sketch or write for 20 minutes'**
  String get suggestCreate;

  /// No description provided for @returnTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get returnTitle;

  /// No description provided for @returnBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been away for a few days. That\'s okay. Your journey hasn\'t been erased. Choose one small objective and continue.'**
  String get returnBody;

  /// No description provided for @returnAction.
  ///
  /// In en, this message translates to:
  /// **'Choose a small quest'**
  String get returnAction;

  /// No description provided for @jalaliMonth1.
  ///
  /// In en, this message translates to:
  /// **'Farvardin'**
  String get jalaliMonth1;

  /// No description provided for @jalaliMonth2.
  ///
  /// In en, this message translates to:
  /// **'Ordibehesht'**
  String get jalaliMonth2;

  /// No description provided for @jalaliMonth3.
  ///
  /// In en, this message translates to:
  /// **'Khordad'**
  String get jalaliMonth3;

  /// No description provided for @jalaliMonth4.
  ///
  /// In en, this message translates to:
  /// **'Tir'**
  String get jalaliMonth4;

  /// No description provided for @jalaliMonth5.
  ///
  /// In en, this message translates to:
  /// **'Mordad'**
  String get jalaliMonth5;

  /// No description provided for @jalaliMonth6.
  ///
  /// In en, this message translates to:
  /// **'Shahrivar'**
  String get jalaliMonth6;

  /// No description provided for @jalaliMonth7.
  ///
  /// In en, this message translates to:
  /// **'Mehr'**
  String get jalaliMonth7;

  /// No description provided for @jalaliMonth8.
  ///
  /// In en, this message translates to:
  /// **'Aban'**
  String get jalaliMonth8;

  /// No description provided for @jalaliMonth9.
  ///
  /// In en, this message translates to:
  /// **'Azar'**
  String get jalaliMonth9;

  /// No description provided for @jalaliMonth10.
  ///
  /// In en, this message translates to:
  /// **'Dey'**
  String get jalaliMonth10;

  /// No description provided for @jalaliMonth11.
  ///
  /// In en, this message translates to:
  /// **'Bahman'**
  String get jalaliMonth11;

  /// No description provided for @jalaliMonth12.
  ///
  /// In en, this message translates to:
  /// **'Esfand'**
  String get jalaliMonth12;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fa'].contains(locale.languageCode);

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
