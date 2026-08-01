// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Flux Media Server';

  @override
  String get videoTab => 'Video';

  @override
  String get audioTab => 'Audio';

  @override
  String get settings => 'Settings';

  @override
  String get upload => 'Upload';

  @override
  String get search => 'Search';

  @override
  String get searchMedia => 'Search media...';

  @override
  String get noMediaFound => 'No media found';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get retry => 'Retry';

  @override
  String get server => 'Server';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get save => 'Save';

  @override
  String get serverUrlSaved => 'Server URL saved';

  @override
  String get account => 'Account';

  @override
  String get logout => 'Logout';

  @override
  String get loggedOut => 'Logged out';

  @override
  String get language => 'Language';

  @override
  String get downloads => 'Downloads';

  @override
  String get clearCache => 'Clear cache';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get play => 'Play';

  @override
  String get duration => 'Duration';

  @override
  String get mediaDetail => 'Media Detail';

  @override
  String get continueWatching => 'Continue Watching';

  @override
  String get recentlyAdded => 'Recently Added';

  @override
  String get favorites => 'Favorites';

  @override
  String get myCollections => 'My Collections';

  @override
  String get allMovies => 'All Movies';

  @override
  String get likedTracks => 'Liked Tracks';

  @override
  String get artists => 'Artists';

  @override
  String get libraries => 'Libraries';

  @override
  String get noLibrariesYet => 'No libraries yet';

  @override
  String get createLibrary => 'Create Library';

  @override
  String get newLibrary => 'New Library';

  @override
  String get name => 'Name';

  @override
  String get libraryName => 'Library name';

  @override
  String get type => 'Type';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get delete => 'Delete';

  @override
  String get deleteLibrary => 'Delete Library';

  @override
  String get scanning => 'Scanning...';

  @override
  String get scanLibrary => 'Scan library';

  @override
  String deleteLibraryConfirm(String name) {
    return 'Delete \"$name\"? Files on disk will not be removed.';
  }

  @override
  String get scanCompleted => 'Scan completed';

  @override
  String get playbackCompleted => 'Playback completed';

  @override
  String get replay => 'Replay';

  @override
  String get edit => 'Edit';

  @override
  String get download => 'Download';

  @override
  String get addToCollection => 'Add to Collection';

  @override
  String get connect => 'Connect';

  @override
  String get enterServerAddress => 'Enter the server address to connect';

  @override
  String get pleaseEnterServerUrl => 'Please enter the server URL';

  @override
  String get urlMustStartWithHttp => 'URL must start with http:// or https://';

  @override
  String get enterEmailToSignIn => 'Enter your email to sign in';

  @override
  String get email => 'Email';

  @override
  String get pleaseEnterEmail => 'Please enter your email';

  @override
  String get pleaseEnterValidEmail => 'Please enter a valid email';

  @override
  String get getCode => 'Get Code';

  @override
  String get changeServer => 'Change server';

  @override
  String get enterCode => 'Enter Code';

  @override
  String get checkYourEmail => 'Check your email';

  @override
  String sentCodeTo(String email) {
    return 'We sent a code to $email';
  }

  @override
  String debugCodeLabel(String code) {
    return 'Debug code: $code';
  }

  @override
  String get code => 'Code';

  @override
  String get pleaseEnterCode => 'Please enter the code';

  @override
  String get codeMustBe6Digits => 'Code must be 6 digits';

  @override
  String get verify => 'Verify';

  @override
  String get resendCode => 'Resend Code';

  @override
  String get uploadMedia => 'Upload Media';

  @override
  String get selectFiles => 'Select Files';

  @override
  String get noFilesSelected => 'No files selected';

  @override
  String get uploading => 'Uploading...';

  @override
  String get errorLoadingLibraries => 'Error loading libraries';

  @override
  String uploadedOfTotal(int success, int total) {
    return 'Uploaded $success of $total files';
  }

  @override
  String skippedAlreadyExists(int count) {
    return '$count skipped - already exists';
  }

  @override
  String checkingFile(String name) {
    return 'Checking $name...';
  }

  @override
  String ofTotal(int current, int total) {
    return '$current of $total';
  }

  @override
  String filesSkippedOnServer(int count) {
    return '$count file(s) skipped (already on server)';
  }

  @override
  String get errorLoadingLyrics => 'Error loading lyrics';

  @override
  String get noLyricsAvailable => 'No lyrics available';

  @override
  String get errorLoadingTranslation => 'Error loading translation';

  @override
  String get noTranslationAvailable => 'No translation available';

  @override
  String get queueIsEmpty => 'Queue is empty';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get translation => 'Translation';

  @override
  String get queue => 'Queue';

  @override
  String get pictureInPicture => 'Picture in Picture';

  @override
  String get deleteCollection => 'Delete Collection';

  @override
  String deleteCollectionConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get thisCollectionIsEmpty => 'This collection is empty';

  @override
  String get noCollectionsYetCreate => 'No collections yet. Create one first.';

  @override
  String addedToCollection(String name) {
    return 'Added to \"$name\"';
  }

  @override
  String failedToAdd(String error) {
    return 'Failed to add: $error';
  }

  @override
  String get allTracks => 'All Tracks';

  @override
  String downloadedOfTotalTracks(int done, int total) {
    return 'Downloaded $done/$total tracks';
  }

  @override
  String noTracksFoundForArtist(String name) {
    return 'No tracks found for \"$name\"';
  }

  @override
  String get done => 'Done';

  @override
  String get downloading => 'Downloading...';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get errorLabel => 'Error';

  @override
  String get addToQueue => 'Add to Queue';

  @override
  String continueFrom(Object formatted) {
    return 'Continue from $formatted';
  }

  @override
  String get startFromBeginning => 'Start over';

  @override
  String get editMetadata => 'Edit Metadata';

  @override
  String get artist => 'Artist';

  @override
  String get album => 'Album';

  @override
  String get genre => 'Genre';

  @override
  String get year => 'Year';

  @override
  String get details => 'Details';

  @override
  String get addedToQueue => 'Added to queue';
}
