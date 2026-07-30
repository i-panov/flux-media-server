// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Flux Media Server';

  @override
  String get videoTab => 'Видео';

  @override
  String get audioTab => 'Аудио';

  @override
  String get settings => 'Настройки';

  @override
  String get upload => 'Загрузка';

  @override
  String get search => 'Поиск';

  @override
  String get searchMedia => 'Поиск медиа...';

  @override
  String get noMediaFound => 'Медиа не найдено';

  @override
  String get noResultsFound => 'Ничего не найдено';

  @override
  String get retry => 'Повторить';

  @override
  String get server => 'Сервер';

  @override
  String get serverUrl => 'URL сервера';

  @override
  String get save => 'Сохранить';

  @override
  String get serverUrlSaved => 'URL сервера сохранён';

  @override
  String get account => 'Аккаунт';

  @override
  String get logout => 'Выйти';

  @override
  String get loggedOut => 'Вы вышли из системы';

  @override
  String get language => 'Язык';

  @override
  String get downloads => 'Загрузки';

  @override
  String get clearCache => 'Очистить кэш';

  @override
  String get about => 'О приложении';

  @override
  String get version => 'Версия';

  @override
  String get play => 'Воспроизвести';

  @override
  String get duration => 'Длительность';

  @override
  String get mediaDetail => 'Детали медиа';

  @override
  String get continueWatching => 'Продолжить просмотр';

  @override
  String get recentlyAdded => 'Недавно добавлено';

  @override
  String get favorites => 'Избранное';

  @override
  String get myCollections => 'Мои коллекции';

  @override
  String get allMovies => 'Все фильмы';

  @override
  String get likedTracks => 'Любимые треки';

  @override
  String get artists => 'Артисты';

  @override
  String get libraries => 'Библиотеки';

  @override
  String get noLibrariesYet => 'Библиотек пока нет';

  @override
  String get createLibrary => 'Создать библиотеку';

  @override
  String get newLibrary => 'Новая библиотека';

  @override
  String get name => 'Название';

  @override
  String get libraryName => 'Название библиотеки';

  @override
  String get type => 'Тип';

  @override
  String get cancel => 'Отмена';

  @override
  String get create => 'Создать';

  @override
  String get delete => 'Удалить';

  @override
  String get deleteLibrary => 'Удалить библиотеку';

  @override
  String get scanning => 'Сканирование...';

  @override
  String get scanLibrary => 'Сканировать библиотеку';

  @override
  String deleteLibraryConfirm(String name) {
    return 'Удалить \"$name\"? Файлы на диске не будут удалены.';
  }

  @override
  String get scanCompleted => 'Сканирование завершено';

  @override
  String get playbackCompleted => 'Воспроизведение завершено';

  @override
  String get replay => 'Повторить';

  @override
  String get edit => 'Изменить';

  @override
  String get download => 'Скачать';

  @override
  String get addToCollection => 'Добавить в коллекцию';

  @override
  String get connect => 'Подключиться';

  @override
  String get enterServerAddress => 'Введите адрес сервера для подключения';

  @override
  String get pleaseEnterServerUrl => 'Пожалуйста, введите URL сервера';

  @override
  String get urlMustStartWithHttp =>
      'URL должен начинаться с http:// или https://';

  @override
  String get enterEmailToSignIn => 'Введите email для входа';

  @override
  String get email => 'Email';

  @override
  String get pleaseEnterEmail => 'Пожалуйста, введите email';

  @override
  String get pleaseEnterValidEmail => 'Пожалуйста, введите корректный email';

  @override
  String get getCode => 'Получить код';

  @override
  String get changeServer => 'Сменить сервер';

  @override
  String get enterCode => 'Введите код';

  @override
  String get checkYourEmail => 'Проверьте почту';

  @override
  String sentCodeTo(String email) {
    return 'Мы отправили код на $email';
  }

  @override
  String debugCodeLabel(String code) {
    return 'Отладочный код: $code';
  }

  @override
  String get code => 'Код';

  @override
  String get pleaseEnterCode => 'Пожалуйста, введите код';

  @override
  String get codeMustBe6Digits => 'Код должен состоять из 6 цифр';

  @override
  String get verify => 'Проверить';

  @override
  String get resendCode => 'Отправить снова';

  @override
  String get uploadMedia => 'Загрузка медиа';

  @override
  String get selectFiles => 'Выбрать файлы';

  @override
  String get noFilesSelected => 'Файлы не выбраны';

  @override
  String get uploading => 'Загрузка...';

  @override
  String get errorLoadingLibraries => 'Ошибка загрузки библиотек';

  @override
  String uploadedOfTotal(int success, int total) {
    return 'Загружено $success из $total файлов';
  }

  @override
  String skippedAlreadyExists(int count) {
    return '$count пропущено — уже существует';
  }

  @override
  String checkingFile(String name) {
    return 'Проверка $name...';
  }

  @override
  String ofTotal(int current, int total) {
    return '$current из $total';
  }

  @override
  String filesSkippedOnServer(int count) {
    return '$count файл(ов) пропущено (уже на сервере)';
  }

  @override
  String get errorLoadingLyrics => 'Ошибка загрузки текста';

  @override
  String get noLyricsAvailable => 'Текст отсутствует';

  @override
  String get errorLoadingTranslation => 'Ошибка загрузки перевода';

  @override
  String get noTranslationAvailable => 'Перевод отсутствует';

  @override
  String get queueIsEmpty => 'Очередь пуста';

  @override
  String get lyrics => 'Текст';

  @override
  String get translation => 'Перевод';

  @override
  String get queue => 'Очередь';

  @override
  String get pictureInPicture => 'Картинка в картинке';

  @override
  String get deleteCollection => 'Удалить коллекцию';

  @override
  String deleteCollectionConfirm(String name) {
    return 'Вы уверены, что хотите удалить \"$name\"?';
  }

  @override
  String get thisCollectionIsEmpty => 'Эта коллекция пуста';

  @override
  String get noCollectionsYetCreate => 'Коллекций пока нет. Создайте первую.';

  @override
  String addedToCollection(String name) {
    return 'Добавлено в \"$name\"';
  }

  @override
  String failedToAdd(String error) {
    return 'Не удалось добавить: $error';
  }

  @override
  String get allTracks => 'Все треки';

  @override
  String downloadedOfTotalTracks(int done, int total) {
    return 'Загружено $done/$total треков';
  }

  @override
  String noTracksFoundForArtist(String name) {
    return 'Треки не найдены для \"$name\"';
  }

  @override
  String get done => 'Готово';

  @override
  String get downloading => 'Загрузка...';

  @override
  String get downloaded => 'Загружено';

  @override
  String get errorLabel => 'Ошибка';
}
