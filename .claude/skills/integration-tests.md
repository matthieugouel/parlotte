---
description: Run parlotte integration tests against a real Synapse Matrix homeserver via Docker
match:
  - integration test
  - run integration
  - test against synapse
  - run-integration-tests
---

# Running Integration Tests

The integration tests run parlotte-core against a real Synapse homeserver in Docker.

## Prerequisites

- Docker (Docker Desktop, OrbStack, or similar) must be running
- Port 8008 must be free on localhost

## Quick Run (recommended)

```bash
./scripts/run-integration-tests.sh --test-threads=1
```

This script handles the full lifecycle:
1. Starts Synapse via `docker compose` (init container generates config, then main container runs)
2. Waits for Synapse health check at `http://localhost:8008/health`
3. Runs `cargo test -p parlotte-integration`
4. Tears down Docker containers and volumes

Pass `KEEP_RUNNING=1` to leave Synapse running after tests (useful for debugging):
```bash
KEEP_RUNNING=1 ./scripts/run-integration-tests.sh --test-threads=1
```

## Manual Run

```bash
# Start Synapse
docker compose -f tests/integration/docker-compose.yml up -d

# Wait for health (usually ~15s on first run, ~5s on subsequent)
curl --retry 15 --retry-delay 2 --retry-all-errors http://localhost:8008/health

# Run tests (use --test-threads=1 for reliability)
cargo test -p parlotte-integration -- --test-threads=1

# Teardown (removes volumes too, so next run starts fresh)
docker compose -f tests/integration/docker-compose.yml down -v
```

## Docker Architecture

- `synapse-init`: One-shot init container. Uses `/start.py migrate_config` to generate `homeserver.yaml` from env vars, then exits.
- `synapse`: Main container. Loads generated config + `tests/integration/synapse/extra-config.yaml` (open registration, no rate limits). Binds to `0.0.0.0:8008`.
- Volume `synapse-data`: Persists homeserver config, signing keys, and SQLite DB between restarts. Deleted by `down -v`.

## Test Configuration

- Homeserver: `parlotte.test` at `http://localhost:8008`
- Open registration enabled (no email/captcha)
- Rate limiting disabled for tests
- Each test creates fresh users with unique usernames to avoid conflicts

## Troubleshooting

- **Connection refused**: Synapse isn't ready. Wait or check `docker logs parlotte-synapse`.
- **Connection reset**: Synapse may be binding to localhost only inside the container. Check `docker exec parlotte-synapse cat /data/homeserver.yaml | grep bind_addresses` — it should show `0.0.0.0`.
- **Stale state**: Run `docker compose -f tests/integration/docker-compose.yml down -v` to wipe all data and start fresh.
- **Port conflict**: Something else is on 8008. Check with `lsof -i :8008`.
