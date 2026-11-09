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
- Рантайм-зависимости: `zod`, `@tanstack/react-query`.
- Web-модули `src/core/*` — тонкие именованные реэкспорты shared.

### Mobile (`mobile/`)

```bash
cd mobile
npx expo start                 # Expo Go / эмулятор
npm run typecheck
npm run lint
npm run test                   # Vitest, i18n
npm run version:sync           # package.json → app.json + version-code
npm run version:sync -- --check
npx expo export --platform android --output-dir dist
```

- `android/` и `ios/` генерируются и в git не входят.
- OTP-вход через SecureStore; сервер задаётся в Settings.
- Анализаторы: biome (extends web) + `eslint-config-expo` + sonarjs.
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

- `app/` — экраны expo-router: `login`, `index`, `video`, `audio`, `settings`.
- `src/auth/` — сессия, logout, `AuthGate`.
- `src/api/` — shared `CoreFetcher` + query-хуки.
- `src/i18n/` — ru/en, реактивный `useLanguage`.
- `src/components/` — `AuthGate`, `MediaList`.

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
- Mobile-токены — только SecureStore; `AuthGate` защищает экраны, Settings
  доступен без сессии.
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
```

E2E и production build — перед крупными изменениями web.

## Документация

- `README.md` — быстрый старт и обзор.
- `AGENTS.md` — этот файл.
- `docs/README.md` — индекс документов.
- `docs/review-2026-11-09.md` — итоговый отчёт ревью и журнал.
