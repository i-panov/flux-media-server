# AGENTS.md — Flux Media Server

**ОБЯЗАТЕЛЬНОЕ ПРАВИЛО: ВСЕГДА ПИСАТЬ ТОЛЬКО ПО-РУССКИ. НИКОГДА НЕ ИСПОЛЬЗОВАТЬ КИТАЙСКИЙ ЯЗЫК. ЭТО ПРАВИЛО КАСАЕТСЯ ВСЕХ ОТВЕТОВ ПОЛЬЗОВАТЕЛЮ, КОММЕНТАРИЕВ И ЛЮБОГО ТЕКСТА.**

Self-hosted media streaming server: Go backend (Fiber + GORM + SQLite) + Flutter frontend (Riverpod + Chopper + media_kit).

## Commands

### Backend (`backend/`)

```bash
cd backend
go run ./cmd/server -config configs/config.yaml  # run server
go test ./internal/... -v                         # run tests (uses in-memory SQLite)
CGO_ENABLED=1 go build -o flux-server ./cmd/server  # build binary
```

- Module name: `flux` (not `flux-media-server`)
- CGO required for SQLite driver
- Tests use `:memory:` DB — no external services needed
- SQLite WAL mode with `busy_timeout=5000`

### Frontend (`frontend/`)

```bash
cd frontend
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs  # codegen (required before build/run)
flutter analyze    # lint (very_good_analysis)
flutter test       # run tests
flutter run        # run app
```

- Code generation is mandatory: run `build_runner` after any change to freezed/riverpod/chopper/auto_route annotations
- Generated files (`*.g.dart`, `*.chopper.dart`, `*.gr.dart`, `*.freezed.dart`) are excluded from analysis
- SDK constraint: `>=3.2.0 <4.0.0`

## Architecture

### Backend structure (`backend/internal/`)

- `app/app.go` — DI wiring, route registration, lifecycle (the "composition root")
- `config/` — YAML config loading with defaults
- `handlers/` — HTTP handlers (Fiber), use `response.Error()` / `response.OK()` helpers
- `services/` — business logic; interfaces in `services/interfaces.go`
- `repository/` — data access; interfaces in `repository/interfaces.go`
- `models/` — GORM models with JSON tags
- `middleware/` — JWT auth middleware
- `email/` — SMTP client for OTP codes
- `metadata/` — filename parsing, ffprobe metadata extraction
- `response/` — JSON response helpers

### Frontend structure (`frontend/lib/`)

- Feature-based with three layers: `data/` → `domain/` → `presentation/`
- `core/` — network (Chopper client), providers, router (auto_route + AuthGuard), error handling, use cases, utils
- `shared/models/` — shared data models
- `features/` — auth, library, media, player, settings

## Key patterns

- Backend handlers accept `*fiber.Ctx`, use `c.UserContext()` for repository calls
- Backend constructors: `NewXxx(deps) *Xxx`
- Frontend uses `fpdart` `Either<Failure, T>` for error handling in repositories
- Frontend tests mock platform channels (flutter_secure_storage) and override Riverpod providers
- Frontend auth states: `AuthInitial` → `AuthCodeSent` → `AuthAuthenticated` / `AuthError`

## Config

Backend reads `configs/config.yaml` (fallback: `$CONFIG_PATH` env var). See `configs/config.example.yaml` for schema.

Key settings:
- `auth.jwt_secret` must be ≥32 chars
- `auth.allow_unknown_email: true` + `debug: true` skips email OTP (code returned in response)
- `scanner.watch_enabled` enables fsnotify-based auto-scanning

## Docker

```bash
cd backend && docker-compose up -d
```

- Exposes port 8080
- Volumes: `/app/data` (DB), `/media` (media files, read-only)
- Runtime image includes `ffmpeg`
