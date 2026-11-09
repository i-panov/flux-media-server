# Flux Media Server

Self-hosted media streaming server: Go (Fiber) backend, React web client and
Expo mobile client. Legacy Flutter `frontend/` is kept as a feature reference
only and is not developed.

## Quick Start

### Backend

```bash
cd backend
cp configs/config.example.yaml configs/config.yaml
# edit configs/config.yaml to match your environment
go run ./cmd/server -config configs/config.yaml
```

### Web

```bash
npm ci
npm run dev -w web
```

Vite runs on `http://127.0.0.1:5173` and proxies `/api` to `:8080`.
Production build: `npm run build -w web`.

### Mobile

```bash
npm ci
cd mobile && npx expo start
```

OTP login requires a reachable server URL; set it in Settings on first launch.
Production bundle: `cd mobile && npx expo export --platform android`.

## Docker

```bash
cd backend
docker compose up -d
```

The server listens on port `8080` inside the container. Docker Compose publishes
it on `${HOST_PORT:-8095}` (8095 by default), so the API is available at
`http://127.0.0.1:8095`. Media files are expected under `/media` (volume mount).

### Memory requirements for uploads

The HTTP engine buffers the entire upload body in RAM before processing. One
upload consumes up to `server.max_upload_size` (2 GB in the example config) of
memory; plan RAM accordingly for concurrent uploads. Uploads require an
admin JWT and are throttled by the rate limiter, but the per-request memory
cost is unavoidable with the current engine. If you expect large files on a
memory-constrained host, lower `server.max_upload_size`.

## Documentation

- [AGENTS.md](AGENTS.md) — architecture, commands, conventions.
- [KODA.md](KODA.md) — project overview and client structure.
- [docs/review-2026-11-09.md](docs/review-2026-11-09.md) — code review and execution journal.
