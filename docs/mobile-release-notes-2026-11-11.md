# Mobile 0.1.36 — release notes (2026-11-12)

**Версии:** mobile `0.1.36` / versionCode `54`, shared `0.1.11`,
backend `1.0.33`, web `0.1.41`.
**Ветка:** `master`. **Статус:** версия `0.1.34`/52; добавлен QR/device-code
вход. TV device-smoke выполнен на Android TV emulator (server → QR →
подтверждение с web → сессия). Dogfood APK: `0.1.34`/52, universal
`arm64-v8a + x86_64` ~59 МБ.

## Что добавлено в 0.1.33

- **Мемы:** вкладка «Мемы», сетка с ленивой загрузкой, поиск и
  полноэкранный просмотр изображения. Используется `/api/media?type=image`.
- **Нативный Android TV (каркас):** `react-native-tvos` + config-tv,
  TV-манифест с leanback/banner, `Platform.isTV`, read-only гейты
  (upload/trash/downloads/metadata/cover/delete/collections CRUD),
  TV-профиль скрывает лишнюю вкладку «Библиотека», D-pad-управление
  видео (play/pause, seek, rewind/fastForward), TV-иконка и баннер.
  TV-сборка собирается через `EXPO_TV=1`. На Android TV emulator пройден
  полный smoke: server→login (OTP)→список видео→detail→playback, play/pause
  с пульта, перемотка/контролы. Пустой список TV исправлен отдельным
  `TVVideoList` (ScrollView + крупные строки, D-pad focus-ring): обычный
  `MediaList` на TV не рендерил строки. Для self-hosted HTTP добавлен
  config-plugin `android:usesCleartextTraffic="true"` — без него release
  TV не логинится на LAN-сервер по `http://`. Проверено на Android TV
  emulator (android-36, x86_64, leanback, 1920×1080): APK ставится,
  приложение запускается, экран сервера открывается, D-pad переводит
  фокус в поле URL (подтверждено uiautomator). Полный сценарий
  логин→библиотека→плеер на эмуляторе не прогнан: TCG без KVM
  нестабилен.
- **10-foot TV-раскладка:** увеличенные отступы, строки 96 px, 4 колонки
  в гридах, focus-ring на карточках/поиске/контролах и начальный
  D-pad-фокус на первом элементе.
- **Лимит загрузки:** на бэкенде отдельный upload-бюджет 300/мин на
  пользователя вместо 10/мин на IP; массовая загрузка мемов больше не
  должна упираться в 429.

## Что исправлено в 0.1.32

- **Адрес сервера.** Нормализация теперь как во Flutter: принимает адрес
  без схемы (`flux.example.com`), публичным хостам добавляет `https://`,
  локальным — `http://`, идемпотентно дописывает `/api`, режет хвостовые
  слэши и отбрасывает query/fragment/userinfo. Ввод
  `https://flux.ithub24.ru` больше не даёт запросы без `/api`.
- **Первый запуск.** Убран дефолтный `http://localhost:8080/api`. Если
  адрес не сохранён и не задан через `EXPO_PUBLIC_API_BASE`, приложение
  сразу открывает `/server` с пустым полем, без запроса на localhost и
  без экрана «Ошибка».
- **Перезапуск с сохранённым адресом.** `initApiConfig` применяет
  сохранённый адрес до монтирования UI и нормализует старые значения,
  поэтому приложение не успевает сходить на пустой/старый baseUrl.
- Health-запрос на экране сервера выключен, пока адрес не задан.

## Что реализовано

- **Вход и сервер:** OTP-вход, access/refresh-токены только в SecureStore,
  публичная настройка URL (`/server`) до входа, сброс сессии и logout с
  очисткой кэша, очереди, скачиваний и persisted state.
- **Видео:** список с пагинацией, поиск по названию (debounce 300 мс),
  сортировка asc/desc, очистка поиска, отдельные пустые состояния;
  детали, плеер (play/pause, seek ±10, скорость 0.5–2, fullscreen, PiP,
  wakelock), resume по прогрессу, избранное, коллекции, source link,
  extract audio и удаление (admin).
- **Аудио:** список с поиском и сортировкой, очередь (start/enqueue/next/
  prev/shuffle/repeat/reorder), persisted queue, полный и мини-плеер,
  seek/скорость, прогресс и resume, фон и lock screen, lyrics/translation
  с sync-подсветкой, артисты и их треки. При поиске очередь строится из
  видимых результатов, индексы совпадают со списком.
- **Библиотека:** continue watching, избранное (медиа и артисты), коллекции
  с вложенностью и bulk-операциями, корзина (restore, purge, empty для
  admin).
- **Загрузка:** document picker (video/audio/image), очередь на 2
  параллельных загрузки, progress, отмена/retry, обработка duplicate,
  polling фоновой обработки.
- **Метаданные:** редактирование полей и артистов, смена обложки,
  удаление в корзину.
- **Offline:** resumable download с Bearer, индекс и лимит кеша, offline
  playback из `file://`, экспорт/«Сохранить в Files», удаление из кеша.
- **Настройки:** тема system/light/dark, язык ru/en, health сервера,
  logout.
- **Тесты и CI:** Vitest на чистую логику и контракты (включая debounce,
  нормализацию запроса, сброс пагинации и empty/excluded-состояния),
  19 Maestro-flow в `.maestro/` (search.yaml добавлен, но не запускался),
  проверки `expo install --check` и `expo config --type introspect` в CI,
  ручной Android e2e workflow с Metro, `adb reverse`, логами и
  скриншотами в артефактах.

## Известные ограничения

- **Maestro не запускался:** в окружении разработки нет maestro, adb,
  эмулятора и KVM. Все flow, включая новый `search.yaml`, проверены только
  парсингом YAML; отчёт не утверждает, что сценарии прошли.
- **Device-smoke не выполнен:** background audio, lock screen, PiP и
  offline проверены кодом и unit-тестами, но не на железе. Expo Go для
  этих функций не подходит — нужен dev/release build.
- **`mobile-e2e.yml` не проверен:** ручной workflow
  (`workflow_dispatch`), в push/PR не входит; возможны правки образа,
  AVD и таймаутов. Медиа-зависимые flow в нём намеренно не запускаются;
  debug-APK требует Metro на хосте и `adb reverse`.
- **Нет system notifications для upload:** прогресс и «готово» видны только
  на открытом экране загрузок; уведомлений в шторке нет.
- **Нет artwork на lock screen:** обложка требует Bearer-заголовков,
  которые система не отправит; в metadata есть title/artist/album.
- **iOS-края не проверены:** Keychain переживает `clearState`,
  PiP/background audio, security-scoped URL для upload и audio session
  требуют отдельного прогона на устройстве.
- **Offline-коллекции неполные:** скачиваются медиа, серверное дерево
  коллекций в offline доступно только для уже скачанных элементов.

## Релизный чек-лист

- [x] `version:sync`, versionCode 51, lockfile синхронизирован.
- [x] Известные ограничения записаны (ниже).
- [x] Коммит `feat(mobile): мемы и TV-каркас`.
- [x] Dogfood APK arm64 — собран (`0.1.33`/51, ~33 МБ, `arm64-v8a`).
- [x] TV AAB arm64 — собран (`0.1.33`/51, ~27 МБ).
- [ ] Device-smoke (login, video, audio background/lock, offline) —
  заблокировано: нет устройства/эмулятора.
- [ ] Maestro/e2e-прогон — заблокировано: нет maestro/adb/эмулятора.

## Проверки

```bash
npm run typecheck -w mobile
npm run lint -w mobile
npm run test -w mobile
npm run version:sync -w mobile -- --check
(cd mobile && EXPO_OFFLINE=1 npx expo install --check)
(cd mobile && npx expo config --type introspect)
(cd mobile && npx expo export --platform android --output-dir dist)
```

YAML всех `.maestro/*.yaml` и `.github/workflows/*.yml` был проверен
парсером локально (Python/PyYAML) в рамках Task 24; отдельного CI-шага
для YAML нет. Новые зависимости не добавлялись.

## 0.1.34 — QR/device-code вход

- На Android TV логин по умолчанию показывает QR и короткий код; OTP
  остаётся кнопкой «Войти по email».
- Мобильное подтверждение устройства: deep link `/activate?code=...`,
  ввод кода, показ имени/платформы, approve.
- В настройках телефона — «Активные устройства» с отзывом сессии.
- QR-матрица рендерится локально (`toqr` через `@flux/shared`), без
  внешнего сервиса и без токенов в QR.
- Для self-hosted HTTP сохранён `usesCleartextTraffic`; для QR нужен
  `server.public_url`, иначе берётся Host запроса.

## 0.1.35 — устройства

- Native-клиент присылает стабильный `device_id` и модель/платформу.
- В настройках устройства можно переименовать устройство.
- Logout завершает только сессии текущего устройства.

## 0.1.36 — устройства

- Текущее устройство отмечено в списке.
- Имена устройств и переименование синхронизированы с web.
