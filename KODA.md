# KODA.md — Flux Media Server

**ОБЯЗАТЕЛЬНОЕ ПРАВИЛО: ВСЕГДА ПИСАТЬ ТОЛЬКО ПО-РУССКИ. НИКОГДА НЕ ИСПОЛЬЗОВАТЬ КИТАЙСКИЙ ЯЗЫК. ЭТО ПРАВИЛО КАСАЕТСЯ ВСЕХ ОТВЕТОВ ПОЛЬЗОВАТЕЛЮ, КОММЕНТАРИЕВ И ЛЮБОГО ТЕКСТА.**

## Обзор проекта

**Flux Media Server** — self-hosted медиа-сервер для стриминга видео и аудио. Go-бэкенд (Fiber), web-клиент (React + Mantine), mobile-клиент (Expo + React Native) и общий пакет `@flux/shared`. Legacy `frontend/` на Flutter оставлен только как справочник функций и не развивается.

## Структура репозитория

```
flux-media-server/
├── backend/                  — Go-бэкенд (Fiber v2 + GORM + SQLite)
│   ├── cmd/server/main.go    — точка входа, флаги -config, -version
│   ├── configs/config.yaml   — конфигурация (сервер, БД, auth, scanner, media)
│   ├── internal/
│   │   ├── app/app.go        — сборка DI, маршруты, lifecycle
│   │   ├── config/           — YAML-конфигурация
│   │   ├── email/            — SMTP-клиент для отправки OTP-кодов
│   │   ├── handlers/         — HTTP-обработчики (auth, media, library, upload, progress, metadata, thumb, artist, collection, favorite, lyrics)
│   │   ├── metadata/         — парсинг имён файлов, извлечение метаданных
│   │   ├── middleware/       — JWT auth middleware, security headers, admin
│   │   ├── models/           — GORM-модели: Media, Metadata, User, WatchProgress, MediaLibrary, Artist, Collection, CollectionItem, Favorite, Lyrics, RefreshToken, MediaType
│   │   ├── repository/       — интерфейсы и реализации репозиториев (SQLite через GORM)
│   │   └── services/         — бизнес-логика: scanner, watcher, streamer, thumbnail, auth (JWT, OTP), upload_queue
│   ├── Dockerfile            — multi-stage build (golang:1.25-alpine → alpine:3.22 + ffmpeg)
│   └── docker-compose.yaml   — проброс 8080/8095, volume для data и media
│
├── web/                      — React 19 + TypeScript + Vite + Mantine
│   ├── src/features/         — video, audio, collections, favorites, player, upload, admin, settings
│   ├── src/api/              — TanStack Query хуки и zod-схемы
│   ├── src/routes/           — TanStack Router (routeTree.gen.ts генерируется)
│   └── e2e/                  — Playwright
├── mobile/                   — Expo + expo-router + React Native
│   ├── app/                  — экраны (login, video, audio, settings)
│   └── src/                  — auth, api, i18n, компоненты
├── packages/shared/          — платформенно-нейтральный TS: api, media/format, query
└── frontend/                 — legacy Flutter, только справочник функций
```

## Бэкенд

### Технологии
- **Язык:** Go 1.25
- **Веб-фреймворк:** Fiber v2
- **ORM:** GORM + SQLite (WAL mode, busy_timeout=5000)
- **Аутентификация:** JWT + Refresh Tokens + OTP через email (SMTP)
- **Медиа:** ffprobe (через go-ffprobe), ffmpeg (для миниатюр), dhowden/tag (аудио-теги)
- **Файловый мониторинг:** fsnotify
- **Контейнер:** Docker (Alpine + ffmpeg)

### Модули Go
- `module flux`
- Ключевые зависимости: gofiber/fiber/v2, gorm.io/gorm, gorm.io/driver/sqlite, golang-jwt/jwt/v5, fsnotify/fsnotify, vansane/go-ffprobe.v2, dhowden/tag

### Стиль кода (Go)
- Пакеты: `internal/` с чётким разделением (handlers, services, repository, models, config, middleware)
- Интерфейсы репозиториев в `repository/interfaces.go`, сервисов — в `services/interfaces.go`
- Конструкторы: `NewXxx(deps) *Xxx`
- Обработчики принимают `*fiber.Ctx`, используют `response.Error()` и `response.OK()` хелперы
- Контекст: `c.UserContext()` передаётся в репозитории
- Конфигурация: YAML, загружается через `config.Load(path)`, дефолты в `config.Load()`
- Модели GORM с JSON-тегами, `gorm:"uniqueIndex"` / `gorm:"index"` аннотациями
- Soft delete через `gorm.DeletedAt`
- FK-ассоциации с каскадными удалениями (`constraint:OnUpdate:CASCADE,OnDelete:CASCADE`)

### API эндпоинты

| Метод | Путь | Описание | Auth | Admin |
|-------|------|----------|------|-------|
| GET | `/api/health` | Health check | — | — |
| POST | `/api/auth/request-code` | Запрос OTP-кода | — | — |
| POST | `/api/auth/verify-code` | Проверка OTP, выдача JWT | — | — |
| POST | `/api/auth/refresh` | Обновление JWT через refresh token | — | — |
| GET | `/api/auth/me` | Текущий пользователь | JWT | — |
| POST | `/api/auth/logout` | Выход (инвалидация refresh token) | JWT | — |
| GET | `/api/media` | Список медиа (фильтры: type, year, q, limit, offset) | JWT | — |
| GET | `/api/media/bulk` | Bulk-загрузка списка медиа | JWT | — |
| GET | `/api/media/:id` | Получить медиа по ID | JWT | — |
| POST | `/api/media` | Создать запись медиа | JWT | ✓ |
| POST | `/api/media/upload` | Загрузка файла (multipart, library_id + file, лимит 2GB) | JWT | ✓ |
| GET | `/api/media/uploads/:id` | Статус асинхронной загрузки | JWT | ✓ |
| DELETE | `/api/media/uploads/:id` | Отмена асинхронной загрузки | JWT | ✓ |
| POST | `/api/media/check-hash` | Проверка хэша файла | JWT | — |
| PUT | `/api/media/:id` | Обновить медиа | JWT | ✓ |
| DELETE | `/api/media/:id` | Удалить медиа (soft delete) | JWT | ✓ |
| GET | `/api/media/:id/stream` | Стриминг файла (Range support) | JWT | — |
| GET | `/api/media/:id/thumb` | Миниатюра | JWT | — |
| GET | `/api/media/:id/cover` | Обложка (для аудио) | JWT | — |
| PUT | `/api/media/:id/cover` | Загрузка обложки (multipart) | JWT | ✓ |
| GET | `/api/libraries` | Список библиотек | JWT | — |
| POST | `/api/libraries` | Создать библиотеку | JWT | — |
| PUT | `/api/libraries/:id` | Обновить библиотеку | JWT | — |
| DELETE | `/api/libraries/:id` | Удалить библиотеку | JWT | — |
| POST | `/api/libraries/:id/scan` | Запуск сканирования | JWT | — |
| GET | `/api/libraries/:id/scan-status` | Статус сканирования | JWT | — |
| GET | `/api/progress` | Прогресс просмотра пользователя | JWT | — |
| PUT | `/api/progress/:mediaId` | Обновить прогресс | JWT | — |
| DELETE | `/api/progress/:mediaId` | Удалить прогресс | JWT | — |
| GET | `/api/metadata/search` | Поиск метаданных | JWT | — |
| POST | `/api/metadata/:mediaId/refresh` | Обновить метаданные | JWT | ✓ |
| PUT | `/api/metadata/:mediaId` | Изменить метаданные | JWT | ✓ |
| GET | `/api/favorites` | Список избранного | JWT | — |
| POST | `/api/media/:id/favorite` | Добавить в избранное (медиа) | JWT | — |
| DELETE | `/api/media/:id/favorite` | Удалить из избранного (медиа) | JWT | — |
| POST | `/api/favorites/artist` | Добавить в избранное (артист) | JWT | — |
| DELETE | `/api/favorites/artist` | Удалить из избранного (артист) | JWT | — |
| GET | `/api/artists` | Список артистов | JWT | — |
| PUT | `/api/artists/:id` | Обновить артиста | JWT | ✓ |
| POST | `/api/artists/:id/cover` | Загрузка обложки артиста | JWT | ✓ |
| GET | `/api/artists/:id/cover` | Обложка артиста | JWT | — |
| POST | `/api/collections` | Создать коллекцию | JWT | — |
| GET | `/api/collections` | Список коллекций | JWT | — |
| PUT | `/api/collections/:id` | Обновить коллекцию | JWT | — |
| DELETE | `/api/collections/:id` | Удалить коллекцию | JWT | — |
| POST | `/api/collections/:id/items` | Добавить элемент в коллекцию | JWT | — |
| DELETE | `/api/collections/:id/items/:mediaId` | Удалить элемент из коллекции | JWT | — |
| GET | `/api/collections/:id/items` | Список элементов коллекции | JWT | — |
| GET | `/api/media/:id/lyrics` | Получить текст песни | JWT | — |
| PUT | `/api/media/:id/lyrics` | Сохранить/обновить текст песни | JWT | ✓ |

### Модели данных

- **User** — id, email, timestamps
- **Media** — id, title, filename, year, description, type (video/audio), artists (many2many), album, genre, duration, filePath, fileSize, fileHash (SHA-256), quickHash, thumbnailURL, coverURL, metadataID, timestamps, soft delete
- **Metadata** — id, externalID, source (tmdb/tvdb), title, year, description, posterURL, backdropURL, rating, genres (JSON), cast (JSON), timestamps
- **MediaLibrary** — id, name, path, type (video/audio), enabled, scanInterval, timestamps
- **WatchProgress** — id, userID, mediaID, position, duration, completed, updatedAt
- **Artist** — id, name (unique), hasCover, timestamps
- **MediaArtist** — join-таблица Media ↔ Artist с позицией (many2many)
- **Collection** — id, userID, name, type (video/audio), timestamps
- **CollectionItem** — id, collectionID, mediaID, position (unique composite), addedAt
- **Favorite** — id, userID, mediaID (nullable), artistID (nullable), check constraint на одиночную цель, timestamps
- **Lyrics** — id, mediaID (unique), lyricsText, translation, syncData (JSON), source, timestamps
- **RefreshToken** — id, userID, token (unique), expiresAt (indexed), createdAt
- **MediaType** — enum: "video", "audio"

### Сервисы

- **ScannerService** — сканирование библиотек: walk по директории, хэширование (SHA-256 полный + quick hash 1MB head + 1MB tail), извлечение метаданных через ffprobe и теги, генерация миниатюр
- **WatcherService** — fsnotify мониторинг папок, debounce 2с, автосканирование при появлении новых файлов
- **StreamerService** — стриминг файлов с поддержкой HTTP Range
- **ThumbnailService** — генерация миниатюр через ffmpeg
- **JWTService** — выпуск и валидация JWT-токенов + refresh tokens
- **OTPStore** — генерация и хранение OTP-кодов с TTL
- **UploadQueue** — асинхронная очередь обработки загрузок (воркеры: хэширование, ffprobe, ffmpeg)

### Конфигурация (config.yaml)

```yaml
server:       host, port (8080), debug, cors_origins, max_upload_size
database:     path (./data/flux.db)
auth:         jwt_secret (≥32 chars), jwt_expiry (hours), refresh_expiry (hours), code_length, code_expiry, max_otp_entries, allowed_emails, allow_unknown_email, smtp (host, port, username, password, from, require_tls, implicit_tls)
scanner:      enabled, interval (min), watch_enabled
media:        thumbnail_path, video_path, audio_path
rate_limiter: max (requests), expiration (seconds)
```

### Запуск бэкенда

```bash
# Локально
cd backend
go run ./cmd/server -config configs/config.yaml

# Docker
docker compose up -d
```

## Клиенты

### Web (`web/`)
- React 19, TypeScript, Vite, Mantine, TanStack Router/Query, zod.
- `npm run dev` — Vite на :5173 с прокси `/api` на :8080.
- `npm run build` — codegen роутов, typecheck, production-сборка.
- `npm run lint`, `npm run test`, `npm run test:e2e`, `npm run lint:deadcode`, `npm run size`.
- API same-origin (`/api`), offline-режим сознательно не поддерживается: стриминг требует сервера.

### Mobile (`mobile/`)
- Expo, expo-router, React Native; `android/` и `ios/` генерируются и не коммитятся.
- OTP-вход, SecureStore, списки видео/аудио, i18n ru/en.
- `npm run typecheck -w mobile`, `npm run lint -w mobile`, `npx expo export --platform android`.
- `npm run version:sync -w mobile` синхронизирует `app.json` с `package.json` и поднимает `versionCode`.

### Shared (`packages/shared/`)
- Чистый TypeScript без DOM/React Native: транспорт, auth-контракт, media/format, query, storage.
- `npm run typecheck -w @flux/shared`, `npm run test -w @flux/shared`, `npm run lint -w @flux/shared`.

### Legacy (`frontend/`)
Flutter-клиент не развивается; новые функции делаются в web/mobile.

## Планы разработки

Планы хранятся в `.zcode/plans/`. Текущий план: загрузка файлов + fsnotify watcher (реализован).

## Важные заметки

- БД: SQLite с WAL-режимом, файл `./data/flux.db`
- Хэширование: полный SHA-256 + quick hash (1MB head + 1MB tail + file size) для быстрого обнаружения изменений
- Миниатюры генерируются через ffmpeg, хранятся в `./data/thumbnails/`
- При `debug: true` OTP-коды возвращаются в ответе (без отправки email)
- JWT secret должен быть не короче 32 символов
- Docker-образ включает ffmpeg и ca-certificates
- Volume для данных: `/app/data`, для медиа: каталог библиотеки (rw; индексация и превью)
- Refresh tokens: фоновая очистка истёкших токенов каждые 24 часа
- Soft delete для Media (gorm.DeletedAt)
- Upload-запросы обрабатываются асинхронно через очередь (202 Accepted)

## Обязательные правила

- **НИКОГДА не выполнять `git commit`, `git push`, `git reset`, `git rebase`, `git merge` без явного разрешения пользователя. Безопасные операции (`git status`, `git diff`, `git log`, `git show` и т.п.) — можно.**