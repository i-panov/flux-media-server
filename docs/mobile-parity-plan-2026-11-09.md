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

---

## 0. Текущее состояние и границы паритета

Сейчас mobile умеет: OTP-вход, SecureStore, настройку URL, health,
списки видео/аудио с пагинацией, logout, i18n.

Цель паритета — функции Flutter, **без** админки, мемов и ТВ-режима
(в Flutter их нет; web-админка/мемы/ТВ остаются web-only).

| Блок | Flutter | Mobile сейчас | Цель |
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

## 1. Решения и зависимости

### Навигация

- `app/_layout.tsx` — провайдеры: Query, Audio, Downloads, Theme.
- `app/(tabs)/_layout.tsx` — табы **Видео / Аудио / Библиотека / Настройки**.
- `app/login.tsx`, `app/server.tsx` — вне табов; сервер доступен без входа.
- Stack-экраны: `video/[id]`, `audio/[id]`, `player`, `artists/[id]`,
  `collections/[id]`, `upload`, `trash`, `downloads`, `settings/server`.
- `AuthGate` остаётся на защищённых экранах; `settings/server` — публичный.

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
mobile/app/settings/server.tsx
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

- [ ] Вынести zod-схемы и fetch-функции без React-хуков.
- [ ] Web-хуки оставить обёртками над shared-функциями; ключи query не менять.
- [ ] Тесты shared: 404 progress → null, 409 favorite → stale, lyrics 404 → null.
- [ ] `npm run test -w @flux/shared`, web `tsc/vitest` — зелёные.
- [ ] Commit: `refactor(shared): вынести progress/favorites/lyrics`.

#### Task 2: перенести collections в shared

**Files:** `packages/shared/src/api/collections.ts`,
`web/src/api/collections.ts`, тесты.

- [ ] Перенести схемы, list/items/create/rename/delete/add/move/remove/bulk/stats.
- [ ] Web-хуки инвалидации оставить в web, чтобы не менять поведение.
- [ ] Тесты: bulk-ответ, частичный skipped, 404/409.
- [ ] Commit: `refactor(shared): вынести collections API`.

#### Task 3: зависимости и конфиг Expo

**Files:** `mobile/package.json`, `mobile/app.json`, `mobile/tsconfig.json`.

- [ ] Добавить `expo-video`, `expo-audio`, `expo-file-system`, `expo-image`,
      `expo-document-picker`, `expo-image-picker`, `expo-keep-awake`,
      `@react-native-async-storage/async-storage`.
- [ ] `app.json`: `userInterfaceStyle: "automatic"`, плагины `expo-audio`
      (background) и `expo-video` (PiP).
- [ ] `npx expo prebuild --clean` на dev-машине; проверить манифест Android
      (foreground service) и iOS background mode.
- [ ] `npm run typecheck -w mobile`, `expo export` — ok.
- [ ] Commit: `chore(mobile): добавить видео/аудио/offline зависимости`.

#### Task 4: табы и каркас навигации

**Files:** `mobile/app/_layout.tsx`, `mobile/app/(tabs)/_layout.tsx`,
`mobile/app/(tabs)/{video,audio,library,settings}.tsx`, `app/server.tsx`.

- [ ] Табы: Видео, Аудио, Библиотека, Настройки; иконки lucide-react-native
      или expo-symbols.
- [ ] `AuthGate` на табах; `/server` доступен без сессии.
- [ ] Сохранить deep links `/video`, `/audio`, `/settings`.
- [ ] Maestro smoke: login → табы → settings.
- [ ] Commit: `feat(mobile): табы и каркас навигации`.

#### Task 5: тема и общие компоненты

**Files:** `src/theme/tokens.ts`, `ThemeProvider.tsx`,
`src/components/{Screen,SectionHeader,EmptyState,ErrorState,MediaCard,MediaGrid}.tsx`.

- [ ] Токены: фон/текст/акцент, light/dark, отступы, радиусы.
- [ ] `ThemeProvider` читает system + настройку пользователя из AsyncStorage.
- [ ] Общие состояния: loading/empty/error/retry; карточка с обложкой,
      favorite-сердцем и меню действий.
- [ ] Тесты: theme toggle pure function; Maestro — переключение темы.
- [ ] Commit: `feat(mobile): тема и общие компоненты`.

#### Task 6: медиа-URL и авторизованные источники

**Files:** `src/media/source.ts`, тест `source.test.ts`.

- [ ] `authSource`, `streamPath`, `thumbPath`, `coverPath`, `imageSource`.
- [ ] Тест: headers содержат Bearer после логина; baseUrl без слэша.
- [ ] Commit: `feat(mobile): авторизованные URL медиа`.

### Фаза 1 — видео (5–6 дней)

#### Task 7: детали видео

**Files:** `app/video/[id].tsx`, `src/api/media.ts` (detail/subs already shared),
`src/components/VideoMeta.tsx`.

- [ ] `useMedia(id)` + экран: постер, title/year/genres/description/artists.
- [ ] Кнопки: favorite, add-to-collection, source link, admin actions.
- [ ] Состояния loading/404/error.
- [ ] Maestro: открыть видео из списка, проверить заголовок и source link.
- [ ] Commit: `feat(mobile): экран деталей видео`.

#### Task 8: видеоплеер

**Files:** `src/player/VideoPlayer.tsx`, `useVideoProgress.ts`,
`app/video/[id].tsx`.

- [ ] `useVideoPlayer({ uri, headers })`, `VideoView` с native/custom controls.
- [ ] Play/pause, seek ±10, таймлайн, скорость 0.5–2, fullscreen, PiP.
- [ ] `useKeepAwake` на время playing; ошибка 401 → refresh/retry.
- [ ] Тест pure: `formatTime`, clamp seek, speed list.
- [ ] Maestro: play/pause, fullscreen, PiP (device).
- [ ] Commit: `feat(mobile): видеоплеер с PiP и скоростью`.

#### Task 9: прогресс и resume

**Files:** `src/player/useVideoProgress.ts`.

- [ ] Загрузка `/progress/:id`, resume один раз после `loaded`.
- [ ] Save каждые 5с + pause/unmount/end; completed ≥90%.
- [ ] Reset в 0 удаляет прогресс.
- [ ] Vitest: throttle, completed at 90%, 404 → null.
- [ ] Maestro: закрыть на 30%, открыть — позиция восстановлена.
- [ ] Commit: `feat(mobile): прогресс и продолжение видео`.

#### Task 10: действия и извлечение аудио

**Files:** `src/api/{favorites,collections,extract}.ts` (shared wrappers),
`MediaActionsSheet.tsx`.

- [ ] Favorite toggle, add/move collection, source link.
- [ ] Extract audio: POST `/media/:id/extract`, poll job, snackbar.
- [ ] Только admin; обычному пользователю кнопок нет.
- [ ] Commit: `feat(mobile): действия с видео и extract audio`.

### Фаза 2 — аудио (7–9 дней)

#### Task 11: shared audioQueue/lyricsSync

**Files:** `packages/shared/src/core/{audioQueue,lyricsSync}.ts`;
web imports; mobile tests.

- [ ] Перенести `startQueue/enqueue/move/remove/repeat/shuffle/next/prev`,
      `shiftPlayedIndices`, `parseLyrics/sync`.
- [ ] Web-тесты перевести на shared; mobile добавляет тест на move/played.
- [ ] Commit: `refactor(shared): общая очередь и lyrics sync`.

#### Task 12: AudioProvider

**Files:** `src/player/AudioProvider.tsx`, `AudioBar.tsx`.

- [ ] `createAudioPlayer(null)`, `replace` при смене трека.
- [ ] Очередь: playQueue, enqueue, next/prev, shuffle, repeat off/all/one,
      remove, move, clear, persisted queue в AsyncStorage.
- [ ] `useAudioPlayerStatus` → currentTime/duration/playing.
- [ ] Тесты pure queue; Maestro: очередь, next, shuffle, repeat.
- [ ] Commit: `feat(mobile): аудио-провайдер и очередь`.

#### Task 13: полный плеер, мини-плеер, фон

**Files:** `app/player.tsx`, `AudioBar.tsx`, `useAudioProgress.ts`.

- [ ] Мини-бар над табами; tap → полный плеер.
- [ ] Play/pause, seek, ±10, скорость, обложка, очередь, favorite.
- [ ] `setAudioModeAsync` + `setActiveForLockScreen` с metadata.
- [ ] Save progress как у видео; background/lock screen на устройстве.
- [ ] Commit: `feat(mobile): аудио-плеер, фон и lock screen`.

#### Task 14: lyrics/translation

**Files:** `app/audio/[id].tsx`, `LyricsView.tsx`.

- [ ] `useLyrics`, показ текста/перевода, sync-подсветка текущей строки.
- [ ] Пустой перевод — вкладка скрыта; админ может открыть редактор.
- [ ] Maestro: трек с lyrics, подсветка при seek.
- [ ] Commit: `feat(mobile): lyrics и translation`.

#### Task 15: артисты

**Files:** `app/artists/[id].tsx`, `src/api/media.ts` (audio by artist),
`src/api/metadata.ts` (artists list).

- [ ] Список артистов, обложка, favorite, rename (admin).
- [ ] Экран артиста: треки через `audioListOptions(..., artistId)`.
- [ ] Commit: `feat(mobile): артисты и их треки`.

### Фаза 3 — библиотека (5–6 дней)

#### Task 16: Continue Watching / Favorites

**Files:** `src/api/{progress,favorites}.ts`, `app/(tabs)/video.tsx`,
`audio.tsx`, `SectionHeader`, `MediaCard`.

- [ ] Ряды Continue Watching, Favorites, Collections на главных.
- [ ] Favorite media/artist toggle; оптимистичное обновление.
- [ ] Maestro: favorite появляется в ряду, снятие убирает.
- [ ] Commit: `feat(mobile): continue watching и избранное`.

#### Task 17: коллекции

**Files:** `app/(tabs)/library.tsx`, `app/collections/[id].tsx`,
`src/api/collections.ts`, модалки create/rename/move/add.

- [ ] Дерево коллекций, breadcrumbs, CRUD.
- [ ] Add/move/remove, bulk-выбор и bulk move/remove.
- [ ] Stats перед удалением.
- [ ] Maestro: создать коллекцию → добавить видео → перенести.
- [ ] Commit: `feat(mobile): коллекции и bulk-операции`.

#### Task 18: корзина

**Files:** `app/trash.tsx`, `src/api/trash.ts`.

- [ ] Список медиа/коллекций, restore, purge (admin), empty trash.
- [ ] Подтверждения; ошибки 404/409.
- [ ] Commit: `feat(mobile): корзина`.

### Фаза 4 — загрузка и метаданные (5–6 дней)

#### Task 19: загрузка файлов

**Files:** `app/upload.tsx`, `src/api/upload.ts`, `useUploadQueue.ts`.

- [ ] `expo-document-picker` (video/audio/image), multipart POST
      `/media/upload` с Bearer.
- [ ] Progress через XHR `upload.onprogress`; 202 → poll job до done/error.
- [ ] Очередь 2 параллельно, отмена, retry, локальные уведомления.
- [ ] Maestro: выбрать файл → progress → готово в списке.
- [ ] Commit: `feat(mobile): загрузка файлов с прогрессом`.

#### Task 20: метаданные, обложка, удаление

**Files:** `src/api/{metadata,cover,media}.ts`,
`EditMetadataScreen.tsx`, `ChangeCoverSheet.tsx`.

- [ ] PATCH-семантика: пустые значения очищают; artists список.
- [ ] `expo-image-picker` → multipart PUT `/media/:id/cover`.
- [ ] Delete → trash, confirm; admin-only.
- [ ] Maestro: изменить title, заменить обложку, удалить.
- [ ] Commit: `feat(mobile): редактирование метаданных и обложки`.

### Фаза 5 — offline (4–5 дней)

#### Task 21: менеджер скачиваний

**Files:** `src/downloads/{downloadStore,DownloadProvider}.ts`,
`app/downloads.tsx`, `DownloadButton.tsx`.

- [ ] `createDownloadResumable` с Authorization на `/media/:id/stream`.
- [ ] `.part` → rename, проверка Content-Length, отмена, retry.
- [ ] AsyncStorage-индекс: id, title, path, size, updated_at; лимит кеша.
- [ ] Индикатор на карточке и в деталях.
- [ ] Vitest: filename, quota eviction, index; Maestro: download → airplane.
- [ ] Commit: `feat(mobile): offline-скачивание`.

#### Task 22: offline playback и экспорт

**Files:** `src/player/offlineSource.ts`, `app/downloads.tsx`.

- [ ] Если файл скачан — player source `file://`, иначе stream.
- [ ] `expo-sharing`/SAF для «Сохранить в Files».
- [ ] Удаление файла из кеша и очистка индекса.
- [ ] Commit: `feat(mobile): offline playback и экспорт`.

### Фаза 6 — полировка и релиз (4–5 дней)

#### Task 23: настройки, тема, i18n

- [ ] Server URL, theme (system/light/dark), language ru/en.
- [ ] Все новые строки в `src/i18n`, без хардкода.
- [ ] Logout очищает кэш, очередь, downloads, токены.
- [ ] Commit: `feat(mobile): настройки, тема и i18n`.

#### Task 24: тесты, CI, документация

- [ ] Maestro flows в `.maestro/`; CI job на Android-эмуляторе.
- [ ] `npm run test -w mobile`, typecheck/lint, `expo export`.
- [ ] Обновить `docs/mobile-parity-plan`, README, AGENTS.
- [ ] Commit: `chore(mobile): e2e, CI и документация`.

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
