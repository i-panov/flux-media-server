# Flux Media Server

Self-hosted медиа-сервер для стриминга видео и аудио: Go-бэкенд, web-клиент
на React и mobile-клиент на Expo. Legacy `frontend/` на Flutter не
развивается и оставлен только как справочник функций.

## Что готово

| Клиент | Статус | Возможности |
|---|---|---|
| **Web** | основной, production-ready | OTP-вход, видео/аудио/мемы, поиск и сортировка, плееры, очередь, lyrics, избранное, артисты, коллекции (включая bulk), загрузка, метаданные, корзина, админка, ТВ-режим, PWA, ru/en |
| **Mobile** | основные функции паритета | OTP-вход и SecureStore, настройка сервера, видео (поиск и сортировка, детали, плеер, resume, скорость, fullscreen, PiP), аудио (поиск и сортировка, очередь, shuffle/repeat, фон и lock screen, lyrics, артисты), библиотека (continue watching, избранное, коллекции с bulk, корзина), загрузка и метаданные, offline-скачивание и экспорт, тема и ru/en |
| **Legacy Flutter** | не развивается | справочник поведения и фич |

Ограничения web: нет offline/downloads, скорости/PiP и пользовательского
скачивания видео. Виртуализация длинных списков частичная. Подробности —
в [docs/review-2026-11-09.md](docs/review-2026-11-09.md).

Ограничения mobile: Maestro-сценарии (19 flow, включая поиск/сортировку) и
ручной Android e2e-workflow добавлены, но ещё не прогонялись на
эмуляторе/устройстве; background audio, PiP и offline подтверждены только
кодом и unit-тестами. Детали —
в [release notes](docs/mobile-release-notes-2026-11-11.md).

## Требования

- Go **1.25** и CGO (SQLite `mattn/go-sqlite3`).
- Node **>=22**, npm workspaces.
- `ffmpeg`/`ffprobe` в `PATH` — для превью, метаданных и транскода.
- Docker — опционально.

## Быстрый старт

```bash
npm ci
```

### Backend

```bash
cd backend
cp configs/config.example.yaml configs/config.yaml
# отредактируйте config.yaml: jwt_secret, media paths, SMTP/debug
go run ./cmd/server -config configs/config.yaml
```

API по умолчанию: `http://127.0.0.1:8080`.

### Web

```bash
npm run dev -w web
```

Vite: `http://127.0.0.1:5173`, `/api` проксируется на `:8080`.
Production-сборка: `npm run build -w web` (результат в `web/dist`).

### Mobile

```bash
cd mobile
npx expo start
```

При первом запуске укажите адрес сервера на публичном экране `/server`
(ссылка «Настроить сервер» на экране входа). Вход — OTP по email;
в `debug`-режиме код возвращается в ответе. Сборка JS-бандла:

```bash
npx expo export --platform android --output-dir dist
```

Проверки mobile:

```bash
npm run typecheck -w mobile && npm run lint -w mobile && npm run test -w mobile
npm run version:sync -w mobile -- --check
cd mobile && EXPO_OFFLINE=1 npx expo install --check
cd mobile && npx expo config --type introspect
```

E2E: в `.maestro/` лежат 19 flow для эмулятора/устройства (нужны Maestro CLI
и adb). Ручной workflow `.github/workflows/mobile-e2e.yml` поднимает Android
эмулятор, backend и прогоняет `tabs.yaml`/`theme.yaml`; он запускается
только через `workflow_dispatch` и в push/PR не входит.

## Docker

```bash
cd backend
docker compose up -d
```

- Внутри контейнера — порт `8080`, на хосте — `${HOST_PORT:-8095}`.
- Данные: `/app/data`; медиа — каталог библиотеки (rw).
- Образ собирает backend и web, включает ffmpeg.
- Локальный `web/dist` можно смонтировать поверх `/app/web`.

### Серверное скачивание (media-loader)

В compose входит `ghcr.io/i-panov/media-loader:0.1.0`:

- `media-loader` — API и UI на `http://127.0.0.1:${MEDIA_LOADER_PORT:-8097}/ui`;
- `media-loader-worker` — очередь yt-dlp/ffmpeg;
- `media-loader-redis` — очередь и кэш;
- данные — named volume `media-loader-data`.

Сервис запускается без авторизации и слушает только loopback. Для доступа
из LAN включите `AUTH_ENABLED=true` и создайте токен:

```bash
docker compose exec media-loader media-loader-auth create --name flux
```

Файлы, скачанные media-loader, лежат в его томе и не импортируются в
библиотеку Flux автоматически. Это отдельный сервис; интеграция импорта
в библиотеку — следующий шаг.

### Память при загрузке

HTTP-движок буферизует тело загрузки в RAM. Одна загрузка занимает до
`server.max_upload_size` (2 ГБ в примере); при нехватке памяти уменьшите
лимит.

## Конфигурация

См. `backend/configs/config.example.yaml`. Ключевое:

- `auth.jwt_secret` — не короче 32 символов.
- `auth.allow_unknown_email: true` + `debug: true` — OTP без SMTP.
- `server.max_upload_size`, `media.*_path`, `scanner.*`.
- `server.trusted_proxies` — CIDR/IP прокси для корректного XFF/rate limit.

## Проверки

```bash
(cd backend && go test ./internal/... -count=1)
(cd web && npm run typecheck && npm run lint && npm run test && npm run lint:deadcode)
npm run test -w @flux/shared
npm run typecheck -w mobile && npm run lint -w mobile && npm run test -w mobile
```

E2E и production build:

```bash
cd web && npm run test:e2e && npm run build && npm run size
```

## Документация

- [AGENTS.md](AGENTS.md) — команды, архитектура, конвенции, версии.
- [docs/README.md](docs/README.md) — индекс документов.
- [docs/review-2026-11-09.md](docs/review-2026-11-09.md) — итоговое ревью,
  решения, ограничения и журнал коммитов.
- [docs/mobile-parity-plan-2026-11-09.md](docs/mobile-parity-plan-2026-11-09.md)
  — план доведения mobile до паритета с Flutter.
- [docs/mobile-parity-handoff-2026-11-10.md](docs/mobile-parity-handoff-2026-11-10.md)
  — исторический handoff mobile-задач и актуальный статус.
- [docs/mobile-release-notes-2026-11-11.md](docs/mobile-release-notes-2026-11-11.md)
  — что вошло в mobile 0.1.44 и известные ограничения.
- [docs/web-release-notes-2026-11-11.md](docs/web-release-notes-2026-11-11.md)
  — web 0.1.35: TV-OSD видео, TV-вход, read-only, фикс карточек и
  «Продолжить просмотр»; реальный ТВ не проверялся.
- [docs/admin-release-notes-2026-11-11.md](docs/admin-release-notes-2026-11-11.md)
  — web 0.1.36, backend 1.0.30 (исторические): авточистка, `used_bytes`
  в карточках хранилища и подсказка в таблице пользователей.
- [docs/tv-roadmap-2026-11-11.md](docs/tv-roadmap-2026-11-11.md)
  — Android TV, web-TV, read-only, QR-вход и порядок работ.

## Лицензия

Файл лицензии в репозитории отсутствует; уточните условия у владельца.
