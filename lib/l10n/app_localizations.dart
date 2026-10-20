import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_tr.dart';

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
    Locale('ar'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale('tr')
  ];

  /// Title of the first onboarding slide, the first screen a new player sees.
  ///
  /// In en, this message translates to:
  /// **'One World, Every Anime'**
  String get onbTitle1;

  /// Text under the first onboarding slide's title.
  ///
  /// In en, this message translates to:
  /// **'Follow, post, and react with fellow fans. Your feed, your fandom.'**
  String get onbBody1;

  /// Title of the second onboarding slide, about the True Fan quizzes.
  ///
  /// In en, this message translates to:
  /// **'Prove You\'re a True Fan'**
  String get onbTitle2;

  /// Text under the second onboarding slide's title. AniGold is the app's coin; keep the name as is.
  ///
  /// In en, this message translates to:
  /// **'Play anime quizzes, race the True Fan leaderboard, and earn AniGold with your daily spin.'**
  String get onbBody2;

  /// Title of the third onboarding slide, about finding other fans.
  ///
  /// In en, this message translates to:
  /// **'Find Your People'**
  String get onbTitle3;

  /// Text under the third onboarding slide's title. A handle is a player's unique @name.
  ///
  /// In en, this message translates to:
  /// **'Search fans by handle, follow them, and message them directly.'**
  String get onbBody3;

  /// Section heading on the Observatory screen for AniSphere's own numbers.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get observatoryCommunity;

  /// Observatory: label under the number of AniSphere members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get observatoryMembers;

  /// Observatory: label under the number of posts made today.
  ///
  /// In en, this message translates to:
  /// **'Posts today'**
  String get observatoryPostsToday;

  /// Observatory: note under the posts-today number explaining when the day starts.
  ///
  /// In en, this message translates to:
  /// **'Posts counted since 00:00 UTC today.'**
  String get observatoryUtcNote;

  /// Section heading on the Observatory screen for anime popularity worldwide, from AniList.
  ///
  /// In en, this message translates to:
  /// **'Global popularity'**
  String get observatoryGlobalTitle;

  /// Observatory: note under the global popularity heading. AniList is the anime database the app uses; keep the name.
  ///
  /// In en, this message translates to:
  /// **'Worldwide totals from AniList — no country breakdown.'**
  String get observatoryGlobalNote;

  /// Observatory: follows a number in each popularity row, as in “1.2M · on AniList lists” — how many AniList users have the anime on a list.
  ///
  /// In en, this message translates to:
  /// **'on AniList lists'**
  String get observatoryOnLists;

  /// Observatory: shown when AniSphere's own numbers fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load community numbers.'**
  String get observatoryStatsError;

  /// Observatory: shown when the global popularity list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load global popularity.'**
  String get observatoryPopularError;

  /// Observatory: shown when the global popularity list comes back empty.
  ///
  /// In en, this message translates to:
  /// **'No popularity data right now.'**
  String get observatoryPopularEmpty;

  /// Discover screen tab that opens today's Community Vote, and the confirm button in the vote dialog.
  ///
  /// In en, this message translates to:
  /// **'Vote'**
  String get vote;

  /// Title of the Community Vote screen, where players vote for an anime each day.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Community Vote'**
  String get communityVoteTitle;

  /// Community Vote: button that opens the anime search to vote.
  ///
  /// In en, this message translates to:
  /// **'Cast a Vote'**
  String get castVote;

  /// Community Vote: label before the votes left today, as in “Votes remaining: 1/2”.
  ///
  /// In en, this message translates to:
  /// **'Votes remaining'**
  String get votesRemaining;

  /// Community Vote: before a countdown to the daily reset, as in “Resets in 3h 12m”.
  ///
  /// In en, this message translates to:
  /// **'Resets in'**
  String get resetsIn;

  /// Community Vote: text in the confirmation dialog before a vote is cast.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get cantBeUndone;

  /// Community Vote: start of the confirmation dialog's title; the app adds the anime title and a question mark, as in “Vote for Frieren?”.
  ///
  /// In en, this message translates to:
  /// **'Vote for'**
  String get voteForConfirm;

  /// Community Vote: shown when the player picks an anime they already voted for today.
  ///
  /// In en, this message translates to:
  /// **'You already voted for this anime today'**
  String get alreadyVotedToday;

  /// Community Vote: shown when the player has used all of today's votes; may be followed by “ · Resets in 3h 12m”.
  ///
  /// In en, this message translates to:
  /// **'No votes left today'**
  String get noVotesLeftToday;

  /// Community Vote: heading over the anime the player voted for today.
  ///
  /// In en, this message translates to:
  /// **'Your Votes Today'**
  String get yourVotesToday;

  /// Community Vote: heading over today's ranking of anime by votes.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Leaderboard'**
  String get todaysLeaderboard;

  /// Community Vote: button that opens the results of earlier days.
  ///
  /// In en, this message translates to:
  /// **'View Past Days'**
  String get viewPastDays;

  /// Title of the screen listing earlier days' Community Vote results.
  ///
  /// In en, this message translates to:
  /// **'Past Community Votes'**
  String get pastVotesTitle;

  /// Community Vote: note that the AniPlus plan gives 4 votes a day. AniPlus is a plan name; keep it.
  ///
  /// In en, this message translates to:
  /// **'AniPlus: 4 votes/day'**
  String get upgradeForVotes;

  /// Community Vote: confirmation after a vote is cast.
  ///
  /// In en, this message translates to:
  /// **'Vote cast! 🎉'**
  String get voteCastSuccess;

  /// Community Vote: shown in today's leaderboard before anyone has voted.
  ///
  /// In en, this message translates to:
  /// **'No votes yet today — be the first!'**
  String get noVotesYetToday;

  /// Shown in place of an anime's title when AniList does not return one, for example on the vote board.
  ///
  /// In en, this message translates to:
  /// **'Title unavailable'**
  String get titleUnavailable;

  /// Discover › Chart: follows a number in each row, as in “18.4K on lists” — how many AniList users have the anime on a list.
  ///
  /// In en, this message translates to:
  /// **'on lists'**
  String get onLists;

  /// Discover › Chart: heading over anime that have no score yet.
  ///
  /// In en, this message translates to:
  /// **'Not scored yet'**
  String get notScoredYet;

  /// Banner across the top of the app when the server could not confirm the player's account; it has Retry and Logout buttons.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your account with the server, so things may not load.'**
  String get sessionUnconfirmed;

  /// Placeholder text in anime search fields (Discover › Search and the Community Vote search).
  ///
  /// In en, this message translates to:
  /// **'Search anime…'**
  String get searchAnimeHint;

  /// Discover › Search: heading over the player's recent searches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// Shown when a search finds nothing; the app adds the search in quotes, as in “No anime found for "frieren"”.
  ///
  /// In en, this message translates to:
  /// **'No anime found for'**
  String get noAnimeFound;

  /// Slogan on the splash screen shown at launch.
  ///
  /// In en, this message translates to:
  /// **'Your World. Your Anime.'**
  String get tagline;

  /// Name of the home feed: bottom navigation tab and side menu entry.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feed;

  /// Name of the Discover screen: bottom navigation tab and side menu entry.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// Name of the watch-party Rooms screen: its title and side menu entry.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get rooms;

  /// Name of the player's profile: bottom navigation tab and the profile screen's title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Name of the short-video section: bottom navigation tab, side menu entry, screen title and a profile tab. “Ani Videos” is a feature name.
  ///
  /// In en, this message translates to:
  /// **'Ani Videos'**
  String get aniVideos;

  /// Side menu entry for the Challenges screen (quizzes and the True Fan challenge).
  ///
  /// In en, this message translates to:
  /// **'Challenges'**
  String get challenges;

  /// Side menu entry for the Seasonal screen (what airs this week).
  ///
  /// In en, this message translates to:
  /// **'Seasonal'**
  String get seasonal;

  /// Side menu entry for the Achievements screen.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// Side menu entry for the Wallet screen, where the player's AniGold coins are.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// Title of the Observatory screen and its side menu entry; it shows community and worldwide anime numbers.
  ///
  /// In en, this message translates to:
  /// **'Observatory'**
  String get observatory;

  /// Side menu entry for the FM Radio screen.
  ///
  /// In en, this message translates to:
  /// **'FM Radio'**
  String get fmRadio;

  /// Side menu entry for the Card Collection screen.
  ///
  /// In en, this message translates to:
  /// **'Card Collection'**
  String get cardCollection;

  /// Side menu entry for the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Name of the player's anime list: side menu entry, screen title and error dialog title. Also used in “Frieren → My List ✅” after adding an anime from a video.
  ///
  /// In en, this message translates to:
  /// **'My List'**
  String get myList;

  /// Button that saves changes (My List entry, Edit Profile).
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Button that closes a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button that acknowledges a message in a dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Edit Profile: label of the display name field (the name shown on the profile, separate from the @handle).
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// Edit Profile: label of the short bio field.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// Shown under the @handle field while the app checks whether the handle is free.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get usernameChecking;

  /// Shown under the @handle field when the handle is free.
  ///
  /// In en, this message translates to:
  /// **'Available ✓'**
  String get usernameAvailable;

  /// Shown under the @handle field when someone already has the handle.
  ///
  /// In en, this message translates to:
  /// **'Already taken'**
  String get usernameTaken;

  /// Shown under the @handle field when it is too short.
  ///
  /// In en, this message translates to:
  /// **'At least 3 characters'**
  String get usernameTooShort;

  /// Shown under the @handle field when it has characters a handle cannot contain.
  ///
  /// In en, this message translates to:
  /// **'Lowercase letters, numbers and _ only'**
  String get usernameInvalid;

  /// Shown under the @handle field when the handle is reserved by the app.
  ///
  /// In en, this message translates to:
  /// **'This name is reserved'**
  String get usernameReserved;

  /// Shown under the @handle field when the availability check fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check — try again'**
  String get usernameCheckFailed;

  /// Title of the sheet every new player sees to choose their @handle.
  ///
  /// In en, this message translates to:
  /// **'Claim your username'**
  String get claimUsernameTitle;

  /// Text on the claim sheet explaining the @handle and the separate display name.
  ///
  /// In en, this message translates to:
  /// **'Pick your unique @handle. Your display name stays separate and can be changed anytime.'**
  String get claimUsernameBody;

  /// Button on the claim sheet that takes the chosen @handle.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get claim;

  /// Button on the claim sheet that closes it without choosing a handle.
  ///
  /// In en, this message translates to:
  /// **'Not now — you can claim later'**
  String get claimLater;

  /// Shown on the claim sheet when taking the handle fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t claim — check your connection and try again'**
  String get usernameClaimFailed;

  /// Edit Profile: button under the avatar; photo upload is not available yet.
  ///
  /// In en, this message translates to:
  /// **'Upload photo (coming soon)'**
  String get uploadPhotoSoon;

  /// Confirmation after Edit Profile saves.
  ///
  /// In en, this message translates to:
  /// **'Profile updated ✅'**
  String get profileUpdated;

  /// Button that tries a failed action again (loading, sending, playing).
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// My List entry: label of the player's own notes about the anime.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// My List entry: label of the watch status (Watching, Completed…).
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// My List: label under the number of anime on the list.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// Button that removes an anime from My List.
  ///
  /// In en, this message translates to:
  /// **'Remove from List'**
  String get removeFromList;

  /// Title of an empty state: My List with nothing on it, a hashtag with no posts, or a people search with no results.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyListTitle;

  /// Text under an empty My List, inviting the player to add anime.
  ///
  /// In en, this message translates to:
  /// **'Add anime to get started'**
  String get emptyListBody;

  /// My List: label of the number of episodes the player has watched.
  ///
  /// In en, this message translates to:
  /// **'Episodes watched'**
  String get episodesWatched;

  /// My List: label of the player's own score for the anime.
  ///
  /// In en, this message translates to:
  /// **'Your score'**
  String get yourScore;

  /// My List entry: before the date the entry last changed, as in “Last updated: Oct 20, 2026 · 14:05”.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdated;

  /// Shown when adding to, changing or removing from My List fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your list. Try again.'**
  String get listError;

  /// Sign-in screen: button that starts the app with a guest profile.
  ///
  /// In en, this message translates to:
  /// **'Continue as Guest'**
  String get continueAsGuest;

  /// Confirmation after continuing as a guest; the app adds “ · ” and the account's id.
  ///
  /// In en, this message translates to:
  /// **'Signed in as guest'**
  String get guestSignedIn;

  /// Sign-in screen: shown when continuing as a guest fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign in. Try again.'**
  String get guestError;

  /// Title of the direct messages screen.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// Title of the language picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// Button that opens account sign-up (onboarding and sign-in screens).
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// Title of the sign-in screen and its button; also shown on a profile that cannot load because no one is signed in.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// Onboarding: button that skips the remaining slides.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Onboarding: button that moves to the next slide.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Sign-up: button that moves to the next step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// Sign-up: button on the last step.
  ///
  /// In en, this message translates to:
  /// **'Finish Setup'**
  String get finishSetup;

  /// Sign-in and sign-up: label of the email field.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Label of the @handle field (sign-up, Edit Profile and the claim sheet).
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Sign-in and sign-up: label of the password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Sign-up: label of the date-of-birth field.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get dateOfBirth;

  /// Sign-up: name of the first step (email, handle, password).
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// Sign-up: name of the step where the player picks anime they like.
  ///
  /// In en, this message translates to:
  /// **'Pick Anime'**
  String get pickAnime;

  /// Sign-up: name of the last step.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// Sign-up: question about the first anime the player watched.
  ///
  /// In en, this message translates to:
  /// **'Your first anime ever?'**
  String get firstAnimeEver;

  /// Sign-up: question over a choice of genres.
  ///
  /// In en, this message translates to:
  /// **'What do you enjoy?'**
  String get whatYouEnjoy;

  /// Sign-up: title of the dialog shown to players under the minimum age.
  ///
  /// In en, this message translates to:
  /// **'Age Restriction ⚠️'**
  String get ageRestriction;

  /// Sign-up: text of the minimum-age dialog.
  ///
  /// In en, this message translates to:
  /// **'AniSphere requires users to be 14 or older.'**
  String get ageRestrictionBody;

  /// Sign-up: button in the minimum-age dialog that leaves sign-up.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// Button that follows another player.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// Label under the number of players someone follows, the title of that list, and the follow button's state once following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// Label under the number of followers, and the title of the followers list. Also follows a number in Discover's people results, as in “1.2K Followers”.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// Profile button that opens a direct message with the player.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// Button on the player's own profile, and the title of the sheet it opens.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// Ani Videos: action beside a video that shares it.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Cover over a post, video or message marked as a spoiler.
  ///
  /// In en, this message translates to:
  /// **'Spoiler — tap to reveal'**
  String get spoiler;

  /// Heading for players' stories (short-lived photo posts).
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get stories;

  /// First item in the stories row; it starts a new story.
  ///
  /// In en, this message translates to:
  /// **'Add Story'**
  String get addStory;

  /// Title of the Trending screen, its side menu entry, a Discover tab, a feed heading (“🔥 Trending”), and a button on an empty My List.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trending;

  /// Title of the anime News screen (“📰 News”) and the name of its general news category.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get news;

  /// Discover screen tab for searching anime.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Placeholder in the anime picker used when tagging an anime on a post or Ani Video.
  ///
  /// In en, this message translates to:
  /// **'Search anime, users, posts…'**
  String get searchHint;

  /// Button on an anime's page that adds it to My List.
  ///
  /// In en, this message translates to:
  /// **'Add to List'**
  String get addToList;

  /// Watch status and My List tab: anime the player is watching.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get watching;

  /// Watch status and My List tab: anime the player has finished.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// Watch status and My List tab: anime the player plans to watch.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get planning;

  /// Watch status: anime the player has paused.
  ///
  /// In en, this message translates to:
  /// **'On Hold'**
  String get onHold;

  /// Watch status and My List count: anime the player stopped watching.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get dropped;

  /// Follows the number of episodes an anime has, as in “12 Episodes”, on its My List page.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodes;

  /// Label under the number of posts on a profile, and the profile's Posts tab.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get posts;

  /// Wallet screen tab: ways to earn AniGold.
  ///
  /// In en, this message translates to:
  /// **'Earn'**
  String get earn;

  /// Wallet screen tab: what AniGold can buy.
  ///
  /// In en, this message translates to:
  /// **'Spend'**
  String get spend;

  /// Wallet screen tab for buying more currency.
  ///
  /// In en, this message translates to:
  /// **'Recharge'**
  String get recharge;

  /// Filter that shows everything: the My List tab and the News category chip.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Button that signs the player out (on the banner shown when the account could not be confirmed).
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// Sign-up: label of the language choice.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Title of the screen for writing a post.
  ///
  /// In en, this message translates to:
  /// **'New Post'**
  String get newPost;

  /// Badge text for a verified player.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// Button that publishes a post or an Ani Video.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get post;

  /// Confirmation after a post is published.
  ///
  /// In en, this message translates to:
  /// **'Posted!'**
  String get posted;

  /// Placeholder in the box where a post is written.
  ///
  /// In en, this message translates to:
  /// **'Share your anime thoughts…'**
  String get newPostHint;

  /// New Post: button that adds images.
  ///
  /// In en, this message translates to:
  /// **'Add Image'**
  String get addImage;

  /// New Post and Ani Video upload: button that tags the anime the post is about.
  ///
  /// In en, this message translates to:
  /// **'Tag Anime'**
  String get tagAnime;

  /// New Post and Ani Video upload: switch that marks the post as a spoiler.
  ///
  /// In en, this message translates to:
  /// **'Mark as spoiler'**
  String get markAsSpoiler;

  /// Feed: shown when there are no posts from followed players.
  ///
  /// In en, this message translates to:
  /// **'No posts yet. Follow users to see their posts!'**
  String get noPostsYet;

  /// Profile › Posts tab: shown when the player has no posts.
  ///
  /// In en, this message translates to:
  /// **'No posts yet.'**
  String get profileNoPosts;

  /// Profile › Ani Videos tab: shown when the player has no videos.
  ///
  /// In en, this message translates to:
  /// **'No videos yet.'**
  String get profileNoVideos;

  /// Title of the comments under a post or Ani Video.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// Shown when a post or video has no comments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet — be the first!'**
  String get noCommentsYet;

  /// Placeholder in the comment box.
  ///
  /// In en, this message translates to:
  /// **'Add a comment…'**
  String get addCommentHint;

  /// Post menu action, and the title and confirm button of its confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Post'**
  String get deletePost;

  /// Post menu action that reports the post.
  ///
  /// In en, this message translates to:
  /// **'Report Post'**
  String get reportPost;

  /// Confirmation after a post is deleted.
  ///
  /// In en, this message translates to:
  /// **'Post deleted'**
  String get postDeleted;

  /// Confirmation after a post, video or message is reported.
  ///
  /// In en, this message translates to:
  /// **'Report received. Thank you!'**
  String get postReported;

  /// Shown when publishing a post fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t publish your post. Try again.'**
  String get postFailed;

  /// New Post: shown when the player tries to add more images than allowed.
  ///
  /// In en, this message translates to:
  /// **'You can add up to 3 images.'**
  String get maxImagesNote;

  /// New Post: shown when an image cannot be prepared for upload.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare an image for upload. Try a different image.'**
  String get imageTooLarge;

  /// General message when an action fails (liking, deleting, reporting…).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get actionFailed;

  /// Shown when the feed or a hashtag's posts fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the feed.'**
  String get loadFeedError;

  /// Title of the list of reasons when reporting a post.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this post?'**
  String get whyReport;

  /// Title of the list of reasons when reporting a player from a chat.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this user?'**
  String get whyReportUser;

  /// Title of the list of reasons when reporting a chat message.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this message?'**
  String get whyReportMessage;

  /// Second line of an error, asking the player to check their connection.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get checkConnection;

  /// Name shown in messages for a player who has no display name.
  ///
  /// In en, this message translates to:
  /// **'Anime fan'**
  String get animeFanFallback;

  /// Shown in an empty chat, and as the preview of a conversation with no messages.
  ///
  /// In en, this message translates to:
  /// **'Say hi 👋'**
  String get sayHi;

  /// Settings entry and screen title for the conversations the player has blocked.
  ///
  /// In en, this message translates to:
  /// **'Block List'**
  String get blockList;

  /// Block List button, and chat menu action, that unblocks a conversation.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// Chat menu action that blocks the conversation.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// Messages screen: shown when the conversation list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Messages are unavailable right now.'**
  String get dmListError;

  /// Messages screen: title when there are no conversations.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// Messages screen: text under “No messages yet”.
  ///
  /// In en, this message translates to:
  /// **'Conversations you start will show up here.'**
  String get noMessagesYetCaption;

  /// Block List: shown when the list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Block list unavailable'**
  String get blockListError;

  /// Block List: title when nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'No blocked conversations'**
  String get noBlockedConversations;

  /// Block List: text under “No blocked conversations”.
  ///
  /// In en, this message translates to:
  /// **'People you block from a chat will appear here.'**
  String get noBlockedConversationsCaption;

  /// Block List: shown on the button while unblocking.
  ///
  /// In en, this message translates to:
  /// **'Unblocking…'**
  String get unblocking;

  /// Chat: shown when a message is waiting for the connection to come back.
  ///
  /// In en, this message translates to:
  /// **'Still sending — it will go out once you\'re back online.'**
  String get stillSending;

  /// Chat: shown when a message fails to send.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send that message.'**
  String get sendMessageFailed;

  /// Chat: shown when a photo fails to send.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send that photo.'**
  String get sendPhotoFailed;

  /// Chat: confirmation after blocking the conversation.
  ///
  /// In en, this message translates to:
  /// **'Conversation blocked'**
  String get conversationBlocked;

  /// Chat: confirmation after unblocking the conversation.
  ///
  /// In en, this message translates to:
  /// **'Conversation unblocked'**
  String get conversationUnblocked;

  /// Chat: shown when the player tries to react in a blocked conversation.
  ///
  /// In en, this message translates to:
  /// **'Reactions are unavailable while this conversation is blocked.'**
  String get reactionsBlocked;

  /// Chat: action on a message that reports it.
  ///
  /// In en, this message translates to:
  /// **'Report message'**
  String get reportMessage;

  /// Chat menu action that reports the other player.
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get reportUser;

  /// Chat: shown when the conversation cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'This conversation is unavailable.'**
  String get conversationUnavailable;

  /// Chat: placeholder in the message box.
  ///
  /// In en, this message translates to:
  /// **'Message…'**
  String get messageHint;

  /// Chat: title of the notice that replaces the message box in a blocked conversation.
  ///
  /// In en, this message translates to:
  /// **'This conversation is blocked'**
  String get conversationIsBlocked;

  /// Settings button, and title of the screen, for deleting the account.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// Delete account screen: first paragraph.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your AniSphere account and everything you made here.'**
  String get deleteAccountLead;

  /// Delete account screen: heading over what is deleted.
  ///
  /// In en, this message translates to:
  /// **'What is deleted'**
  String get deleteWhatGoes;

  /// Delete account screen: item under “What is deleted”.
  ///
  /// In en, this message translates to:
  /// **'Your profile, posts, videos, stories and comments'**
  String get deleteGoesContent;

  /// Delete account screen: item under “What is deleted”.
  ///
  /// In en, this message translates to:
  /// **'Your likes, follows, votes and the messages you sent'**
  String get deleteGoesActivity;

  /// Delete account screen: item under “What is deleted”. AniGold is the app's coin.
  ///
  /// In en, this message translates to:
  /// **'Your AniGold, items and leaderboard entries'**
  String get deleteGoesWallet;

  /// Delete account screen: heading over what is kept.
  ///
  /// In en, this message translates to:
  /// **'What stays'**
  String get deleteWhatStays;

  /// Delete account screen: item under “What stays”.
  ///
  /// In en, this message translates to:
  /// **'People you messaged keep their side of those conversations.'**
  String get deleteOthersKeep;

  /// Delete account screen: item under “What stays”, about the @handle.
  ///
  /// In en, this message translates to:
  /// **'Your @handle is retired forever. No one can take it — including you.'**
  String get deleteHandleRetired;

  /// Delete account screen: heading over the timing.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get deleteWhen;

  /// Delete account screen: item under “When”.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be signed out now. Removal finishes within about an hour.'**
  String get deleteTiming;

  /// Delete account screen: warning above the confirmation field.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get deleteIrreversible;

  /// Delete account screen: label of the field where the player types the confirmation word. The app checks for the English word DELETE, so keep “DELETE” in Latin capitals.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get deleteTypeToConfirm;

  /// Delete account screen: the final button.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccountButton;

  /// Delete account screen: shown while the deletion is in progress.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account…'**
  String get deletingAccount;

  /// Delete account screen: shown when the deletion was refused and nothing changed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Nothing was changed — try again.'**
  String get deleteFailedNothingChanged;

  /// Delete account screen: shown when the server could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach AniSphere. Nothing was changed — check your connection and try again.'**
  String get deleteFailedUnreachable;

  /// Delete account screen: shown when the app could not tell whether the deletion went through.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t confirm the deletion. Check your connection and try again — trying again is safe.'**
  String get deleteFailedUnsure;

  /// Shown on the onboarding screen after the player is signed out and the deletion has started.
  ///
  /// In en, this message translates to:
  /// **'Your account is being deleted.'**
  String get accountDeletionStarted;

  /// Title of the dialog shown when a guest player signs out.
  ///
  /// In en, this message translates to:
  /// **'Sign out of a guest account?'**
  String get guestSignOutTitle;

  /// Text of the guest sign-out dialog.
  ///
  /// In en, this message translates to:
  /// **'Guest accounts can\'t be signed back into. Your posts and messages would stay online with no way to remove them.'**
  String get guestSignOutBody;

  /// Button in the guest sign-out dialog that signs out.
  ///
  /// In en, this message translates to:
  /// **'Sign out anyway'**
  String get signOutAnyway;

  /// Onboarding: button on the last slide.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// Sign-in screen: heading explaining that the app starts with a guest profile.
  ///
  /// In en, this message translates to:
  /// **'Start as a guest'**
  String get guestIntroTitle;

  /// Sign-in screen: text under “Start as a guest”.
  ///
  /// In en, this message translates to:
  /// **'AniSphere doesn\'t have accounts you sign into with an email or password yet. Continuing gives you a guest profile on this device — or picks up the one it already has.'**
  String get guestIntroBody;

  /// Sign-in screen: warning about signing out of a guest profile.
  ///
  /// In en, this message translates to:
  /// **'A guest profile can\'t be signed back into. If you sign out, you can\'t return to it, and anything you posted stays online.'**
  String get guestIntroWarning;

  /// Name shown in messages for a player whose account was deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted account'**
  String get deletedAccount;

  /// Chat: notice that the other player's account was deleted.
  ///
  /// In en, this message translates to:
  /// **'This account no longer exists.'**
  String get accountNoLongerExists;

  /// Chat: text under “This conversation is blocked”.
  ///
  /// In en, this message translates to:
  /// **'Messages can\'t be sent or received right now.'**
  String get conversationBlockedCaption;

  /// Title of the list of reasons when reporting an Ani Video.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this video?'**
  String get whyReportVideo;

  /// Report reason: spam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportSpam;

  /// Report reason: a spoiler that was not marked as one.
  ///
  /// In en, this message translates to:
  /// **'Untagged spoiler'**
  String get reportSpoiler;

  /// Report reason: harassment or abuse.
  ///
  /// In en, this message translates to:
  /// **'Harassment or abuse'**
  String get reportAbuse;

  /// Report reason: anything else.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportOther;

  /// Discover screen tab for finding other players.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// Discover › People: heading over suggested players.
  ///
  /// In en, this message translates to:
  /// **'Suggested For You'**
  String get suggestedForYou;

  /// Discover › People: shown when there are no more suggestions.
  ///
  /// In en, this message translates to:
  /// **'No more suggestions'**
  String get noSuggestions;

  /// Followers list: shown when the player has no followers.
  ///
  /// In en, this message translates to:
  /// **'No followers yet'**
  String get noFollowersYet;

  /// Following list: shown when the player follows no one.
  ///
  /// In en, this message translates to:
  /// **'Not following anyone yet'**
  String get notFollowingAnyone;

  /// Shown when a profile cannot be found.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// Placeholder in fields that search players by handle (Discover › People, story mentions).
  ///
  /// In en, this message translates to:
  /// **'Search users…'**
  String get searchUsers;

  /// Label for the number of likes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get likes;

  /// Feed: heading over the week's popular posts (“🔥 Popular This Week”).
  ///
  /// In en, this message translates to:
  /// **'Popular This Week'**
  String get popularThisWeek;

  /// Feed: title of the notice shown when the player follows no one.
  ///
  /// In en, this message translates to:
  /// **'Follow users to see posts in your Feed!'**
  String get emptyFeedFollow;

  /// Feed: text under “Follow users to see posts in your Feed!”.
  ///
  /// In en, this message translates to:
  /// **'Start following to customize your Feed'**
  String get startFollowingHint;

  /// News screen: shown when there are no articles.
  ///
  /// In en, this message translates to:
  /// **'No news yet'**
  String get noNewsYet;

  /// News article: button that opens the original article.
  ///
  /// In en, this message translates to:
  /// **'Read on source'**
  String get readOnSource;

  /// News article: heading over the anime the article is about.
  ///
  /// In en, this message translates to:
  /// **'Related Anime'**
  String get relatedAnime;

  /// News category: announcements.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get catAnnouncement;

  /// News category: news about a new season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get catSeason;

  /// News category: movies.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get catMovie;

  /// News category: collaborations.
  ///
  /// In en, this message translates to:
  /// **'Collab'**
  String get catCollab;

  /// News category: events.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get catEvent;

  /// Ani Videos: title of the upload screen and the button that opens it.
  ///
  /// In en, this message translates to:
  /// **'Upload a video'**
  String get uploadVideo;

  /// Upload screen: the length limit. The number must match the app's limit; the app may add “  ·  37s”, the picked video's length.
  ///
  /// In en, this message translates to:
  /// **'Max 120 seconds'**
  String get maxVideoDuration;

  /// Upload screen: shown when the picked video is longer than the limit. The number must match the app's limit.
  ///
  /// In en, this message translates to:
  /// **'Video is too long — max 120 seconds'**
  String get videoTooLong;

  /// Upload screen: button that picks a video from the phone.
  ///
  /// In en, this message translates to:
  /// **'Pick from gallery'**
  String get pickFromGallery;

  /// Upload screen: button that records a video with the camera.
  ///
  /// In en, this message translates to:
  /// **'Record a video'**
  String get recordVideo;

  /// Upload screen: placeholder in the caption box.
  ///
  /// In en, this message translates to:
  /// **'Write a caption…'**
  String get captionHint;

  /// Upload screen: shown during upload; the app adds the progress, as in “Uploading… 45%”.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// Confirmation after a video is published.
  ///
  /// In en, this message translates to:
  /// **'Video posted!'**
  String get videoPosted;

  /// Shown when a video upload fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload your video. Try again.'**
  String get videoUploadFailed;

  /// Ani Videos: shown when there are no videos.
  ///
  /// In en, this message translates to:
  /// **'No videos yet — upload the first!'**
  String get noVideosYet;

  /// Shown when videos fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load videos.'**
  String get videosLoadError;

  /// Shown over a video that failed to play; a Retry button follows.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this video.'**
  String get videoPlayFailed;

  /// Shown over a video that cannot be played at all.
  ///
  /// In en, this message translates to:
  /// **'This video can\'t be played.'**
  String get videoUnplayable;

  /// Video menu action, and the title and confirm button of its confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete video'**
  String get deleteVideo;

  /// Confirmation after a video is deleted.
  ///
  /// In en, this message translates to:
  /// **'Video deleted'**
  String get videoDeleted;

  /// Video menu action that reports the video.
  ///
  /// In en, this message translates to:
  /// **'Report video'**
  String get reportVideo;

  /// Title of the Seasonal screen, which lists the episodes airing this week.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get thisWeek;

  /// Seasonal: added to today's day heading, as in “Tue · Today”.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Seasonal: short for “episode” before its number, as in “Ep 12 · 18:00”. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Ep'**
  String get epShort;

  /// Seasonal: shown when nothing airs this week.
  ///
  /// In en, this message translates to:
  /// **'No episodes airing this week.'**
  String get noEpisodesThisWeek;

  /// Seasonal: shown when the week's schedule fails to load. Two lines.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this week\'s schedule.\nCheck your connection and try again.'**
  String get weekScheduleError;

  /// Seasonal: short name for Monday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get dayMon;

  /// Seasonal: short name for Tuesday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get dayTue;

  /// Seasonal: short name for Wednesday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get dayWed;

  /// Seasonal: short name for Thursday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get dayThu;

  /// Seasonal: short name for Friday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get dayFri;

  /// Seasonal: short name for Saturday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get daySat;

  /// Seasonal: short name for Sunday, used as a day heading.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get daySun;

  /// Name of the winter anime season (January–March), as in “❄️ Winter 2026”.
  ///
  /// In en, this message translates to:
  /// **'Winter'**
  String get seasonWinter;

  /// Name of the spring anime season (April–June), as in “🌸 Spring 2026”.
  ///
  /// In en, this message translates to:
  /// **'Spring'**
  String get seasonSpring;

  /// Name of the summer anime season (July–September), as in “☀️ Summer 2026”.
  ///
  /// In en, this message translates to:
  /// **'Summer'**
  String get seasonSummer;

  /// Name of the fall anime season (October–December), as in “🍂 Fall 2026”.
  ///
  /// In en, this message translates to:
  /// **'Fall'**
  String get seasonFall;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'en',
        'es',
        'fr',
        'id',
        'ja',
        'ko',
        'tr'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'id':
      return AppLocalizationsId();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
