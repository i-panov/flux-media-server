# Mobile Parity — handoff / всё, что осталось

**Дата снимка:** 2026-11-10. **HEAD снимка:** `8ec88b8`. **Ветка:** `master`.
**План:** [mobile-parity-plan-2026-11-09.md](mobile-parity-plan-2026-11-09.md).
**Статус:** исторический снимок от 2026-11-10. Актуальное состояние —
в разделе 0: Tasks 1–24 и поиск/сортировка списков (0.1.31) выполнены,
остался Task 25 (релиз и device-smoke).

Этот файл — самодостаточное ТЗ для другого агента: текущее состояние, правила
работы, оставшиеся задачи, известные долги и подводные камни.

---

## 0. Актуальный статус на 2026-11-11

**Кодовая база:** коммит `feat(mobile): поиск и сортировка списков`.
**Task 24:** коммит `chore(mobile): e2e, CI и документация` — база перед
search/sort. **Версии:** backend `1.0.29`, shared `0.1.8`, web `0.1.31`,
mobile `0.1.31`, versionCode `49`.

Tasks 1–23 реализованы и закоммичены. Компактная карта коммитов (подробные
описания и приёмка — в разделах 2 и 4):

| Task | Коммит | Итог |
|---|---|---|
| 1–7 | `d6ce4e3` … `8ec88b8` | shared API, зависимости, табы, тема, медиа-URL, детали видео |
| 8 | `52956e7` | видеоплеер: play/pause, seek, скорость, fullscreen, PiP, wakelock |
| 9 | `cdad7eb` | прогресс и resume видео (throttle, completed ≥90%, reset) |
| 10 | `e4de91f` | действия видео и extract audio (только admin) |
| 11 | `1c9754b` | shared audioQueue/lyricsSync |
| 12 | `1f14fc8` | AudioProvider, очередь, shuffle/repeat, persisted queue |
| 13 | `ffdc3e2` | полный/мини-аудиоплеер, background, lock screen |
| 14 | `d4f8e94` | lyrics/translation и sync-подсветка |
| 15 | `5da91f4` | артисты: список, треки, favorite, rename |
| 16 | `662eef3` | continue watching и избранное |
| 17 | `e4f121d` | коллекции, вложенность, bulk |
| 18 | `b43fc68` | корзина: restore/purge/empty |
| 19 | `d9ef437` | загрузка файлов: picker, очередь, progress, retry |
| 20 | `8fb570e` | метаданные, обложка, удаление |
| 21 | `351ab7f` | offline-скачивание и индекс |
| 22 | `8e2edf6` | offline playback и экспорт |
| 23 | `2c4d776` | настройки, тема, i18n, logout-reset |
| 24 | `5e41973` | e2e, CI и документация |
| search/sort | `feat(mobile): поиск и сортировка` | поиск и сортировка списков видео/аудио, версия 0.1.31 |

**Task 24 (этот коммит):** CI-обвязка для 18 Maestro flow, которые были
созданы в Tasks 4–23: ручной `.github/workflows/mobile-e2e.yml` (Android
emulator + Metro + Maestro), проверки `expo install --check` и
`expo config --type introspect` в CI, обновлённые plan/handoff/README/AGENTS
и release notes. Проверки Task 24: typecheck, lint, 33 файла / 346 тестов,
`expo export`, `version:sync --check` (0.1.30/48), YAML-парсинг всех flow и
workflow.

**Пробел паритета закрыт:** поиск и сортировка списков видео/аудио
реализованы в 0.1.31 — `useVideoList(q, sort)`/
`useAudioList(q, sort)`, `MediaSearchBar`, debounce 300 мс, asc/desc,
очистка и отдельные пустые состояния. В библиотеке остаётся Task 25:
релиз, dogfood APK arm64 и device-smoke.

### Актуальные известные ограничения

- **Maestro не запускался:** в окружении разработки нет maestro, adb,
  эмулятора и KVM. Все flow, включая новый `search.yaml`, проверены только
  парсингом YAML. Утверждать, что сценарий «прошёл», нельзя.
- **`mobile-e2e.yml` не проверен на раннере:** job ручной
  (`workflow_dispatch`), в push/PR не входит; возможны правки образа,
  AVD, KVM и таймаутов Maestro.
- **Нет system notifications для upload:** прогресс и «готово» видны только
  на открытом экране загрузок, уведомлений в шторке нет.
- **Нет artwork на lock screen:** обложка требует Bearer-заголовков,
  которые система не отправит; metadata содержит title/artist/album.
- **iOS-края не проверены на устройстве:** Keychain переживает
  `clearState`, PiP/background audio требуют dev/release build,
  security-scoped URL для upload и audio session — зона риска.
- **Device smoke не выполнен:** background audio, PiP, offline и
  lock screen проверены статически/юнит-тестами, не на железе.

---

## 1. Правила, которые озвучил пользователь

1. **ВСЕГДА писать только по-русски. Никогда не использовать китайский.**
   Это касается ответов пользователю, комментариев в коде и любого текста.
2. **После каждого коммита/крупного раунда — отписаться в чат**, что сделано,
   и продолжить работу. Пользователь хочет быть в курсе.
3. **После каждого крупного раунда запускать субагента на ревью текущего
   незакоммиченного `git diff`.** Субагенту **запрещено** менять/откатывать
   файлы, делать `git add/commit/checkout/restore/reset/stash/clean`.
4. **Никогда не прерывать ревьюера.** Ждать, пока он сам закончит. Если он
   долго работает — ждать, а не убивать/перезапускать.
5. Замечания ревью **исправить**, затем закоммитить и переходить к следующей
   задаче. Не оставлять открытые P0/P1/P2 без решения.
6. Выбранный режим исполнения — **Subagent-Driven Development**:
   свежий implementer-субагент на задачу, потом spec-review, потом
   code-quality-review; фиксы делает тот же implementer; ревью повторяется.
7. Документацию держать в порядке: `docs/`, `AGENTS.md`, `README.md`.
   `KODA.md` удалён — пользователь им больше не пользуется.
8. Не трогать legacy `frontend/` (Flutter) без явной необходимости; он
   только справочник фич.
9. Коммиты — в `master` (так велась работа); без push, reset, checkout
   чужого кода.

---

## 2. Что уже готово (Tasks 1–7)

| Task | Коммит | Итог |
|---|---|---|
| 1 | `d6ce4e3` | progress/favorites/lyrics API и схемы в `@flux/shared`; web-хуки — обёртки |
| 2 | `2a0329b` | collections API в shared; bulk add/move/remove, stats, test на real `null` payload |
| 3 | `b1ba41b` | expo-video/audio/file-system/image/pickers/keep-awake/async-storage/system-ui; PiP, background audio, dark splash; mobile 0.1.10/28 |
| 4 | `24649bd` | табы Видео/Аудио/Библиотека/Настройки; AuthGate на табах; публичный `/server`; back-stack recovery; scheme `flux`; Ionicons; Maestro tabs |
| 5 | `2bee567` | тема light/dark/system + hydration/splash; токены; Screen/MediaCard/MediaGrid/Empty/Error/ListFooter; mobile 0.1.12/30 |
| 6 | `bbf4f9b` | `authSource`/`imageSource`, stream/thumb/cover URL + Bearer; mobile 0.1.13/31 |
| 7 | `8ec88b8` | экран деталей видео: auth-постер, метаданные, favorite, add-to-collection, source link, admin delete, 404/error; mobile 0.1.14/32 |

### Текущая структура mobile

```
mobile/app/(tabs)/_layout.tsx      табы + AuthGate
mobile/app/(tabs)/video.tsx        видео-сетка (MediaList)
mobile/app/(tabs)/audio.tsx        аудио-список
mobile/app/(tabs)/library.tsx      заглушка библиотеки
mobile/app/(tabs)/settings.tsx     тема/язык/health/logout
mobile/app/video/[id].tsx          детали видео
mobile/app/login.tsx               OTP-вход
mobile/app/server.tsx              публичная настройка URL
mobile/app/index.tsx               Redirect → /video
mobile/src/api/                    media/favorites/collections/setup
mobile/src/auth/                   session/logout
mobile/src/media/source.ts         authSource/stream/thumb/cover
mobile/src/theme/                  tokens/ThemeProvider
mobile/src/components/             Screen/MediaList/MediaCard/MediaGrid/...
.maestro/                          tabs, tabs-error-recovery, theme, video-detail
```

### Проверки на момент снимка (2026-11-10)

```bash
npm run typecheck -w mobile
npm run lint -w mobile
npm run test -w mobile          # 6 файлов / 25 тестов
cd mobile && npx expo export --platform android --output-dir dist
npm run version:sync -w mobile -- --check   # 0.1.14 / 32
```

Shared: `npm run test -w @flux/shared` — 96 тестов. Web не менялся с
`0.1.30`, но shared API расширялся.

---

## 3. Критичные ограничения окружения

- **Maestro CLI и эмулятор отсутствуют.** Все `.maestro/*.yaml` проверены
  только структурно. Не утверждать, что flow «прошёл».
- **Локальный `mobile/android` устарел** (gitignored, ~1.5 ГБ). Перед нативной
  сборкой нужен `npx expo prebuild --clean` (сначала сохранить
  `android/local.properties`); иначе не будет PiP/FGS/нового splash/темы.
- **Expo Go не подходит** для background audio/PiP — нужен dev/release build.
- **Глобальный npm registry = npmmirror.** `package-lock.json` чистый, но
  новый `npm install` может вернуть зеркало. При установке использовать
  `--registry=https://registry.npmjs.org`, не коммитить mirror-URL.
- **`~/.npm` и `~/.expo` могут быть read-only** в песочнице; `npx expo install
  --check` иногда падает с EROFS. Версии сверять с
  `node_modules/expo/bundledNativeModules.json`.
- **Go/ffmpeg** для мобильных задач не нужны; ffmpeg в окружении может
  отсутствовать, backend-тесты это учитывают.
- **Секреты/токены** не логировать. `authSource` читает SecureStore на каждый
  вызов, не кешировать.

---

## 4. Оставшиеся задачи (24–25)

> Tasks 8–24 выполнены; поиск/сортировка закрыты в 0.1.31. Их описания ниже
> сохранены как исторический контекст. Актуален только Task 25 — релиз и
> device-smoke.

Формат: цель → файлы → что сделать → приёмка/тесты. Все задачи делать
TDD/с тестами, где возможно; после каждой — commit, отчёт, review.

### Task 8 ✅ — видеоплеер

**Цель:** проигрывать видео в приложении, не только показывать постер.

**Files:** `mobile/src/player/VideoPlayer.tsx`,
`mobile/src/player/useVideoProgress.ts` (или отдельный hook),
`mobile/app/video/[id].tsx`.

**Сделать:**
- `useVideoPlayer({ uri, headers })` через `authSource(streamPath(id))`;
  `VideoView` (native/custom controls); `useKeepAwake` пока playing.
- Play/pause, seek ±10, таймлайн, скорость 0.5–2, fullscreen, PiP
  (`VideoView` + `enterFullscreen`/`startPictureInPicture`).
- Обработка 401: один retry после `authSource` (токен мог обновиться),
  затем Alert/ErrorState.
- Сохранить/восстановить позицию — Task 9; в Task 8 можно оставить hook
  заготовкой, но не дублировать progress-логику.
- Back/ориентация/PiP не должны ломать табы.

**Приёмка:**
- Видео играет с Bearer, seek/speed/fullscreen/PiP работают на устройстве
  (эмулятор/сборка).
- Pure-тесты: `formatTime`, clamp seek, список скоростей.
- Maestro: play/pause, fullscreen, PiP (device-only).
- version bump mobile patch (+ versionCode).

**Подводные камни:** PiP/фоновое видео требует prebuild; iOS PiP может
требовать `supportsPictureInPicture`; не монтировать два `VideoView`
одновременно; `useVideoPlayer` source object headers.

---

### Task 9 ✅ — прогресс и resume видео

**Цель:** продолжить просмотр с сохранённой позиции.

**Files:** `mobile/src/player/useVideoProgress.ts`,
`mobile/app/video/[id].tsx`.

**Сделать:**
- `fetchProgress` из shared; 404 → null.
- Resume один раз после `loaded`; не перетирать, если пользователь уже
  начал смотреть/сделал seek.
- Save каждые 5 секунд, на pause/unmount/end; completed при ≥90%.
- Reset в 0 удаляет progress (`deleteProgress`).
- Не спамить PUT; throttle; отменять при unmount.
- Ошибки сохранения не ломают воспроизведение.

**Приёмка:**
- Vitest: throttle, completed 90%, 404→null, reset.
- Maestro: закрыть на 30%, открыть — позиция восстановлена.
- version bump.

**Подводные камни:** не сохранять 0 при первом mount; не сохранять после
end как 0; длительность из player, а не из media; при смене трека сбросить.

---

### Task 10 ✅ — действия видео и extract audio

**Цель:** favorite/add-to-collection/source/extract уже частично есть;
добавить extract и вынести действия в sheet.

**Files:** `mobile/src/components/MediaActionsSheet.tsx`,
`mobile/src/api/extract.ts`, `mobile/app/video/[id].tsx`.

**Сделать:**
- Favorite/add/move collection/source link — переиспользовать существующие
  API (`favorites.ts`, `collections.ts`) и не дублировать.
- Extract: `POST /media/:id/extract`; poll job status до done/error; показывать
  прогресс/snackbar; только admin.
- Обработать 409/404/401.
- Кнопки только для admin, где backend требует `requireAdmin`.

**Приёмка:** Maestro/ручной extract; ошибки; version bump.

**Подводные камни:** backend extract endpoints смотреть в
`backend/internal/app/app.go`; не создавать второй API-клиент.

---

### Task 11 ✅ — shared audioQueue/lyricsSync

**Цель:** не дублировать очередь и парсер lyrics между web/mobile.

**Files:** `packages/shared/src/core/audioQueue.ts`,
`packages/shared/src/core/lyricsSync.ts`, web imports, mobile tests.

**Сделать:**
- Перенести `startQueue`, enqueue, move/remove, repeat/shuffle, next/prev,
  `shiftPlayedIndices`, `parseLyrics/sync` из `web/src/features/player`.
- Web-импорты/тесты перевести на shared; web-поведение не менять.
- Mobile-тест на move/played и lyrics parsing.
- Не тащить DOM/React.

**Приёмка:** shared tests + web tests зелёные; commit.

---

### Task 12 ✅ — AudioProvider и очередь

**Цель:** фоновый аудиоплеер с очередью.

**Files:** `mobile/src/player/AudioProvider.tsx`, `AudioBar.tsx`.

**Сделать:**
- `createAudioPlayer(null)`, `replace(source)` при смене трека;
  `useAudioPlayerStatus` для currentTime/duration/playing.
- Очередь: playQueue/enqueue/next/prev/shuffle/repeat off/all/one/remove/move/
  clear; persisted queue в AsyncStorage (id, title, artist, cover, path).
- `setAudioModeAsync({ shouldPlayInBackground:true, interruptionMode:"doNotMix" })`;
  `setActiveForLockScreen` с metadata (title/artist/album/artwork).
- `authSource(streamPath(id))` для headers; 401 retry.
- Provider в root `_layout`, mini bar над табами.

**Приёмка:** pure queue tests; Maestro queue/next/shuffle/repeat; фон и lock
screen на устройстве; version bump.

**Подводные камни:** expo-audio 58; config plugin уже стоит; player нужно
освобождать (`release`), не создавать на каждый рендер; Android foreground
service; iOS audio session.

---

### Task 13 ✅ — полный аудиоплеер, мини-плеер, фон

**Files:** `mobile/app/player.tsx`, `AudioBar.tsx`,
`mobile/src/player/useAudioProgress.ts`.

**Сделать:**
- Мини-бар над табами; tap → полный плеер.
- Play/pause, seek, ±10, скорость, обложка, очередь, favorite.
- Progress как видео (Task 9), save каждые 5с/pause/end.
- Background/lock screen; metadata обновлять при смене трека.
- Не сбрасывать очередь при навигации.

**Приёмка:** Maestro + устройство; version bump.

---

### Task 14 ✅ — lyrics/translation

**Files:** `mobile/app/audio/[id].tsx`, `LyricsView.tsx`.

**Сделать:**
- `fetchLyrics`/`useLyrics` (shared), 404 → null.
- Показ текста/перевода; sync-подсветка текущей строки; пустой перевод —
  вкладка скрыта; админ может открыть редактор (PUT shared `saveLyrics`).
- Обработать пустой/битый sync_data.

**Приёмка:** Maestro трек с lyrics + seek; version bump.

---

### Task 15 ✅ — артисты

**Files:** `mobile/app/artists/[id].tsx`, `src/api/media.ts`,
`src/api/metadata.ts` (artists list/rename).

**Сделать:**
- Список артистов, обложка (`has_cover/updated_at`), favorite, rename admin.
- Экран артиста: `audioListOptions(fetcher, "", artistId)`; пагинация.
- Ссылка с аудио-трека/строки.

**Приёмка:** Maestro; version bump.

---

### Task 16 ✅ — Continue Watching / Favorites

**Files:** `mobile/src/api/progress.ts` (shared wrappers),
`src/api/favorites.ts`, `app/(tabs)/video.tsx`, `audio.tsx`,
`SectionHeader`, `MediaCard`.

**Сделать:**
- Ряды Continue Watching (video/audio), Favorites, Collections (пока
  заглушка/переходы) на главных.
- Favorite media/artist toggle; оптимистичное обновление или disable на
  isFetching.
- Не дублировать элементы: либо скрывать избранное из основного списка,
  либо помечать; использовать `useVisibleMedia`-подобную логику.
- Пустые ряды скрывать.

**Приёмка:** Maestro favorite появляется/исчезает; version bump.

---

### Task 17 ✅ — коллекции UI/bulk

**Files:** `app/(tabs)/library.tsx`, `app/collections/[id].tsx`,
`src/api/collections.ts`, модалки create/rename/move/add.

**Сделать:**
- Дерево, breadcrumbs, CRUD, add/move/remove.
- Bulk-выбор, bulk move/remove; stats перед удалением.
- Обработать 404/409, пустые коллекции, вложенность.
- Переиспользовать shared collections API (bulk-add уже есть).
- Связать с Task 7 sheet (не дублировать).

**Приёмка:** Maestro create→add video→move; version bump.

---

### Task 18 ✅ — корзина

**Files:** `app/trash.tsx`, `src/api/trash.ts`.

**Сделать:**
- Список медиа/коллекций, restore, purge (admin), empty trash.
- Подтверждения; 404/409; инвалидация media/collections/trash/favorites.
- Admin-only destructive actions.

**Приёмка:** Maestro; version bump.

---

### Task 19 ✅ — загрузка файлов

**Files:** `app/upload.tsx`, `src/api/upload.ts`, `useUploadQueue.ts`.

**Сделать:**
- `expo-document-picker` (video/audio/image), multipart POST `/media/upload`
  с Bearer; `media_type`; force при duplicate.
- Progress через XHR `upload.onprogress` (fetch прогресс не даёт); 202 → poll
  `/media/uploads/:id` или `/media/transcodes/:id` до done/error.
- Очередь 2 параллельно, отмена, retry; локальные уведомления
  (`expo-notifications` + POST_NOTIFICATIONS на Android 13+ — учесть).
- Учесть лимит/таймаут/большие файлы.

**Приёмка:** Maestro picker→progress→готово; version bump.

**Подводные камни:** backend upload contract смотреть
`web/src/api/upload.ts`; FormData + Authorization; iOS security-scoped URL.

---

### Task 20 ✅ — метаданные, обложка, удаление

**Files:** `src/api/metadata.ts`, `src/api/cover.ts`,
`EditMetadataScreen.tsx`, `ChangeCoverSheet.tsx`.

**Сделать:**
- Metadata patch-семантика: пустые строки/0 очищают; artists список;
  `PUT /metadata/:id`.
- `expo-image-picker` → multipart `PUT /media/:id/cover`; JPEG/PNG/WebP ≤10MB.
- Delete → trash, confirm, admin-only (сейчас delete уже есть в Task 7).
- Обновлять detail/list/favorites/collections кэш.

**Приёмка:** Maestro title/cover/delete; version bump.

---

### Task 21 ✅ — менеджер скачиваний

**Files:** `src/downloads/downloadStore.ts`, `DownloadProvider.tsx`,
`app/downloads.tsx`, `DownloadButton.tsx`.

**Сделать:**
- `expo-file-system` (SDK 58: `File`/`DownloadTask` или legacy
  `createDownloadResumable`) с Authorization на `/media/:id/stream`.
- `.part` → rename, проверка Content-Length, отмена, retry, timeout.
- AsyncStorage-индекс: id, title, path, size, updated_at; лимит кеша/eviction.
- Индикатор на карточке/деталях; кнопка скачать/удалить.
- Учесть, что `expo-file-system@58` не экспортирует `createDownloadResumable`
  из корня — импорт из `expo-file-system/legacy` или новый API.

**Приёмка:** Vitest filename/quota/index; Maestro download→airplane; version bump.

---

### Task 22 ✅ — offline playback и экспорт

**Files:** `src/player/offlineSource.ts`, `app/downloads.tsx`.

**Сделать:**
- Если файл скачан — source `file://`, иначе stream; для audio/video.
- `expo-sharing`/SAF «Сохранить в Files»; удаление из кеша/индекса.
- Не ломать progress/sync; offline-ошибки.

**Приёмка:** Maestro airplane playback; version bump.

---

### Task 23 ✅ — настройки, тема, i18n

**Files:** `app/server.tsx`, login и i18n; публичная настройка — `/server`.

**Сделать:**
- Server URL, theme (system/light/dark), language ru/en — уже частично есть;
  довести все новые строки, убрать hardcode.
- Logout очищает query cache, audio queue, downloads, токены, persisted state.
- Проверить все экраны в dark/light, a11y.
- Возможно вынести `KeyValueStore` вместо прямого AsyncStorage.

**Приёмка:** Maestro тема/язык/logout; version bump.

---

### Task 24 ✅ — тесты, CI, документация

**Итог:** 18 flow в `.maestro/` на момент Task 24; search/sort добавил
19-й `search.yaml`. Ручной `.github/workflows/mobile-e2e.yml`,
config-проверки в `ci.yml`, обновлённые plan/handoff/README/AGENTS и
release notes. Maestro и e2e-workflow не запускались (см. раздел 0).

**Сделать:**
- Maestro flows в `.maestro/`; CI job Android emulator (Maestro CLI).
- `npm run test -w mobile`, typecheck/lint, `expo export`.
- `expo install --check`/`expo config --type introspect` в CI.
- Обновить `docs/mobile-parity-plan`, README, AGENTS, handoff.
- Добавить component/render tests при необходимости (RNTL) или ограничиться
  Maestro.

**Приёмка:** CI зелёный; docs актуальны.

---

### Поиск и сортировка списков ✅ — закрыто в 0.1.31

**Цель:** закрыть единственный известный функциональный разрыв с Flutter.

**Files:** `mobile/app/(tabs)/video.tsx`, `audio.tsx`,
`mobile/src/api/media.ts`, `mobile/src/components/MediaList.tsx`,
`mobile/src/i18n/index.ts`, debounce/controls-компонент.

**Сделано:**
- `useVideoList(q, sort)` и `useAudioList(q, sort)` проброшены в
  `videoListOptions`/`audioListOptions` (shared уже поддерживает).
- TextInput поиска с debounce 300 мс, переключатель asc/desc, скрытие
  home-рядов при активном поиске, пустые состояния «ничего не найдено»,
  «библиотека пуста» и «всё в избранном».
- Тесты на чистые хелперы (debounce, toggle sort, нормализация запроса,
  сброс пагинации, excluded/empty); version bump mobile patch и
  `version:sync` (0.1.31/49).

**Приёмка:** поиск/сортировка работают в обоих табах по коду и unit-тестам;
realtime-проверка на устройстве не выполнялась — см. Task 25.

---

### Task 25 — релиз

- [x] `version:sync`, versionCode 49, lockfile.
- [ ] Dogfood APK arm64 — заблокировано: нет Android SDK/NDK.
- [ ] Smoke на устройстве: login, video, audio background/lock, offline —
  заблокировано: нет устройства/эмулятора.
- [x] Известные ограничения записаны (release notes 0.1.31).
- [x] Commit `chore(mobile): релиз 0.1.31`.

---

## 5. Известные P3-долги (исторический снимок)

Список ниже — долги, зафиксированные при приёмке Tasks 1–7. Часть закрыта
в Tasks 8–23; он оставлен как история и не является блокером Task 25.

### После Task 1
- Дубли shared/web тестов progress/favorites; web-тесты не проверяют
  session/401 wrapper.
- Barrel shared шире контракта (`progressEntrySchema`, `favoritesListSchema`,
  `isUnfinishedProgress`, `isStaleFavoriteError`), нет `ProgressList`.
- Web-обёртка `fetchLatestUnfinishedAudio` имеет то же имя, что shared, но
  другое поведение (session/ошибки).
- `saveLyrics` всегда `clear:true`/`source:"user"` по умолчанию; сделать
  параметром.
- Нет тестов rethrow progress/lyrics, stale-total favorites.
- Версия shared не бампнута (0.1.7). **Закрыто:** shared `0.1.8`.

### После Task 2
- Основные happy-path тесты bulk неполные (без всех 4 ключей); dedicated
  null tests есть.
- Дубли web/shared тестов moveCollection.
- `collectionSchema` реэкспорт в web без потребителей.
- `queryFn: () => fetchCollections()` — лишняя стрелка.
- `Collection.type` — `z.string()`, а create принимает `MediaType`; нужен
  guard/isMediaType.
- Bulk-add теперь есть, но `added`-тест/схема согласованы.
- Версия shared не бампнута. **Закрыто:** shared `0.1.8`.

### После Task 3
- Локальный `mobile/android` устарел; нужен prebuild.
- CI не проверяет config plugins (`expo install --check`,
  `expo config --type introspect`). **Закрыто в Task 24.**
- `CAMERA` может появиться из AAR image-picker; решить
  `cameraPermission:false`, если камера не нужна.
- `expo-image` plugin без props — no-op.
- `expo-audio ~58.0.11` vs bundled ~58.0.10 — допустимо.
- `mobile/tsconfig.json` не менялся (в плане указан, но не нужен).

### После Task 4
- DRY health/save: `settings.tsx` и `server.tsx` дублируют статус/логику
  сохранения; вынести `useBackendStatus`/`useServerConfig`, покрыть тестами.
- `settings.tsx` ветка `session.isError` под AuthGate недостижима.
- TextInput без accessibilityLabel; live-region для save/error.
- Maestro flows не в CI; iOS Keychain переживает clearState.
- `scheme` добавлен; нативное проверить на устройстве.
- back-stack проверен статически; runtime не подтверждён.
- Teма/язык — button+selected, не radiogroup.

### После Task 5
- Нет unit-тестов hydration/persist/race; AsyncStorage напрямую в
  ThemeProvider (лучше KeyValueStore).
- Нет timeout гидратации; при зависании getItem — вечный splash.
- `persistedMode` при повреждённом значении показывает «system», хотя
  сохранения не было.
- Нет accessibilityLiveRegion для «Сохранено».
- Maestro `settings-theme-persisted` без `scrollUntilVisible`.
- Hardcoded radii (10/32/999) в компонентах/MediaList.
- `favorite` dark = #c92a2a (как bg ок, как foreground 3.35:1).
- MediaGrid теряет ListHeader при loading/error; onEndReached без guard;
  ListFooter при error без onRetry рендерит пустой контейнер.
- `Screen` default edges top — потерян bottom inset.
- MediaCard/SectionHeader без render-тестов.
- Light splash выровнен с #ffffff (бренд-цвет #E6F4FE больше не используется).
- jimp-compact может дать тонкий тёмный кант у dark splash (asset корректен).

### После Task 6
- `authSource` гарантирует абсолютный URL только при absolute baseUrl;
  default `/api` даст относительный. Добавить `new URL` проверку/тест.
- Query/fragment в baseUrl не обрабатываются; `normalizeServerUrl` принимает.
- Нет type-only assert совместимости с expo ImageSource/VideoSource/AudioSource.
- `Media.thumbnail_url/cover_url` уже содержат `/api`; `thumbPath/coverPath`
  без `/api` — не смешивать, использовать только `*Path`.
- `imageSource` — алиас, тест тавтологичен; это ок.

### После Task 7
- Maestro source-ветка условная и может молча пропуститься; back после
  scroll может быть вне viewport.
- `AddToCollectionSheet` при `collections.isError` с кешем заменяет список
  error-view; сделать data-first.
- Favorite при первичной ошибке favorites остаётся enabled/isFavorite=false;
  POST на уже избранное глушится stale, пользователь не видит изменения.
- 404 при кеше оставляет устаревший экран + inline error; различать.
- `useDeleteMedia` не инвалидирует `["favorites"]`.
- `Screen` top edge: нижние кнопки detail могут уходить под home indicator.
- Poster cover→thumb не сбрасывает старый source до нового; краткий битый
  кадр.
- Detail грузит все favorites (до 200/стр.) ради boolean; нужен per-id/limit
  endpoint или локальный кэш.
- Sheet не создаёт коллекции (Task 17).
- Metadata edit/cover придут в Task 20.

---

## 6. Версии и процесс

Текущие (2026-11-11):
- backend `1.0.29`;
- web `0.1.31`;
- shared `0.1.8`;
- mobile `0.1.31`, versionCode 49.

**Долг снимка 2026-11-10 снят:** shared поднят до `0.1.8`, web и mobile
пинят `0.1.8`; `package-lock.json` обновлён. Task 24 — docs/CI-коммит без
изменения кода и версий; search/sort поднял mobile до `0.1.31`/49.

Правило версий: каждый коммит, затрагивающий backend/web/mobile/shared,
поднимает patch; mobile `versionCode` — через `npm run version:sync`,
CI проверяет `--check`.

---

## 7. Команды и проверки

```bash
# mobile
npm run typecheck -w mobile
npm run lint -w mobile
npm run test -w mobile
npm run version:sync -w mobile -- --check
cd mobile && EXPO_OFFLINE=1 npx expo install --check
cd mobile && npx expo config --type introspect
cd mobile && npx expo export --platform android --output-dir dist

# Maestro (нужны maestro, adb и эмулятор/устройство)
maestro test .maestro/tabs.yaml
maestro test .maestro/theme.yaml

# shared
npm run typecheck -w @flux/shared
npm run lint -w @flux/shared
npm run test -w @flux/shared

# web (если менялся shared/web)
cd web && npx tsc --noEmit && npm run lint && npm run lint:deadcode && npx vitest run --configLoader runner

# backend (если задача трогает API)
cd backend && go test ./internal/... -count=1
```

Перед коммитом: `git diff --check`, `git status`; не коммитить `node_modules`,
`dist`, `mobile/android`, `docs/superpowers`.

---

## 8. Definition of Done для паритета

DoD **функционально закрыт**: поиск/сортировка списков вошли в 0.1.31,
пункты Tasks 1–24 реализованы. Формально чекбоксы не отмечать до Task 25:
dogfood-сборка и device-smoke ещё не выполнены.

- [ ] Видео: список/поиск/детали/плеер (play/pause/seek/±10/скорость/
      fullscreen/PiP), resume, source, favorite, коллекции, extract, offline.
- [ ] Аудио: список/артисты/полный+мини-плеер/очередь (shuffle/repeat/
      reorder), фон/lock screen, lyrics/translation, resume, offline.
- [ ] Библиотека: continue watching, favorites (media/artists), коллекции
      с вложенностью и bulk, корзина.
- [ ] Загрузка: picker/очередь/progress/отмена/retry/уведомления.
- [ ] Метаданные/обложка/удаление; admin-only.
- [ ] Offline: download/play/удаление/лимит/экспорт.
- [ ] ru/en, light/dark/system, ошибки/пустые состояния.
- [ ] Maestro flows + CI + dogfood APK.
- [ ] Документация (README, AGENTS, plan, handoff) актуальна.

---

## 9. Что проверить перед Task 25

1. `git status` — чисто; HEAD — коммит search/sort
   `feat(mobile): поиск и сортировка списков`.
2. `npm run typecheck -w mobile && npm run lint -w mobile && npm run test -w mobile`.
3. `npm run version:sync -w mobile -- --check` — 0.1.31/49.
4. `cd mobile && EXPO_OFFLINE=1 npx expo install --check && npx expo config --type introspect`.
5. Прогнать `.maestro/tabs.yaml`, `.maestro/theme.yaml` и
   `.maestro/search.yaml` на эмуляторе или устройстве; не выдавать
   структурную проверку YAML за прогон.
6. Собрать dogfood APK arm64 и пройти device-smoke: login, video,
   audio background/lock, offline, поиск/сортировка.
