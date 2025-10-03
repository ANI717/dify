# ==========================
# Stage 1: fetch Dify at a fixed ref
# ==========================
FROM alpine/git AS source
ARG DIFY_REF=1.9.0          # pin to a tag or commit SHA you trust
WORKDIR /src
RUN git clone https://github.com/langgenius/dify.git . \
 && git checkout --detach "$DIFY_REF"

# ==========================
# Stage 2: build Web (Next.js) with pnpm
# ==========================
FROM node:18-bookworm AS webbuild
WORKDIR /app/web

# lockfiles first for caching
COPY --from=source /src/web/package.json /src/web/pnpm-lock.yaml* /src/web/yarn.lock* /src/web/package-lock.json* ./

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_OPTIONS=--max_old_space_size=4096 \
    PUPPETEER_SKIP_DOWNLOAD=1
RUN corepack enable

# install deps (prefer pnpm)
RUN if [ -f pnpm-lock.yaml ]; then \
      corepack prepare pnpm@latest --activate && pnpm install --frozen-lockfile; \
    elif [ -f yarn.lock ]; then \
      corepack prepare yarn@stable --activate && yarn install --frozen-lockfile; \
    elif [ -f package-lock.json ]; then \
      npm ci --no-audit --no-fund; \
    else \
      npm install --legacy-peer-deps --no-audit --no-fund; \
    fi

# copy sources & build
COPY --from=source /src/web/ ./
# Keep this generic so NGINX can proxy /api → API
ENV NEXT_PUBLIC_API_URL=/api
RUN if [ -f pnpm-lock.yaml ]; then pnpm run build; \
    elif [ -f yarn.lock ]; then yarn build; \
    else npm run build; fi

# ==========================
# Stage 3: final runtime (Node + Python 3.11 + uv + Supervisor)
# ==========================
FROM node:18-bookworm

# Python 3.11 and runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip \
      build-essential pkg-config libpq-dev libpq5 \
      supervisor curl ca-certificates bash git \
 && ln -sf /usr/bin/python3 /usr/bin/python \
 && rm -rf /var/lib/apt/lists/*

# Install uv (Astral) for Python deps
RUN curl -LsSf https://astral.sh/uv/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /app

# --- API: copy source and install deps into an in-project venv
COPY --from=source /src/api/ /app/api/
WORKDIR /app/api

# Create venv explicitly so .venv exists, then sync deps into that venv
RUN python -m venv .venv
ENV VIRTUAL_ENV=/app/api/.venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# If uv.lock exists, use --frozen; otherwise resolve
RUN if [ -f uv.lock ]; then \
      uv sync --no-dev --frozen --python "${VIRTUAL_ENV}/bin/python"; \
    else \
      uv sync --no-dev --python "${VIRTUAL_ENV}/bin/python"; \
    fi

# Ensure runtime servers/tools are installed in the same venv
RUN pip install --no-cache-dir gunicorn uvicorn gevent celery

# --- Web: copy built artifacts
WORKDIR /app
COPY --from=webbuild /app/web/.next        /app/web/.next
COPY --from=webbuild /app/web/package.json /app/web/package.json
COPY --from=webbuild /app/web/node_modules /app/web/node_modules
COPY --from=webbuild /app/web/public       /app/web/public

# --- Storage & perms
RUN mkdir -p /temp/api-storage && chown -R node:node /temp /var/log /app

# --- Your supervisor config & entrypoint (already in your repo)
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh    /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Minimal defaults (override via .env at run)
ENV PORT_WEB=8080 \
    PORT_API=5001 \
    STORAGE_LOCAL_PATH=/temp/api-storage

# Expose only web; API stays internal on 5001
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
