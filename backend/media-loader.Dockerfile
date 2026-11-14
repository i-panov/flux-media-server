# syntax=docker/dockerfile:1.7
# Сборка media-loader из исходников, без готового образа из registry.
# Контекст — backend/; исходники клонируются внутри Dockerfile.

ARG MEDIA_LOADER_REPOSITORY=https://github.com/i-panov/media-loader.git
ARG MEDIA_LOADER_REF=main

FROM python:3.13-slim-trixie AS source

ARG MEDIA_LOADER_REPOSITORY
ARG MEDIA_LOADER_REF

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# fetch поддерживает и ветку, и тег, и точный commit SHA.
RUN git init /src \
    && cd /src \
    && git remote add origin "${MEDIA_LOADER_REPOSITORY}" \
    && git fetch --depth 1 origin "${MEDIA_LOADER_REF}" \
    && git checkout --detach FETCH_HEAD

FROM python:3.13-slim-trixie AS builder

COPY --from=ghcr.io/astral-sh/uv:0.11.2 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1

WORKDIR /app

COPY --from=source /src/pyproject.toml /src/uv.lock /src/README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-dev

COPY --from=source /src/src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev


FROM python:3.13-slim-trixie AS runtime

ARG DEBIAN_MIRROR=deb.debian.org

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g" /etc/apt/sources.list.d/debian.sources; \
    elif [ -f /etc/apt/sources.list ]; then \
        sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g" /etc/apt/sources.list; \
    fi \
    && apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg ca-certificates

RUN groupadd --gid 1000 app \
    && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder --chown=app:app /app /app

RUN mkdir -p /data/cache /data/jobs /data/tmp /config \
    && chown -R app:app /data /config

USER app
EXPOSE 8000

CMD ["uvicorn", "media_loader.api:app", "--host", "0.0.0.0", "--port", "8000"]
