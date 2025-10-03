#!/usr/bin/env bash
set -euo pipefail

# Basic sanity for required envs
#: "${DATABASE_URL:?Set DATABASE_URL to your Postgres URI}"
#: "${REDIS_URL:?Set REDIS_URL to your Redis URI (redis://...)}"
#: "${VECTOR_STORE:?Set VECTOR_STORE (e.g., pgvector)}"
#: "${SECRET_KEY:?Set SECRET_KEY}"

# Helpful default: run auto-migrations like official docker mode
export MIGRATION_ENABLED=${MIGRATION_ENABLED:-true}

# Storage (local) path default per docs
export STORAGE_TYPE=${STORAGE_TYPE:-local}
export STORAGE_LOCAL_PATH=${STORAGE_LOCAL_PATH:-/temp/api-storage}

# Start all processes
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
