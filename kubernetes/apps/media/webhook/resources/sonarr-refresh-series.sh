#!/usr/bin/env bash
set -Eeuo pipefail

# SONARR_API_KEY comes from the container environment (webhook-secrets), not
# from the hook, so webhook never logs it. Sonarr is reached through its Service
# rather than the caller's address, which may be IPv6.
SONARR_URL="${SONARR_URL:-http://sonarr.media.svc}"

function refresh() {
    if [[ "${SONARR_EVENT_TYPE}" == "Test" ]]; then
        echo "[DEBUG] test event received, nothing to do ..."
    elif [[ "${SONARR_EVENT_TYPE}" == "Grab" ]]; then
        episodes=$(
            curl -fsSL --header "X-Api-Key: ${SONARR_API_KEY}" "${SONARR_URL}/api/v3/episode?seriesId=${SONARR_SERIES_ID}" |
                jq --raw-output '[.[] | select((.title == "TBA") or (.title == "TBD"))] | length'
        )
        if ((episodes > 0)); then
            echo "[INFO] episode titles found with TBA/TBD titles, refreshing series ${SONARR_SERIES_TITLE} ..."
            curl -fsSL --request POST \
                --header "X-Api-Key: ${SONARR_API_KEY}" \
                --header "Content-Type: application/json" \
                --data-binary "$(jo name=RefreshSeries seriesId="${SONARR_SERIES_ID}")" \
                "${SONARR_URL}/api/v3/command" &>/dev/null
        fi
    fi
}

function main() {
    refresh
}

main "$@"
