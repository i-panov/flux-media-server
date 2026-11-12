# AGENTS.md — Flux Media Server

**ОБЯЗАТЕЛЬНОЕ ПРАВИЛО: ВСЕГДА ПИСАТЬ ТОЛЬКО ПО-РУССКИ. НИКОГДА НЕ ИСПОЛЬЗОВАТЬ КИТАЙСКИЙ ЯЗЫК. ЭТО ПРАВИЛО КАСАЕТСЯ ВСЕХ ОТВЕТОВ ПОЛЬЗОВАТЕЛЮ, КОММЕНТАРИЕВ И ЛЮБОГО ТЕКСТА.**

Self-hosted media streaming server: Go backend (Fiber + GORM + SQLite),
React web client и Expo mobile client. Общий код — `packages/shared`.
Legacy `frontend/` на Flutter не развивается; он оставлен только как
справочник функций.

## Структура

```
backend/            Go API, очереди, сканер, SQLite
web/                React 19 + TypeScript + Vite + Mantine + TanStack
mobile/             Expo + expo-router + React Native
packages/shared/    платформенно-нейтральный TS (api, media, query, storage)
docs/               отчёты и решения; docs/superpowers — локальный архив
frontend/           legacy Flutter, только reference
```

## Команды

### Установка (npm workspaces)

```bash
npm ci                  # один раз из корня; hoist в корневой node_modules
```

Требуется Node `>=22`. TypeScript закреплён на v6, пока typescript-eslint
не поддерживает v7.

### Backend (`backend/`)

```bash
cd backend
go run ./cmd/server -config configs/config.yaml
go test ./internal/... -count=1       # in-memory SQLite, ffmpeg не обязателен
CGO_ENABLED=1 go build -o flux-server ./cmd/server
```

- Module: `flux`, не `flux-media-server`.
- CGO обязателен для `mattn/go-sqlite3`.
- SQLite WAL, `busy_timeout=5000`, `_txlock=immediate`.
- Go 1.25 (см. `go.mod`).

### Web (`web/`)

```bash
cd web
npm run dev            # Vite :5173, proxy /api → :8080
npm run build          # tsr generate + tsc + vite build
npm run typecheck
npm run lint           # Biome + ESLint, должен быть чистым
npm run lint:deadcode  # Knip
npm run test           # Vitest
npm run test:e2e       # Playwright, Chromium
npm run size           # size-limit
```

- `src/routeTree.gen.ts` генерируется `tsr`; коммитится.
- PWA service worker `src/sw.ts` обязан сохранять литерал
  `self.__WB_MANIFEST`.
- API same-origin (`/api`), `VITE_API_BASE` не используется.
- Offline/downloads в web не поддерживаются осознанно.

### Shared (`packages/shared/`)

```bash
npm run typecheck -w @flux/shared
npm run lint -w @flux/shared
npm run test -w @flux/shared
```

- Чистый TS без JSX, DOM, React Native и localStorage.
- Рантайм-зависимости: `zod`, `@tanstack/react-query`, `toqr` (QR-матрица).
- Web-модули `src/core/*` — тонкие именованные реэкспорты shared.

### Mobile (`mobile/`)

```bash
cd mobile
npx expo start                 # Expo Go / эмулятор
npm run typecheck
npm run lint
npm run test                   # Vitest: pure-логика, i18n, download index
npm run version:sync           # package.json → app.json + version-code
npm run version:sync -- --check
EXPO_OFFLINE=1 npx expo install --check
npx expo config --type introspect
npx expo export --platform android --output-dir dist
maestro test .maestro/tabs.yaml # нужны Maestro CLI + adb + эмулятор/устройство
```

- `android/` и `ios/` генерируются (`expo prebuild`) и в git не входят.
- Сессия (access/refresh) — только SecureStore; OTP-вход и QR/device-code
  (TV/веб, подтверждение через `/activate`); `AuthGate`
  защищает табы, публичная настройка сервера — `/server` (`app/server.tsx`,
  доступна до входа). Logout очищает query cache, очередь, downloads,
  токены и persisted state.
- Анализаторы: biome (extends web) + `eslint-config-expo` + sonarjs.
- `@flux/shared` — единственный источник API/очереди/lyrics-логики;
  не дублировать fetch-контракты в mobile.
- Поиск и сортировка списков видео/аудио реализованы в mobile 0.1.31, текущий релиз 0.1.34:
  `useVideoList(q, sort)`/`useAudioList(q, sort)`, debounce 300 мс,
  переключатель asc/desc и отдельные пустые состояния.
- Maestro: 19 flow в `.maestro/` (tabs, theme, video, audio, lyrics,
  artists, collections, favorites, search, trash, upload, metadata,
  downloads).
  Ручной workflow `.github/workflows/mobile-e2e.yml` поднимает Android
  emulator, backend и прогоняет `tabs.yaml`/`theme.yaml`; в push/PR не
  входит (`workflow_dispatch`). CI `shared-mobile` проверяет
  `expo install --check` и `expo config --type introspect`.
- Dogfood-APK (arm64, ~30 МБ вместо ~92 МБ universal):
  `EXPO_PUBLIC_API_BASE=<url> ORG_GRADLE_PROJECT_reactNativeArchitectures=arm64-v8a ./gradlew assembleRelease`
  из `mobile/android` (JDK 17 + `local.properties` с SDK/NDK локально).

## Архитектура

### Backend (`backend/internal/`)

- `app/app.go` — DI, маршруты, lifecycle (composition root).
- `config/` — YAML-конфиг и дефолты.
- `handlers/` — Fiber-хендлеры, `response.Error()`/`response.OK()`.
- `services/` — бизнес-логика; интерфейсы в `services/interfaces.go`.
- `repository/` — доступ к данным; интерфейсы в `repository/interfaces.go`,
  ad-hoc миграции в `db.go` с версией в `schema_migrations`.
- `models/` — GORM-модели.
- `models/setting.go`, `repository/setting.go` — key/value-настройки
  инстанса в таблице `settings`; persisted-значение
  (`storage.auto_cleanup_originals`) перекрывает YAML, конфиг остаётся
  fallback'ом.
- `middleware/` — JWT/куки, admin, security headers.
- `email/` — SMTP/OTP.
- `metadata/` — разбор имён и source URL.
- `response/` — JSON-хелперы.

Очереди upload/transcode/extract стартуют после создания каталогов и
валидации `contentDirs`; `Shutdown` ждёт скан и backfill dimensions.

### Web (`web/src/`)

- `features/` — video, audio, player, collections, favorites, upload, admin,
  memes, trash, tv, settings, media.
- `api/` — TanStack Query-хуки и zod-схемы.
- `routes/` — TanStack Router; `/admin` закрыт `beforeLoad`.
- `core/` — реэкспорты `@flux/shared`.
- `locales/` — ru/en; fallback `en`.
- `e2e/` — Playwright, API стабится.

### Mobile (`mobile/`)

- `app/` — expo-router: `(tabs)/{video,audio,library,settings}`, `index`,
  `login`, `server`, `video/[id]`, `audio/[id]`, `player`,
  `artists/{index,[id]}`, `collections/[id]`, `upload`, `trash`,
  `downloads`, `activate`, `devices`, `media/[id]/edit`.
- `src/auth/` — сессия, logout, `SessionResetProvider`, `AuthGate`.
- `src/api/` — shared `CoreFetcher` + query-хуки: media, favorites,
  collections, progress, lyrics, upload, trash, metadata, cover, extract.
- `src/media/` — `authSource`/`imageSource`, `useAuthImageSource`.
- `src/player/` — `AudioProvider`, `AudioBar`, `VideoPlayer`, очередь,
  прогресс, offline-source.
- `src/downloads/` — `DownloadProvider`, индекс, лимит кеша, экспорт.
- `src/collections/`, `src/artists/`, `src/upload/`, `src/lyrics/` —
  доменная логика и чистые хелперы.
- `src/theme/` — токены и `ThemeProvider`; `src/i18n/` — ru/en.
- `src/components/` — общие экраны, карточки, диалоги, состояния.
- `.maestro/` — UI-flow; `.github/workflows/mobile-e2e.yml` — ручной
  Android emulator прогон (в push/PR не входит).

### Shared (`packages/shared/src/`)

- `api/` — `apiFetch`/`apiFetchBlob`, `ApiError`, auth-контракт, transport
  (web cookies / mobile Bearer), `RefreshError`.
- `core/` — media-схемы, fetch, format.
- `query.ts`, `storage.ts` — общий query client и `KeyValueStore`.

## Ключевые паттерны

- Backend-хендлеры принимают `*fiber.Ctx`, репозитории — `c.UserContext()`.
- Конструкторы: `NewXxx(deps) *Xxx`.
- Ошибки API: `response.Error`; ошибки репозитория мапятся `repoError`.
- Web-запросы — только через `apiFetch`/`apiFetchBlob`; сырой `fetch` в
  компонентах запрещён (кроме транспорта).
- Mobile-токены (access/refresh) — только SecureStore; `AuthGate` защищает
  табы (включая Settings), публичная настройка сервера — `/server`.
- Mobile-запросы — через shared `apiFetch`/`CoreFetcher`; очередь, progress
  и lyrics-логика не дублируются в mobile.
- Shared не импортирует React/DOM/RN; платформенные различия — через
  `AuthTransport`/`KeyValueStore`.

## Версионирование

- `backend/`: patch в `backend/cmd/server/main.go` (`1.0.x`).
- `web/`: patch в `web/package.json` (`0.x.y`).
- `mobile/`: patch в `mobile/package.json`; `app.json` и `mobile/version-code`
  синхронизируются `npm run version:sync`, CI проверяет `--check`.
- `packages/shared/`: `0.x.y`; patch на совместимые изменения, minor на
  ломающие транспорт/модели. При бампе обновить зависимости web/mobile и
  `package-lock.json`.
- Legacy `frontend/`: если всё же трогаете, patch в `pubspec.yaml` и build
  number после `+`.
- Версия backend отдаётся `GET /api/health` (`version`) и видна в настройках.

## Конфиг и Docker

- Конфиг: `backend/configs/config.yaml` (fallback `$CONFIG_PATH`), пример —
  `config.example.yaml`.
- `auth.jwt_secret` ≥32 символов; `debug + allow_unknown_email` возвращает OTP
  в ответе.
- `server.trusted_proxies` — CIDR/IP прокси, от которых принимается XFF.
- Docker-контекст — корень репо: `cd backend && docker compose up -d`.
- Внутри контейнера порт `8080`; host — `${HOST_PORT:-8095}`.
- Данные: `/app/data`; медиа — каталог библиотеки (rw), конфиг монтируется ro.
- Образ включает ffmpeg/ca-certificates и собранный web (`/app/web`,
  включается `web_dist`).

## Проверки перед коммитом

```bash
(cd backend && go test ./internal/... -count=1)
(cd web && npm run typecheck && npm run lint && npm run test && npm run lint:deadcode)
npm run test -w @flux/shared
npm run typecheck -w mobile && npm run lint -w mobile && npm run test -w mobile
(cd mobile && EXPO_OFFLINE=1 npx expo install --check && npx expo config --type introspect)
```

E2E и production build — перед крупными изменениями web. Mobile E2E —
ручной workflow `mobile-e2e.yml`; Maestro-flow требуют эмулятора/устройства
и в обычный CI не входят.

## Документация

- `README.md` — быстрый старт и обзор.
- `AGENTS.md` — этот файл.
- `docs/README.md` — индекс документов.
- `docs/review-2026-11-09.md` — итоговый отчёт ревью и журнал.
- `docs/mobile-parity-plan-2026-11-09.md` — план паритета mobile.
- `docs/mobile-parity-handoff-2026-11-10.md` — исторический handoff и
  актуальный статус mobile.
- `docs/mobile-release-notes-2026-11-11.md` — release notes mobile 0.1.34.
