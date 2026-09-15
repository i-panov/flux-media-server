# Flux Media Server

Self-hosted media streaming server built with Go (Fiber) backend and Flutter frontend.

## Quick Start

### Backend

```bash
cd backend
cp configs/config.example.yaml configs/config.yaml
# edit configs/config.yaml to match your environment
go run ./cmd/server -config configs/config.yaml
```

### Frontend

```bash
cd frontend
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

## Docker

```bash
cd backend
docker-compose up -d
```

The server listens on port `8080`. Media files are expected under `/media` (volume mount).

### Memory requirements for uploads

The HTTP engine buffers the entire upload body in RAM before processing. One
upload consumes up to `server.max_upload_size` (2 GB in the example config) of
memory; plan RAM accordingly for concurrent uploads. Uploads require an
admin JWT and are throttled by the rate limiter, but the per-request memory
cost is unavoidable with the current engine. If you expect large files on a
memory-constrained host, lower `server.max_upload_size`.

## Internal Documentation

See [AGENTS.md](AGENTS.md) for architecture, project structure, and detailed development notes.
