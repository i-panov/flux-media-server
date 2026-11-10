# Mobile Parity — handoff / всё, что осталось

**Дата снимка:** 2026-11-10. **HEAD:** `8ec88b8`. **Ветка:** `master`.
**План:** [mobile-parity-plan-2026-11-09.md](mobile-parity-plan-2026-11-09.md).
**Статус:** Tasks 1–7 приняты; Tasks 8–25 не начаты. Рабочее дерево чистое.

Этот файл — самодостаточное ТЗ для другого агента: текущее состояние, правила
работы, оставшиеся задачи, известные долги и подводные камни.

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

### Проверки, которые сейчас зелёные

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

## 4. Оставшиеся задачи (8–25)

Формат: цель → файлы → что сделать → приёмка/тесты. Все задачи делать
TDD/с тестами, где возможно; после каждой — commit, отчёт, review.

### Task 8 — видеоплеер

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

### Task 9 — прогресс и resume видео

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

### Task 10 — действия видео и extract audio

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

### Task 11 — shared audioQueue/lyricsSync

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

### Task 12 — AudioProvider и очередь

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

### Task 13 — полный аудиоплеер, мини-плеер, фон

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

### Task 14 — lyrics/translation

**Files:** `mobile/app/audio/[id].tsx`, `LyricsView.tsx`.

**Сделать:**
- `fetchLyrics`/`useLyrics` (shared), 404 → null.
- Показ текста/перевода; sync-подсветка текущей строки; пустой перевод —
  вкладка скрыта; админ может открыть редактор (PUT shared `saveLyrics`).
- Обработать пустой/битый sync_data.

**Приёмка:** Maestro трек с lyrics + seek; version bump.

---

### Task 15 — артисты

**Files:** `mobile/app/artists/[id].tsx`, `src/api/media.ts`,
`src/api/metadata.ts` (artists list/rename).

**Сделать:**
- Список артистов, обложка (`has_cover/updated_at`), favorite, rename admin.
- Экран артиста: `audioListOptions(fetcher, "", artistId)`; пагинация.
- Ссылка с аудио-трека/строки.

**Приёмка:** Maestro; version bump.

---

### Task 16 — Continue Watching / Favorites

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

### Task 17 — коллекции UI/bulk

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

### Task 18 — корзина

**Files:** `app/trash.tsx`, `src/api/trash.ts`.

**Сделать:**
- Список медиа/коллекций, restore, purge (admin), empty trash.
- Подтверждения; 404/409; инвалидация media/collections/trash/favorites.
- Admin-only destructive actions.

**Приёмка:** Maestro; version bump.

---

### Task 19 — загрузка файлов

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

### Task 20 — метаданные, обложка, удаление

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

### Task 21 — менеджер скачиваний

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

### Task 22 — offline playback и экспорт

**Files:** `src/player/offlineSource.ts`, `app/downloads.tsx`.

**Сделать:**
- Если файл скачан — source `file://`, иначе stream; для audio/video.
- `expo-sharing`/SAF «Сохранить в Files»; удаление из кеша/индекса.
- Не ломать progress/sync; offline-ошибки.

**Приёмка:** Maestro airplane playback; version bump.

---

### Task 23 — настройки, тема, i18n

**Files:** settings/server/login/i18n.

**Сделать:**
- Server URL, theme (system/light/dark), language ru/en — уже частично есть;
  довести все новые строки, убрать hardcode.
- Logout очищает query cache, audio queue, downloads, токены, persisted state.
- Проверить все экраны в dark/light, a11y.
- Возможно вынести `KeyValueStore` вместо прямого AsyncStorage.

**Приёмка:** Maestro тема/язык/logout; version bump.

---

### Task 24 — тесты, CI, документация

**Сделать:**
- Maestro flows в `.maestro/`; CI job Android emulator (Maestro CLI).
- `npm run test -w mobile`, typecheck/lint, `expo export`.
- `expo install --check`/`expo config --type introspect` в CI.
- Обновить `docs/mobile-parity-plan`, README, AGENTS, handoff.
- Добавить component/render tests при необходимости (RNTL) или ограничиться
  Maestro.

**Приёмка:** CI зелёный; docs актуальны.

---

### Task 25 — релиз

- `version:sync`, versionCode, dogfood APK arm64.
- Smoke на устройстве: login, video, audio background/lock, offline.
- Записать известные ограничения (Expo Go без background, splash).
- Commit `chore(mobile): релиз <version>`.

---

## 5. Известные P3-долги (не блокируют Tasks 8–25, но не забыть)

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
- Версия shared не бампнута (0.1.7).

### После Task 2
- Основные happy-path тесты bulk неполные (без всех 4 ключей); dedicated
  null tests есть.
- Дубли web/shared тестов moveCollection.
- `collectionSchema` реэкспорт в web без потребителей.
- `queryFn: () => fetchCollections()` — лишняя стрелка.
- `Collection.type` — `z.string()`, а create принимает `MediaType`; нужен
  guard/isMediaType.
- Bulk-add теперь есть, но `added`-тест/схема согласованы.
- Версия shared не бампнута.

### После Task 3
- Локальный `mobile/android` устарел; нужен prebuild.
- CI не проверяет config plugins (`expo install --check`,
  `expo config --type introspect`).
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

Текущие:
- backend `1.0.28`;
- web `0.1.30`;
- shared `0.1.7`;
- mobile `0.1.14`, versionCode 32.

**Долг:** Tasks 1/2 меняли shared, но shared остался `0.1.7`; web/mobile
пинят `0.1.7`. По AGENTS нужно:
- bump shared patch (0.1.8), обновить `web/package.json`,
  `mobile/package.json`, `package-lock.json`;
- bump web patch, если менялся web (пока нет);
- bump mobile patch на каждый коммит + `version:sync`.
Сделать это отдельным `chore` перед релизом или при следующем изменении shared.

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
cd mobile && npx expo export --platform android --output-dir dist
npm run version:sync -w mobile -- --check

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

## 9. Что проверить перед продолжением

1. `git status` — чисто; HEAD `8ec88b8`.
2. `npm run test -w mobile` — 25 тестов.
3. `npm run version:sync -w mobile -- --check` — 0.1.14/32.
4. Открыть `docs/mobile-parity-plan-2026-11-09.md` Task 8 и начать с
   `VideoPlayer`/`useVideoProgress`.
5. Сразу создать `.maestro` сценарий для плеера после реализации, но не
   выдавать структурную проверку за прогон.
