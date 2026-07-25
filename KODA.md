# KODA.md — Flux Media Server

## Обзор проекта

**Flux Media Server** — self-hosted медиа-сервер для стриминга видео и аудио. Состоит из Go-бэкенда (Fiber) и Flutter-клиента (Android, iOS, Linux, Windows, macOS, Web).

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
│   │   ├── handlers/         — HTTP-обработчики (auth, media, library, upload, progress, metadata, thumb)
│   │   ├── metadata/         — парсинг имён файлов, извлечение метаданных
│   │   ├── middleware/       — JWT auth middleware
│   │   ├── models/           — GORM-модели: Media, Metadata, User, WatchProgress, MediaLibrary
│   │   ├── repository/       — интерфейсы и реализации репозиториев (SQLite через GORM)
│   │   ├── response/         — хелперы для JSON-ответов и ошибок
│   │   └── services/         — бизнес-логика: scanner, watcher, streamer, thumbnail, auth (JWT, OTP)
│   ├── Dockerfile            — multi-stage build (golang:1.22-alpine → alpine:3.19 + ffmpeg)
│   └── docker-compose.yml    — проброс порта 8080, volume для data и media
│
├── frontend/                 — Flutter-клиент
│   ├── lib/
│   │   ├── main.dart         — инициализация MediaKit, auto-login, роутинг
│   │   ├── core/
│   │   │   ├── network/      — Chopper API-клиент, интерсепторы (auth, logging)
│   │   │   ├── providers/    — глобальные Riverpod-провайдеры
│   │   │   ├── router/       — auto_route роутер, AuthGuard
│   │   │   ├── error/        — обработка ошибок
│   │   │   ├── usecases/     — use cases
│   │   │   └── utils/        — утилиты
│   │   ├── features/         — feature-based архитектура
│   │   │   ├── auth/         — аутентификация (data/domain/presentation)
│   │   │   ├── library/      — библиотеки (data/domain/presentation)
│   │   │   ├── media/        — медиа (data/domain/presentation)
│   │   │   ├── player/       — плеер на media_kit (data/domain/presentation)
│   │   │   └── settings/     — настройки (data/domain/presentation)
│   │   └── shared/models/    — общие модели
│   ├── pubspec.yaml
│   └── analysis_options.yaml — very_good_analysis
│
└── .zcode/plans/             — планы разработки
```

## Бэкенд

### Технологии
- **Язык:** Go 1.23
- **Веб-фреймворк:** Fiber v2
- **ORM:** GORM + SQLite (WAL mode, busy_timeout=5000)
- **Аутентификация:** JWT + OTP через email (SMTP)
- **Медиа:** ffprobe (через go-ffprobe), ffmpeg (для миниатюр), dhowden/tag (аудио-теги)
- **Файловый мониторинг:** fsnotify
- **Контейнер:** Docker (Alpine + ffmpeg)

### Модули Go
- `module flux`
- Ключевые зависимости: gofiber/fiber/v2, gorm.io/gorm, gorm.io/driver/sqlite, golang-jwt/jwt/v5, fsnotify/fsnotify, vansante/go-ffprobe.v2, dhowden/tag

### Стиль кода (Go)
- Пакеты: `internal/` с чётким разделением (handlers, services, repository, models, config, middleware)
- Интерфейсы репозиториев в `repository/interfaces.go`, сервисов — в `services/interfaces.go`
- Конструкторы: `NewXxx(deps) *Xxx`
- Обработчики принимают `*fiber.Ctx`, используют `response.Error()` и `response.OK()` хелперы
- Контекст: `c.UserContext()` передаётся в репозитории
- Конфигурация: YAML, загружается через `config.Load(path)`, дефолты в `config.Load()`
- Модели GORM с JSON-тегами, `gorm:"uniqueIndex"` / `gorm:"index"` аннотациями

### API эндпоинты

| Метод | Путь | Описание | Auth |
|-------|------|----------|------|
| GET | `/health` | Health check | — |
| POST | `/api/auth/request-code` | Запрос OTP-кода | — |
| POST | `/api/auth/verify-code` | Проверка OTP, выдача JWT | — |
| GET | `/api/auth/me` | Текущий пользователь | JWT |
| GET | `/api/media` | Список медиа (фильтры: type, year, q, limit, offset) | JWT |
| GET | `/api/media/:id` | Получить медиа по ID | JWT |
| POST | `/api/media` | Создать запись медиа | JWT |
| POST | `/api/media/upload` | Загрузка файла (multipart, library_id + file, лимит 2GB) | JWT |
| POST | `/api/media/check-hash` | Проверка хэша файла | JWT |
| PUT | `/api/media/:id` | Обновить медиа | JWT |
| DELETE | `/api/media/:id` | Удалить медиа | JWT |
| GET | `/api/media/:id/stream` | Стриминг файла (Range support) | JWT |
| GET | `/api/media/:id/thumb` | Миниатюра | JWT |
| GET | `/api/libraries` | Список библиотек | JWT |
| POST | `/api/libraries` | Создать библиотеку | JWT |
| PUT | `/api/libraries/:id` | Обновить библиотеку | JWT |
| DELETE | `/api/libraries/:id` | Удалить библиотеку | JWT |
| POST | `/api/libraries/:id/scan` | Запуск сканирования | JWT |
| GET | `/api/libraries/:id/scan-status` | Статус сканирования | JWT |
| GET | `/api/progress` | Прогресс просмотра пользователя | JWT |
| PUT | `/api/progress/:mediaId` | Обновить прогресс | JWT |
| DELETE | `/api/progress/:mediaId` | Удалить прогресс | JWT |
| GET | `/api/metadata/search` | Поиск метаданных | JWT |
| POST | `/api/metadata/:mediaId/refresh` | Обновить метаданные | JWT |
| PUT | `/api/metadata/:mediaId` | Изменить метаданные | JWT |

### Модели данных

- **User** — id, email, timestamps
- **Media** — id, title, year, description, type (video/audio), artist, album, genre, duration, filePath, fileSize, fileHash (SHA-256), quickHash, thumbnailURL, metadataID, timestamps
- **Metadata** — id, externalID, source (tmdb/tvdb), title, year, description, posterURL, backdropURL, rating, genres, cast, timestamps
- **MediaLibrary** — id, name, path, type (video/audio), enabled, scanInterval, timestamps
- **WatchProgress** — id, userID, mediaID, position, duration, completed, updatedAt

### Сервисы

- **ScannerService** — сканирование библиотек: walk по директории, хэширование (SHA-256 полный + quick hash 1MB head/tail), извлечение метаданных через ffprobe и теги, генерация миниатюр
- **WatcherService** — fsnotify мониторинг папок, debounce 2с, автосканирование при появлении новых файлов
- **StreamerService** — стриминг файлов с поддержкой HTTP Range
- **ThumbnailService** — генерация миниатюр через ffmpeg
- **JWTService** — выпуск и валидация JWT-токенов
- **OTPStore** — генерация и хранение OTP-кодов с TTL

### Конфигурация (config.yaml)

```yaml
server:       host, port (8080), debug, cors_origins
database:     path (./data/flux.db)
auth:         jwt_secret (≥32 chars), jwt_expiry (hours), code_length, code_expiry, max_otp_entries, allowed_emails, allow_unknown_email, smtp (host, port, username, password, from)
scanner:      enabled, interval (min), watch_enabled
media:        thumbnail_path, video_path, audio_path
```

### Запуск бэкенда

```bash
# Локально
cd backend
go run ./cmd/server -config configs/config.yaml

# Docker
docker-compose up -d
```

## Фронтенд

### Технологии
- **Фреймворк:** Flutter (SDK ≥3.2.0 <4.0.0)
- **Стейт-менеджмент:** Riverpod (flutter_riverpod + riverpod_annotation + riverpod_generator)
- **Сеть:** Chopper (генерация клиентов) + http
- **Роутинг:** auto_route (auto_route_generator)
- **Модели:** freezed + json_serializable
- **Плеер:** media_kit (media_kit, media_kit_video, media_kit_libs_video)
- **Линт:** very_good_analysis
- **Прочее:** file_picker, flutter_secure_storage, connectivity_plus, cached_network_image, fpdart, crypto

### Архитектура
- Feature-based с трёхслойной структурой: `data/` → `domain/` → `presentation/`
- Сгенерированные файлы: `*.g.dart`, `*.chopper.dart`, `*.gr.dart`, `*.freezed.dart` (исключены из анализа)

### Стиль кода (Dart)
- Material 3, colorSchemeSeed: deepPurple, поддержка light/dark темы
- Riverpod для DI и стейт-менеджмента
- Chopper-генерация API-клиента из аннотаций
- auto_route с AuthGuard для защищённых маршрутов
- Отключённые линты: public_member_api_docs, lines_longer_than_80_chars, require_trailing_commas, avoid_print, comment_references

### Запуск фронтенда

```bash
cd frontend
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

## Планы разработки

Планы хранятся в `.zcode/plans/`. Текущий план: загрузка файлов + fsnotify watcher (реализован).

## Важные заметки

- БД: SQLite с WAL-режимом, файл `./data/flux.db`
- Хэширование: полный SHA-256 + quick hash (1MB head + 1MB tail + file size) для быстрого обнаружения изменений
- Миниатюры генерируются через ffmpeg, хранятся в `./data/thumbnails/`
- При `debug: true` OTP-коды возвращаются в ответе (без отправки email)
- JWT secret должен быть не короче 32 символов
- Docker-образ включает ffmpeg и ca-certificates
- Volume для данных: `/app/data`, для медиа: `/media` (read-only)
