#!/usr/bin/env bash
# Полный e2e: настоящий Flux backend + транскод, реальный media-loader
# в Docker, локальный HTTP-сервер с MP4 и браузер.
# Требования: go, node, python3, docker compose, ffmpeg/ffprobe в PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEB="$ROOT/web"
OUT="$ROOT/.artifacts/e2e-real"
DOCKER_BIN="${DOCKER_BIN:-docker}"
PORT="${FLUX_E2E_PORT:-$((19000 + RANDOM % 500))}"
VITE_PORT="${FLUX_E2E_VITE_PORT:-$((PORT + 1))}"
export FLUX_E2E_BASE_URL="http://127.0.0.1:$VITE_PORT"
COMPOSE="$WEB/e2e/real/compose.yaml"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do
		kill "$pid" 2>/dev/null || true
	done
	"$DOCKER_BIN" compose -f "$COMPOSE" down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "ffmpeg not found; set PATH to ffmpeg/ffprobe" >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 not found; нужен для seed каталога" >&2
	exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"/{video,audio,images,originals,tmp,thumbnails}
cat > "$OUT/config.yaml" <<CFG
server:
  host: "127.0.0.1"
  port: $PORT
  env: "dev"
  debug: true
  cookie_secure: false
  max_upload_size: 104857600
database:
  path: "$OUT/flux.db"
rate_limiter:
  max: 100
auth:
  jwt_secret: "e2e-only-secret-0123456789-0123456789"
  allow_unknown_email: true
scanner:
  enabled: false
  watch_enabled: false
media:
  thumbnail_path: "$OUT/thumbnails"
  video_path: "$OUT/video"
  audio_path: "$OUT/audio"
  image_path: "$OUT/images"
storage:
  originals_dir: "$OUT/originals"
  temp_dir: "$OUT/tmp"
transcode:
  crf: 20
  preset: "ultrafast"
  max_height: 1080
media_loader:
  url: "http://127.0.0.1:18081"
  timeout: 30
CFG

echo ">> building backend"
(cd "$ROOT/backend" && CGO_ENABLED=1 go build -o "$OUT/flux-server" ./cmd/server)

if ! "$DOCKER_BIN" image inspect flux-media-loader:local >/dev/null 2>&1; then
	echo ">> building media-loader image"
	(cd "$ROOT" && "$DOCKER_BIN" build -f backend/media-loader.Dockerfile -t flux-media-loader:local backend)
fi

echo ">> starting media-loader stack"
"$DOCKER_BIN" compose -f "$COMPOSE" up -d

echo ">> starting fixture server"
node "$WEB/e2e/real/fixture-server.mjs" > "$OUT/fixture.log" 2>&1 &
PIDS+=($!)

echo ">> starting backend"
"$OUT/flux-server" -config "$OUT/config.yaml" > "$OUT/backend.log" 2>&1 &
PIDS+=($!)

echo ">> starting web"
(cd "$WEB" && VITE_API_PROXY="http://127.0.0.1:$PORT" npm run dev -- --host 127.0.0.1 --port $VITE_PORT > "$OUT/web.log" 2>&1) &
PIDS+=($!)

for url in "http://127.0.0.1:$PORT/api/health" "http://127.0.0.1:$VITE_PORT" "http://127.0.0.1:18082/video.mp4" "http://127.0.0.1:18081/ui"; do
	for _ in $(seq 1 60); do
		if curl -fsS "$url" >/dev/null 2>&1; then break; fi
		sleep 1
	done
	curl -fsS "$url" >/dev/null || { echo "not ready: $url" >&2; exit 1; }
done

echo ">> seeding catalog"
python3 "$WEB/e2e/real/seed-catalog.py" "$OUT/flux.db"

echo ">> running Playwright"
(cd "$WEB" && npx playwright test -c playwright.real.config.ts)
