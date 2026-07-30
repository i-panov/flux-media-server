# Build stage
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=1 go build -ldflags="-s -w" -o /build/flux-server ./cmd/server

# Runtime stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata ffmpeg

WORKDIR /app

COPY --from=builder /build/flux-server .
COPY --from=builder /build/configs/config.example.yaml ./configs/config.yaml

# Run as an unprivileged user: a remote file-write vulnerability must not
# give root inside the container.
RUN adduser -D -u 1000 flux \
	&& mkdir -p /app/data \
	&& chown -R flux:flux /app/data

USER flux

EXPOSE 8080

VOLUME ["/app/data", "/app/media"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/health || exit 1

ENTRYPOINT ["./flux-server"]
CMD ["-config", "configs/config.yaml"]
