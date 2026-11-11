# Mobile Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Довести Expo-приложение до функционального паритета с legacy
Flutter: видео и аудио с плеерами, прогресс, избранное, коллекции, загрузка,
метаданные, корзина и offline-скачивание.

**Architecture:** Expo Router с нижними табами и stack-экранами; общий
data-layer в `@flux/shared`; видео — `expo-video`, аудио — `expo-audio`
с фоновым воспроизведением и lock screen; offline — `expo-file-system` +
AsyncStorage-индекс. Серверные контракты уже есть в backend/web, мобильный
клиент повторяет их, а не изобретает новые.

**Tech Stack:** Expo SDK 58, React Native 0.88, expo-router, TanStack Query,
zod, `@flux/shared`, expo-video, expo-audio, expo-file-system, expo-image,
expo-document-picker, expo-image-picker, AsyncStorage, Vitest, Maestro.

**Статус (2026-11-11):** Tasks 1–24 реализованы в объёме плана, но DoD
паритета **не закрыт**: нет поиска и сортировки списков видео/аудио
(shared API `q`/`sort` готов, UI — отдельная задача). Task 25 (релиз и
smoke на устройстве) не начат. Maestro-сценарии лежат в `.maestro/`, но в
окружении разработки не запускались (нет maestro/adb/эмулятора): проверка
YAML — не прогон. Ручной workflow `.github/workflows/mobile-e2e.yml` тоже
добавлен черновиком и не проверялся на раннере.

---

## 0. Текущее состояние и границы паритета

Срез на 2026-11-09 (старт плана): mobile умел OTP-вход, SecureStore,
настройку URL, health, списки видео/аудио с пагинацией, logout, i18n.
Таблица ниже — исходное состояние, а не текущее; итог — в разделе 3
(Tasks 1–24) и в release notes.

Цель паритета — функции Flutter, **без** админки, мемов и ТВ-режима
(в Flutter их нет; web-админка/мемы/ТВ остаются web-only).

| Блок | Flutter | Mobile на старте | Цель |
|---|---|---|---|
| Auth/сервер | ✅ | ✅ | оставить |
| Видео-список | ✅ | ✅ | поиск, сортировка, Continue/Favorites |
| Видео-детали/плеер | ✅ | ❌ | `expo-video`, resume, speed, PiP, wakelock |
| Аудио-список/артисты | ✅ | ⚠️ список | артисты, обложки |
| Аудио-плеер/мини-плеер | ✅ | ❌ | очередь, shuffle/repeat, фон, lock screen |
| Lyrics/translation | ✅ | ❌ | просмотр + sync |
| Избранное | ✅ | ❌ | медиа и артисты |
| Коллекции | ✅ | ❌ | CRUD, вложенность, перенос, bulk |
| Загрузка | ✅ | ❌ | picker, progress, очередь, уведомления |
| Метаданные/обложка/удаление | ✅ | ❌ | админ-действия |
| Извлечение аудио | ✅ | ❌ | админ-действие |
| Корзина | ✅ | ❌ | список, restore, purge |
| Offline/downloads | ✅ | ❌ | download, offline play, save to Files |
| i18n/тема | ✅ | ⚠️ i18n | ru/en, light/dark/system |

Единственный известный функциональный пробел паритета — поиск и сортировка
списков видео/аудио: shared-опции уже принимают `q`/`sort`, но экраны их не
передают. Поэтому DoD не закрыт, хотя Tasks 1–24 выполнены.

## 1. Решения и зависимости

### Навигация

- `app/_layout.tsx` — провайдеры: Query, Audio, Downloads, Theme.
- `app/(tabs)/_layout.tsx` — табы **Видео / Аудио / Библиотека / Настройки**.
- `app/login.tsx`, `app/server.tsx` — вне табов; сервер доступен без входа.
- Stack-экраны: `video/[id]`, `audio/[id]`, `player`, `artists/[id]`,
  `collections/[id]`, `upload`, `trash`, `downloads`.
- `AuthGate` остаётся на защищённых экранах; `server` (`app/server.tsx`) —
  публичный, доступен до входа.

### Данные

Перенести в `@flux/shared` чистые контракты, которые сейчас есть только
в web:

- `api/progress.ts` — `progressSchema`, `fetchProgress`, `saveProgress`,
  `deleteProgress`, `fetchContinueWatching`, `fetchLatestUnfinishedAudio`.
- `api/favorites.ts` — `favoriteSchema`, `fetchFavoriteMedia`,
  `fetchFavoriteArtistIds`, `toggleFavorite`, `toggleArtistFavorite`.
- `api/lyrics.ts` — `lyricsSchema`, `fetchLyrics`, `saveLyrics`.
- `api/collections.ts` — `collectionSchema`, `fetchCollections`,
  `fetchCollectionItems`, CRUD, add/move/remove/bulk, stats.
- `core/audioQueue.ts`, `core/lyricsSync.ts` — чистые функции из web,
  чтобы мобильная очередь и подсветка текста не дублировали логику.

Web-хуки остаются в `web/src/api/*` и оборачивают shared-функции; web-тесты
переезжают/остаются на shared-контрактах.

### Медиа-URL и авторизация

`src/media/source.ts`:

```ts
import { getApiConfig } from "@flux/shared";

export async function authSource(path: string) {
  const { baseUrl, transport } = getApiConfig();
  return { uri: `${baseUrl}${path}`, headers: await transport.authHeaders() };
}

export const streamPath = (id: number) => `/media/${id}/stream`;
export const thumbPath = (id: number) => `/media/${id}/thumb`;
export const coverPath = (id: number) => `/media/${id}/cover`;
```

`expo-video`/`expo-audio`/`expo-image` принимают `{ uri, headers }`.
При 401 во время воспроизведения — один повтор после `authSource()`
(токен мог обновиться), затем ошибка с retry.

### Плееры

- **Видео:** `expo-video`: `useVideoPlayer`, `VideoView`, `playbackRate`,
  `enterFullscreen`, `startPictureInPicture`, `useKeepAwake`.
- **Аудио:** `expo-audio`: `createAudioPlayer(null)`, `replace(source)`,
  `useAudioPlayerStatus`, `setActiveForLockScreen`, `setAudioModeAsync({
  shouldPlayInBackground: true, interruptionMode: "doNotMix" })`.
- **Offline:** `expo-file-system` `createDownloadResumable` с Authorization;
  `.part` → rename; индекс в AsyncStorage.

### Конфиг Expo

`app.json`:

```json
{
  "userInterfaceStyle": "automatic",
  "plugins": [
    "expo-splash-screen",
    ["expo-audio", { "enableBackgroundPlayback": true }],
    ["expo-video", { "supportsPictureInPicture": true }]
  ]
}
```

Для Android background-audio нужен dev/release build, Expo Go не подходит;
это учитывается в smoke/CI.

### Тесты

- Vitest — чистые функции, API-контракты, очередь, progress-throttle.
- Maestro — критичные flow: login → video → resume; audio queue;
  favorite/collection; upload; offline play.
- UI-компоненты отдельным Jest-стеком не покрываем, чтобы не тащить
  второй runner; визуальные регрессии — скриншоты Maestro.

---

## 2. Целевая структура файлов

```
mobile/app/(tabs)/_layout.tsx
mobile/app/(tabs)/video.tsx
mobile/app/(tabs)/audio.tsx
mobile/app/(tabs)/library.tsx
mobile/app/(tabs)/settings.tsx
mobile/app/video/[id].tsx
mobile/app/audio/[id].tsx
mobile/app/player.tsx
mobile/app/artists/[id].tsx
mobile/app/collections/[id].tsx
mobile/app/upload.tsx
mobile/app/trash.tsx
mobile/app/downloads.tsx
mobile/app/server.tsx
mobile/src/api/{progress,favorites,collections,lyrics,upload,trash,metadata,cover,extract}.ts
mobile/src/media/source.ts
mobile/src/player/{AudioProvider,AudioBar,QueueSheet,useVideoProgress,useAudioProgress}.tsx
mobile/src/components/{MediaCard,MediaGrid,SectionHeader,EmptyState,ErrorState,ListFooter}.tsx
mobile/src/downloads/{DownloadProvider,downloadStore}.ts
mobile/src/theme/{tokens,ThemeProvider}.ts
```

---

## 3. Фазы и задачи

### Фаза 0 — фундамент (3–4 дня)

#### Task 1: перенести progress/favorites/lyrics в shared

**Files:** создать `packages/shared/src/api/progress.ts`,
`favorites.ts`, `lyrics.ts`; обновить `packages/shared/src/index.ts`,
`web/src/api/{progress,favorites,lyrics}.ts`, тесты.

- [x] Вынести zod-схемы и fetch-функции без React-хуков.
- [x] Web-хуки оставить обёртками над shared-функциями; ключи query не менять.
- [x] Тесты shared: 404 progress → null, 409 favorite → stale, lyrics 404 → null.
- [x] `npm run test -w @flux/shared`, web `tsc/vitest` — зелёные.
- [x] Commit: `refactor(shared): вынести progress/favorites/lyrics`.

#### Task 2: перенести collections в shared

**Files:** `packages/shared/src/api/collections.ts`,
`web/src/api/collections.ts`, тесты.

- [x] Перенести схемы, list/items/create/rename/delete/add/move/remove/bulk/stats.
- [x] Web-хуки инвалидации оставить в web, чтобы не менять поведение.
- [x] Тесты: bulk-ответ, частичный skipped, 404/409.
- [x] Commit: `refactor(shared): вынести collections API`.

#### Task 3: зависимости и конфиг Expo

**Files:** `mobile/package.json`, `mobile/app.json`, `mobile/tsconfig.json`.

- [x] Добавить `expo-video`, `expo-audio`, `expo-file-system`, `expo-image`,
      `expo-document-picker`, `expo-image-picker`, `expo-keep-awake`,
      `@react-native-async-storage/async-storage`.
- [x] `app.json`: `userInterfaceStyle: "automatic"`, плагины `expo-audio`
      (background) и `expo-video` (PiP).
- [x] `npx expo prebuild --clean` на dev-машине; проверить манифест Android
      (foreground service) и iOS background mode.
- [x] `npm run typecheck -w mobile`, `expo export` — ok.
- [x] Commit: `chore(mobile): добавить видео/аудио/offline зависимости`.

#### Task 4: табы и каркас навигации

**Files:** `mobile/app/_layout.tsx`, `mobile/app/(tabs)/_layout.tsx`,
`mobile/app/(tabs)/{video,audio,library,settings}.tsx`, `app/server.tsx`.

- [x] Табы: Видео, Аудио, Библиотека, Настройки; иконки Ionicons из
      `@expo/vector-icons` (не lucide).
- [x] `AuthGate` на табах; `/server` доступен без сессии.
- [x] Сохранить deep links `/video`, `/audio`, `/settings`.
- [x] Maestro smoke: login → табы → settings.
- [x] Commit: `feat(mobile): табы и каркас навигации`.

#### Task 5: тема и общие компоненты

**Files:** `src/theme/tokens.ts`, `ThemeProvider.tsx`,
`src/components/{Screen,SectionHeader,EmptyState,ErrorState,MediaCard,MediaGrid}.tsx`.

- [x] Токены: фон/текст/акцент, light/dark, отступы, радиусы.
- [x] `ThemeProvider` читает system + настройку пользователя из AsyncStorage.
- [x] Общие состояния: loading/empty/error/retry; карточка с обложкой,
      favorite-сердцем и меню действий.
- [x] Тесты: theme toggle pure function; Maestro — переключение темы.
- [x] Commit: `feat(mobile): тема и общие компоненты`.

#### Task 6: медиа-URL и авторизованные источники

**Files:** `src/media/source.ts`, тест `source.test.ts`.

- [x] `authSource`, `streamPath`, `thumbPath`, `coverPath`, `imageSource`.
- [x] Тест: headers содержат Bearer после логина; baseUrl без слэша.
- [x] Commit: `feat(mobile): авторизованные URL медиа`.

### Фаза 1 — видео (5–6 дней)

#### Task 7: детали видео

**Files:** `app/video/[id].tsx`, `src/api/media.ts` (detail/subs already shared),
`src/components/VideoMeta.tsx`.

- [x] `useMedia(id)` + экран: постер, title/year/genres/description/artists.
- [x] Кнопки: favorite, add-to-collection, source link, admin actions.
- [x] Состояния loading/404/error.
- [x] Maestro: открыть видео из списка, проверить заголовок и source link.
- [x] Commit: `feat(mobile): экран деталей видео`.

#### Task 8: видеоплеер

**Files:** `src/player/VideoPlayer.tsx`, `useVideoProgress.ts`,
`app/video/[id].tsx`.

- [x] `useVideoPlayer({ uri, headers })`, `VideoView` с native/custom controls.
- [x] Play/pause, seek ±10, таймлайн, скорость 0.5–2, fullscreen, PiP.
- [x] `useKeepAwake` на время playing; ошибка 401 → refresh/retry.
- [x] Тест pure: `formatTime`, clamp seek, speed list.
- [x] Maestro: play/pause, fullscreen, PiP (device).
- [x] Commit: `feat(mobile): видеоплеер с PiP и скоростью`.

#### Task 9: прогресс и resume

**Files:** `src/player/useVideoProgress.ts`.

- [x] Загрузка `/progress/:id`, resume один раз после `loaded`.
- [x] Save каждые 5с + pause/unmount/end; completed ≥90%.
- [x] Reset в 0 удаляет прогресс.
- [x] Vitest: throttle, completed at 90%, 404 → null.
- [x] Maestro: закрыть на 30%, открыть — позиция восстановлена.
- [x] Commit: `feat(mobile): прогресс и продолжение видео`.

#### Task 10: действия и извлечение аудио

**Files:** `src/api/{favorites,collections,extract}.ts` (shared wrappers),
`MediaActionsSheet.tsx`.

- [x] Favorite toggle, add/move collection, source link.
- [x] Extract audio: POST `/media/:id/extract`, poll job, snackbar.
- [x] Только admin; обычному пользователю кнопок нет.
- [x] Commit: `feat(mobile): действия с видео и extract audio`.

### Фаза 2 — аудио (7–9 дней)

#### Task 11: shared audioQueue/lyricsSync

**Files:** `packages/shared/src/core/{audioQueue,lyricsSync}.ts`;
web imports; mobile tests.

- [x] Перенести `startQueue/enqueue/move/remove/repeat/shuffle/next/prev`,
      `shiftPlayedIndices`, `parseLyrics/sync`.
- [x] Web-тесты перевести на shared; mobile добавляет тест на move/played.
- [x] Commit: `refactor(shared): общая очередь и lyrics sync`.

#### Task 12: AudioProvider

**Files:** `src/player/AudioProvider.tsx`, `AudioBar.tsx`.

- [x] `createAudioPlayer(null)`, `replace` при смене трека.
- [x] Очередь: playQueue, enqueue, next/prev, shuffle, repeat off/all/one,
      remove, move, clear, persisted queue в AsyncStorage.
- [x] `useAudioPlayerStatus` → currentTime/duration/playing.
- [x] Тесты pure queue; Maestro: очередь, next, shuffle, repeat.
- [x] Commit: `feat(mobile): аудио-провайдер и очередь`.

#### Task 13: полный плеер, мини-плеер, фон

**Files:** `app/player.tsx`, `AudioBar.tsx`, `useAudioProgress.ts`.

- [x] Мини-бар над табами; tap → полный плеер.
- [x] Play/pause, seek, ±10, скорость, обложка, очередь, favorite.
- [x] `setAudioModeAsync` + `setActiveForLockScreen` с metadata.
- [x] Save progress как у видео; background/lock screen на устройстве.
- [x] Commit: `feat(mobile): аудио-плеер, фон и lock screen`.

#### Task 14: lyrics/translation

**Files:** `app/audio/[id].tsx`, `LyricsView.tsx`.

- [x] `useLyrics`, показ текста/перевода, sync-подсветка текущей строки.
- [x] Пустой перевод — вкладка скрыта; админ может открыть редактор.
- [x] Maestro: трек с lyrics, подсветка при seek.
- [x] Commit: `feat(mobile): lyrics и translation`.

#### Task 15: артисты

**Files:** `app/artists/[id].tsx`, `src/api/media.ts` (audio by artist),
`src/api/metadata.ts` (artists list).

- [x] Список артистов, обложка, favorite, rename (admin).
- [x] Экран артиста: треки через `audioListOptions(..., artistId)`.
- [x] Commit: `feat(mobile): артисты и их треки`.

### Фаза 3 — библиотека (5–6 дней)

#### Task 16: Continue Watching / Favorites

**Files:** `src/api/{progress,favorites}.ts`, `app/(tabs)/video.tsx`,
`audio.tsx`, `SectionHeader`, `MediaCard`.

- [x] Ряды Continue Watching, Favorites, Collections на главных.
- [x] Favorite media/artist toggle; оптимистичное обновление.
- [x] Maestro: favorite появляется в ряду, снятие убирает.
- [x] Commit: `feat(mobile): continue watching и избранное`.

#### Task 17: коллекции

**Files:** `app/(tabs)/library.tsx`, `app/collections/[id].tsx`,
`src/api/collections.ts`, модалки create/rename/move/add.

- [x] Дерево коллекций, breadcrumbs, CRUD.
- [x] Add/move/remove, bulk-выбор и bulk move/remove.
- [x] Stats перед удалением.
- [x] Maestro: создать коллекцию → добавить видео → перенести.
- [x] Commit: `feat(mobile): коллекции и bulk-операции`.

#### Task 18: корзина

**Files:** `app/trash.tsx`, `src/api/trash.ts`.

- [x] Список медиа/коллекций, restore, purge (admin), empty trash.
- [x] Подтверждения; ошибки 404/409.
- [x] Commit: `feat(mobile): корзина`.

### Фаза 4 — загрузка и метаданные (5–6 дней)

#### Task 19: загрузка файлов

**Files:** `app/upload.tsx`, `src/api/upload.ts`, `useUploadQueue.ts`.

- [x] `expo-document-picker` (video/audio/image), multipart POST
      `/media/upload` с Bearer.
- [x] Progress через XHR `upload.onprogress`; 202 → poll job до done/error.
- [x] Очередь 2 параллельно, отмена, retry, локальные уведомления.
- [x] Maestro: выбрать файл → progress → готово в списке.
- [x] Commit: `feat(mobile): загрузка файлов с прогрессом`.

#### Task 20: метаданные, обложка, удаление

**Files:** `src/api/{metadata,cover,media}.ts`,
`EditMetadataScreen.tsx`, `ChangeCoverSheet.tsx`.

- [x] PATCH-семантика: пустые значения очищают; artists список.
- [x] `expo-image-picker` → multipart PUT `/media/:id/cover`.
- [x] Delete → trash, confirm; admin-only.
- [x] Maestro: изменить title, заменить обложку, удалить.
- [x] Commit: `feat(mobile): редактирование метаданных и обложки`.

### Фаза 5 — offline (4–5 дней)

#### Task 21: менеджер скачиваний

**Files:** `src/downloads/{downloadStore,DownloadProvider}.ts`,
`app/downloads.tsx`, `DownloadButton.tsx`.

- [x] `createDownloadResumable` с Authorization на `/media/:id/stream`.
- [x] `.part` → rename, проверка Content-Length, отмена, retry.
- [x] AsyncStorage-индекс: id, title, path, size, updated_at; лимит кеша.
- [x] Индикатор на карточке и в деталях.
- [x] Vitest: filename, quota eviction, index; Maestro: download → airplane.
- [x] Commit: `feat(mobile): offline-скачивание`.

#### Task 22: offline playback и экспорт

**Files:** `src/player/offlineSource.ts`, `app/downloads.tsx`.

- [x] Если файл скачан — player source `file://`, иначе stream.
- [x] `expo-sharing`/SAF для «Сохранить в Files».
- [x] Удаление файла из кеша и очистка индекса.
- [x] Commit: `feat(mobile): offline playback и экспорт`.

### Фаза 6 — полировка и релиз (4–5 дней)

#### Task 23: настройки, тема, i18n

- [x] Server URL, theme (system/light/dark), language ru/en.
- [x] Все новые строки в `src/i18n`, без хардкода.
- [x] Logout очищает кэш, очередь, downloads, токены.
- [x] Commit: `feat(mobile): настройки, тема и i18n`.

#### Task 24: тесты, CI, документация

- [x] Maestro flows в `.maestro/` (созданы в Tasks 4–23); ручной CI job
      на Android-эмуляторе (`.github/workflows/mobile-e2e.yml`, только
      `workflow_dispatch`).
- [x] `npm run test -w mobile`, typecheck/lint, `expo export`.
- [x] Обновить `docs/mobile-parity-plan`, README, AGENTS.
- [x] Commit: `chore(mobile): e2e, CI и документация`.

#### Task 25: релиз

- [ ] `version:sync`, versionCode, dogfood APK arm64.
- [ ] Smoke на устройстве: login, video, audio background, offline.
- [ ] Записать известные ограничения (Expo Go без background).
- [ ] Commit: `chore(mobile): релиз <version>`.

---

## 4. Порядок, зависимости и оценка

1. Фаза 0 — обязательна для всех.
2. После неё видео (Фаза 1) и аудио (Фаза 2) можно вести параллельно,
   но AudioProvider зависит от shared queue (Task 11).
3. Библиотека (Фаза 3) зависит от данных Фаз 0–2.
4. Загрузка/метаданные (Фаза 4) не блокируют плееры.
5. Offline (Фаза 5) — после video/audio, использует их source-хелперы.
6. Полировка/CI — после функционала.

Ориентир для одного разработчика: **6–8 недель**; с параллельным
исполнением видео/аудио — **4–5 недель**.

## 5. Критерии готовности паритета

Критерии закрыты не полностью: нет поиска и сортировки списков
видео/аудио, поэтому DoD паритета не закрыт. Остальные функции реализованы
в Tasks 1–24; финальные чекбоксы (включая device-smoke и dogfood) — после
Task 25 и отдельной задачи на поиск/сортировку.

- [ ] Видео: список, поиск, детали, play/pause/seek/speed/fullscreen/PiP,
      resume, source link, favorite, коллекции, extract, offline.
- [ ] Аудио: список, артисты, мини/полный плеер, очередь (shuffle/repeat/
      reorder), фон/lock screen, lyrics/translation, resume, offline.
- [ ] Библиотека: continue watching, favorites (media/artists), коллекции
      с вложенностью и bulk, корзина.
- [ ] Загрузка: picker, очередь, progress, отмена, retry, уведомления.
- [ ] Метаданные/обложка/удаление; admin-кнопки только админу.
- [ ] Offline: download, play из файла, удаление, лимит кеша, экспорт.
- [ ] ru/en, light/dark/system, ошибки/пустые состояния.
- [ ] Maestro-сценарии и CI-сборка; dogfood APK.

## 6. Риски и меры

| Риск | Мера |
|---|---|
| Expo Go не тянет background audio/PiP | отдельный dev/release build; smoke на устройстве |
| Токен истёк во время видео | source с headers + один retry после refresh |
| Большие файлы/медленная сеть | resumable download, progress, отмена, таймауты |
| Очередь/прогресс рассинхронизируются | shared queue + тесты на move/played; persist |
| RN-компоненты сложно тестировать | Vitest для pure, Maestro для UI |
| Backend-контракты меняются | shared zod-схемы и контрактные тесты |
| Хранилище/downloads растут | лимит кеша, eviction, отображение размера |

## 7. Что не входит

- Админка, мемы, ТВ-режим (в Flutter их нет; остаются web).
- PWA/service worker (mobile — нативное приложение).
- Полный offline каталог коллекций: скачиваются медиа, метаданные
  хранятся в индексе; серверные коллекции в offline доступны только
  для уже скачанных элементов.
