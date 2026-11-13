#!/usr/bin/env bash
# Полный локальный CodeQL-прогон: Go + web/mobile/shared.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${ROOT}/scripts/codeql-go.sh" "$@"
"${ROOT}/scripts/codeql-js.sh" "$@"
