#!/usr/bin/env bash
#
# Create alice and bob users on the local Synapse test homeserver.
#
# Useful for manual multi-instance testing with `swift run Parlotte --profile alice`
# and `swift run Parlotte --profile bob` in two windows.
#
# Usage:
#   ./scripts/create-test-users.sh            # Register alice + bob (idempotent if absent)
#   ./scripts/create-test-users.sh --reset    # Wipe Synapse volume first, then register
#
# Credentials (printed at the end):
#   alice / password123
#   bob   / password123
#   Homeserver: http://localhost:8008

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/tests/integration/docker-compose.yml"

HOMESERVER="http://localhost:8008"
PASSWORD="password123"
USERS=(alice bob)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[parlotte]${NC} $*"; }
warn() { echo -e "${YELLOW}[parlotte]${NC} $*"; }
err()  { echo -e "${RED}[parlotte]${NC} $*" >&2; }

RESET=0
for arg in "$@"; do
    case "$arg" in
        --reset) RESET=1 ;;
        -h|--help)
            sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            err "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

if [ "$RESET" = "1" ]; then
    log "Wiping Synapse volume..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans >/dev/null 2>&1 || true
fi

log "Starting Synapse (if not already running)..."
docker compose -f "$COMPOSE_FILE" up -d >/dev/null

log "Waiting for Synapse to be ready..."
MAX_RETRIES=30
RETRY=0
until curl -fsSL "$HOMESERVER/health" >/dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    if [ "$RETRY" -ge "$MAX_RETRIES" ]; then
        err "Synapse did not become healthy after ${MAX_RETRIES} attempts"
        docker compose -f "$COMPOSE_FILE" logs synapse
        exit 1
    fi
    sleep 2
done
log "Synapse is ready."

register() {
    local username="$1"
    local body
    body=$(curl -fsS -X POST "$HOMESERVER/_matrix/client/v3/register" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$username\",\"password\":\"$PASSWORD\",\"auth\":{\"type\":\"m.login.dummy\"}}" \
        2>&1) || {
        if echo "$body" | grep -q 'M_USER_IN_USE'; then
            warn "  $username already exists — skipping. Pass --reset to re-create."
            return 0
        fi
        err "  failed to register $username: $body"
        return 1
    }
    log "  registered $username"
}

log "Registering users..."
for user in "${USERS[@]}"; do
    register "$user"
done

echo
log "Done. Credentials:"
for user in "${USERS[@]}"; do
    echo "  $user / $PASSWORD  (@$user:parlotte.test)"
done
echo "  Homeserver: $HOMESERVER"
