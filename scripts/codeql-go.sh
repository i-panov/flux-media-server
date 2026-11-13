#!/usr/bin/env bash
# CodeQL для Go backend. Usage: scripts/codeql-go.sh [analyze]
set -euo pipefail
CODEQL="${CODEQL:-${HOME}/Apps/codeql/codeql}"
PACKS="${CODEQL_PACKS:-${HOME}/.cache/codeql-packs}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="${ROOT}/.codeql/go"
SARIF="${ROOT}/.codeql/sarif/go.sarif"
mkdir -p "${PACKS}" "$(dirname "${SARIF}")"
"${CODEQL}" pack download codeql/go-queries:go-code-scanning --dir="${PACKS}" >/dev/null
SUITE=($(find "${PACKS}" -path '*/go-queries/*/codeql-suites/go-code-scanning.qls' -print -quit))
SUPPRESSIONS=($(find "${PACKS}" -path '*/go-queries/*/AlertSuppression.ql' -print -quit))
if ((${#SUITE[@]} == 0)); then
	echo "!! [codeql] go query suite not found under ${PACKS}" >&2
	exit 1
fi
if [[ "${1:-}" != "analyze" ]]; then
	echo ">> [codeql] creating Go database"
	rm -rf "${DB}"
	"${CODEQL}" database create "${DB}" --language=go \
		--source-root="${ROOT}/backend" --command="go build ./..." \
		--search-path="${PACKS}"
fi
echo ">> [codeql] running Go suite"
"${CODEQL}" database analyze "${DB}" --format=sarif-latest \
	--output="${SARIF}" --search-path="${PACKS}" --threads=0 \
	"${SUITE[0]}" "${SUPPRESSIONS[0]}"
echo ">> done: ${SARIF}"
