#!/usr/bin/env bash
# CodeQL для TypeScript/React web, mobile и shared.
# Usage: scripts/codeql-js.sh [analyze]
set -euo pipefail
CODEQL="${CODEQL:-${HOME}/Apps/codeql/codeql}"
PACKS="${CODEQL_PACKS:-${HOME}/.cache/codeql-packs}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${PACKS}" "${ROOT}/.codeql/sarif"
"${CODEQL}" pack download codeql/javascript-queries:javascript-code-scanning --dir="${PACKS}" >/dev/null
SUITE=($(find "${PACKS}" -path '*/javascript-queries/*/codeql-suites/javascript-code-scanning.qls' -print -quit))
if ((${#SUITE[@]} == 0)); then
	echo "!! [codeql] javascript query suite not found under ${PACKS}" >&2
	exit 1
fi
for part in web/src mobile/src mobile/app packages/shared/src; do
	name="${part//\//-}"
	DB="${ROOT}/.codeql/javascript-${name}"
	SARIF="${ROOT}/.codeql/sarif/javascript-${name}.sarif"
	if [[ "${1:-}" != "analyze" ]]; then
		echo ">> [codeql] creating JS/TS database: ${part}"
		rm -rf "${DB}"
		"${CODEQL}" database create "${DB}" --language=javascript \
			--source-root="${ROOT}/${part}" --build-mode=none \
			--search-path="${PACKS}"
	fi
	echo ">> [codeql] analyzing ${part}"
	"${CODEQL}" database analyze "${DB}" --format=sarif-latest \
		--output="${SARIF}" --search-path="${PACKS}" --threads=0 \
		"${SUITE[0]}"
done
echo ">> done: ${ROOT}/.codeql/sarif"
