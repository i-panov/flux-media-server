# Build stage
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /build

COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./
RUN CGO_ENABLED=1 go build -ldflags="-s -w" -o /build/flux-server ./cmd/server

# Web stage: сборка SPA тем же npm run build, что и локально
# (route codegen + typecheck + vite). Бандл печётся в образе, поэтому
# рассинхрон «бинарник одной версии, веб другой» исключён: образ
# самодостаточен, отдельный деплой dist не нужен.
FROM node:22-alpine AS web

WORKDIR /web

COPY web/package.json web/package-lock.json ./
RUN npm ci

COPY web/ ./
RUN npm run build

# Runtime stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata ffmpeg

WORKDIR /app

COPY --from=builder /build/flux-server .
COPY --from=builder /build/configs/config.example.yaml ./configs/config.example.yaml
# Содержимое dist — прямо в /app/web: сервер отдаёт его по web_dist
# (см. configs/config.example.yaml). Путь совпадает с демо-маунтом,
# который при наличии пересборки локально перекрывает запечённое.
COPY --from=web /web/dist/ ./web/

# Run as an unprivileged user: a remote file-write vulnerability must not
# give root inside the container.
RUN adduser -D -u 1000 flux \
	&& mkdir -p /app/data \
	&& chown -R flux:flux /app/data

USER flux

EXPOSE 8095

VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8095/api/health || exit 1

ENTRYPOINT ["./flux-server"]
CMD ["-config", "/app/configs/config.yaml"]
