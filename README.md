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

## Internal Documentation

See [AGENTS.md](AGENTS.md) for architecture, project structure, and detailed development notes.
