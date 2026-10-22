// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Flux';

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
  String get downloads => 'Офлайн';

  @override
  String get saveOffline => 'В офлайн';

  @override
  String get saveFile => 'Скачать';

  @override
  String get preparingFile => 'Готовим файл...';

  @override
  String get fileSaved => 'Файл сохранён';

  @override
  String get saveNotSupported =>
      'Сохранение не поддерживается на этой платформе';

  @override
  String fileSaveFailed(String error) {
    return 'Не удалось сохранить: $error';
  }

  @override
  String get clearCache => 'Очистить кэш';

  @override
  String get about => 'О приложении';

  @override
  String get clientVersion => 'Версия клиента';

  @override
  String get serverVersion => 'Версия сервера';

  @override
  String get play => 'Воспроизвести';

  @override
  String get previous => 'Предыдущий';

  @override
  String get next => 'Следующий';

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
  String get deleteMediaConfirmation =>
      'Удалить этот медиафайл без возможности восстановления?';

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
  String get addToCollection => 'Добавить в коллекцию';

  @override
  String get selectCollection => 'Выбрать коллекцию';

  @override
  String get newCollection => 'Новая коллекция';

  @override
  String get collection => 'Коллекция';

  @override
  String selectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String bulkAddedToCollection(String name, int count, int skipped) {
    return 'В «$name» добавлено $count, пропущено $skipped';
  }

  @override
  String bulkMovedToCollection(String name, int count, int skipped) {
    return 'В «$name» перенесено $count, пропущено $skipped';
  }

  @override
  String get noCollection => 'Без коллекции';

  @override
  String failedToAddToCollection(int count) {
    return 'Не удалось добавить в коллекцию: $count';
  }

  @override
  String createdCollection(String name) {
    return 'Создана коллекция \"$name\"';
  }

  @override
  String failedToCreate(String error) {
    return 'Не удалось создать: $error';
  }

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
  String selectedFiles(int count) {
    return 'Выбрано файлов: $count';
  }

  @override
  String get uploadFailed => 'Ошибка загрузки';

  @override
  String get queued => 'В очереди';

  @override
  String uploadBatchSummary(int done, int total, int duplicates, int failed) {
    return 'Загружено $done из $total (дубли: $duplicates, ошибки: $failed)';
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
  String deleteCollectionCascadeConfirm(String name, int count) {
    return 'Удалить \"$name\" вместе с подколлекциями ($count)?';
  }

  @override
  String get noCollectionsYetCreate => 'Коллекций пока нет. Создайте первую.';

  @override
  String addedToCollection(String name) {
    return 'Добавлено в \"$name\"';
  }

  @override
  String removedFromCollection(String name) {
    return 'Удалено из \"$name\"';
  }

  @override
  String failedToAdd(String error) {
    return 'Не удалось добавить: $error';
  }

  @override
  String get allTracks => 'Все треки';

  @override
  String downloadedOfTotalTracks(int done, int total) {
    return 'Сохранено $done/$total треков';
  }

  @override
  String noTracksFoundForArtist(String name) {
    return 'Треки не найдены для \"$name\"';
  }

  @override
  String get done => 'Готово';

  @override
  String get downloading => 'Сохранение...';

  @override
  String get downloaded => 'В офлайн';

  @override
  String get downloadStarted => 'Сохранение в офлайн началось';

  @override
  String get downloadCancelled => 'Сохранение отменено';

  @override
  String downloadFailed(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get errorLabel => 'Ошибка';

  @override
  String get addToQueue => 'В очередь';

  @override
  String get editMetadata => 'Редактировать метаданные';

  @override
  String get artist => 'Исполнитель';

  @override
  String get album => 'Альбом';

  @override
  String get genre => 'Жанр';

  @override
  String get year => 'Год';

  @override
  String get details => 'Подробнее';

  @override
  String get addedToQueue => 'Добавлено в очередь';

  @override
  String get all => 'Все';

  @override
  String get video => 'Видео';

  @override
  String get audio => 'Аудио';

  @override
  String get requiredField => 'Обязательное поле';

  @override
  String get description => 'Описание';

  @override
  String get coverImage => 'Обложка';

  @override
  String get sourceUrl => 'Ссылка на источник';

  @override
  String get invalidSourceUrl => 'Введите корректную http(s)-ссылку';

  @override
  String get copyLink => 'Скопировать ссылку';

  @override
  String get linkCopied => 'Ссылка скопирована в буфер обмена';

  @override
  String get cannotOpenLink => 'Не удалось открыть ссылку';

  @override
  String get speed => 'Скорость';

  @override
  String get volume => 'Громкость';

  @override
  String get pause => 'Пауза';

  @override
  String get fullscreen => 'Полный экран';

  @override
  String get exitFullscreen => 'Свернуть';

  @override
  String get seekBack10 => 'Назад на 10 секунд';

  @override
  String get seekForward10 => 'Вперёд на 10 секунд';

  @override
  String get close => 'Закрыть';

  @override
  String get checkingAuthentication => 'Проверка авторизации...';

  @override
  String get useFilename => 'Из имени файла';

  @override
  String get fileAlreadyExists => 'Файл уже есть на сервере';

  @override
  String get uploadSuccess => 'Загрузка завершена';

  @override
  String get extractAudio => 'Извлечь аудио';

  @override
  String get extractingAudio => 'Извлекается аудио…';

  @override
  String get extractCancelled => 'Извлечение аудио отменено';

  @override
  String get cancelExtraction => 'Отменить извлечение';

  @override
  String get openAudioTrack => 'Открыть трек';

  @override
  String get audioExtracted => 'Аудиотрек сохранён в библиотеку';

  @override
  String get extractAudioConfirmTitle => 'Извлечь аудио?';

  @override
  String get extractAudioConfirmText =>
      'Аудиодорожка будет сохранена в аудиобиблиотеку в исходном качестве.';

  @override
  String extractFailed(String error) {
    return 'Не удалось извлечь аудио: $error';
  }

  @override
  String get changeCover => 'Заменить обложку';

  @override
  String get uploadingCover => 'Загрузка обложки...';

  @override
  String get editLyrics => 'Редактировать текст';

  @override
  String get editTranslation => 'Редактировать перевод';

  @override
  String get lyricsSaved => 'Текст сохранён';

  @override
  String get translationSaved => 'Перевод сохранён';

  @override
  String get saving => 'Сохранение...';

  @override
  String get addLyricsHere => 'Введите текст песни...';

  @override
  String get addTranslationHere => 'Введите перевод...';

  @override
  String get offlineMode =>
      'Нет подключения к серверу. Показывается только скачанный контент.';

  @override
  String get invalidYear => 'Неверный год';

  @override
  String get uploadCancelled => 'Загрузка отменена';

  @override
  String get hashingFile => 'Вычисление хэша...';

  @override
  String get checkingDuplicates => 'Проверка дубликатов...';

  @override
  String get serverProcessing => 'Обработка сервером...';

  @override
  String get offlineCopy => 'Офлайн-копия';

  @override
  String get audioPlayingInBackground => 'Играет аудио-трек';

  @override
  String get removeFromCollection => 'Удалить из коллекции';

  @override
  String get moveToCollection => 'Переместить в коллекцию';

  @override
  String get moveCollection => 'Переместить коллекцию';

  @override
  String get moveToRoot => 'В корень';

  @override
  String get newSubcollection => 'Новая подколлекция';

  @override
  String get subcollections => 'Подколлекции';

  @override
  String get collectionMoved => 'Коллекция перемещена';

  @override
  String get itemMoved => 'Элемент перемещён';

  @override
  String get noCollections => 'Нет коллекций';

  @override
  String get trash => 'Корзина';

  @override
  String get trashEmpty => 'Корзина пуста';

  @override
  String get restore => 'Восстановить';

  @override
  String get restored => 'Восстановлено';

  @override
  String get deleteForever => 'Удалить навсегда';

  @override
  String get purged => 'Удалено навсегда';

  @override
  String get emptyTrash => 'Очистить корзину';

  @override
  String get emptyTrashConfirm =>
      'Удалить всё из корзины навсегда? Файлы будут стёрты с диска.';

  @override
  String get trashEmptied => 'Корзина очищена';

  @override
  String purgeMediaConfirm(String name) {
    return 'Удалить \"$name\" навсегда? Файл будет стёрт с диска.';
  }

  @override
  String purgeCollectionConfirm(String name) {
    return 'Удалить \"$name\" навсегда вместе с содержимым?';
  }

  @override
  String get movedToTrash => 'Перемещено в корзину';

  @override
  String get moveMediaToTrash =>
      'Переместить файл в корзину? Потом можно восстановить.';

  @override
  String deleteCollectionTrashConfirm(String name, int sub, int files) {
    return 'Переместить \"$name\" в корзину (подколлекций: $sub, файлов: $files)?';
  }

  @override
  String get failedToLoadCollections => 'Не удалось загрузить коллекции';

  @override
  String get addMedia => 'Добавить медиа';

  @override
  String get loadMore => 'Загрузить ещё';

  @override
  String get showAll => 'Показать все';

  @override
  String get changeEmail => 'Изменить email';

  @override
  String failedToRemove(String error) {
    return 'Не удалось удалить: $error';
  }

  @override
  String get alreadyAdded => 'Уже добавлено';

  @override
  String get uploadFileEmpty => 'Выбранный файл пуст';

  @override
  String get uploadFileTooLarge =>
      'Файл превышает лимит загрузки сервера (2 ГБ)';

  @override
  String get addToFavorites => 'Добавить в избранное';

  @override
  String get removeFromFavorites => 'Убрать из избранного';

  @override
  String get invalidServerUrl =>
      'Введите корректный URL, начинающийся с http:// или https://';

  @override
  String failedToSaveSettings(String error) {
    return 'Не удалось сохранить настройки: $error';
  }

  @override
  String get logoutConfirmTitle => 'Выйти?';

  @override
  String logoutConfirmMessage(String size) {
    return 'У вас $size офлайн-медиа. Выход удалит офлайн-кэш.';
  }

  @override
  String get offlineCache => 'Офлайн-кэш';

  @override
  String get cacheSizeCalculating => 'Расчёт размера кэша...';

  @override
  String cacheSizeLabel(String size) {
    return 'Офлайн-кэш: $size';
  }

  @override
  String get cacheCleared => 'Офлайн-кэш очищен';

  @override
  String get trustSelfSignedCertificate =>
      'Доверять самоподписанному сертификату';

  @override
  String get trustSelfSignedHint =>
      'Только для частных серверов. Включает небезопасный HTTPS для запросов API; для потоков видео/аудио сертификат всё равно должен быть доверенным. Обложки в уведомлениях применятся после перезапуска приложения.';

  @override
  String connectionFailed(String error) {
    return 'Не удалось подключиться к серверу: $error';
  }

  @override
  String serverStatusError(int code) {
    return 'Сервер вернул статус $code';
  }

  @override
  String get editArtistName => 'Изменить имя артиста';

  @override
  String get artistName => 'Имя артиста';
}
