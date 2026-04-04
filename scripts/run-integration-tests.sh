#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/tests/integration/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[parlotte]${NC} $*"; }
warn() { echo -e "${YELLOW}[parlotte]${NC} $*"; }
err() { echo -e "${RED}[parlotte]${NC} $*" >&2; }

cleanup() {
    if [ "${KEEP_RUNNING:-}" != "1" ]; then
        log "Stopping Synapse..."
        docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
    else
        warn "KEEP_RUNNING=1 — leaving Synapse running."
    fi
}

trap cleanup EXIT

# Start Synapse
log "Starting Synapse..."
docker compose -f "$COMPOSE_FILE" up -d

# Wait for Synapse to be healthy
log "Waiting for Synapse to be ready..."
MAX_RETRIES=30
RETRY=0
until curl -fsSL http://localhost:8008/health > /dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    if [ "$RETRY" -ge "$MAX_RETRIES" ]; then
        err "Synapse did not become healthy after ${MAX_RETRIES} attempts"
        docker compose -f "$COMPOSE_FILE" logs synapse
        exit 1
    fi
    sleep 2
done
log "Synapse is ready."

# Run integration tests
log "Running integration tests..."
cd "$PROJECT_ROOT"
cargo test -p parlotte-integration -- "$@"

log "All integration tests passed!"
