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

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /build/flux-server .
COPY --from=builder /build/configs/config.example.yaml ./configs/config.yaml

RUN mkdir -p /app/data

EXPOSE 8080

VOLUME ["/app/data", "/app/media"]

ENTRYPOINT ["./flux-server"]
CMD ["-config", "configs/config.yaml"]
