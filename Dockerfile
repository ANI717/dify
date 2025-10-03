# ----------------------------
# Web build (Next.js)
# ----------------------------
FROM node:18-bullseye AS webbuild
WORKDIR /app/web
# Install deps first for better caching
COPY web/package.json web/package-lock.json* web/yarn.lock* web/pnpm-lock.yaml* ./ 
RUN if [ -f pnpm-lock.yaml ]; then npm i -g pnpm && pnpm i --frozen-lockfile; \
    elif [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
    else npm ci; fi
# Copy rest of web
COPY web/ .
# Build with API url wired at runtime via NEXT_PUBLIC_*
# (Next.js will still read these at build; we keep runtime vars for SSR)
ARG NEXT_PUBLIC_API_URL=/api
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN npm run build

# ----------------------------
# API/Worker build (Python)
# ----------------------------
FROM python:3.11-slim AS apibuild
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# ---- native build deps most Python DB libs need ----
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential gcc curl git pkg-config libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/api

# Try Poetry only when lockfile exists; otherwise skip cleanly
COPY api/pyproject.toml api/poetry.lock* ./
RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install --no-cache-dir poetry || true

# Install with Poetry if both files exist; otherwise we’ll use requirements.txt later
RUN if [ -f "pyproject.toml" ] && [ -f "poetry.lock" ]; then \
      command -v poetry >/dev/null 2>&1 && \
      poetry config virtualenvs.create false && \
      poetry install --no-interaction --no-ansi || exit 0; \
    fi

# Fallback: requirements.txt (safe to run even if Poetry already installed things)
COPY api/requirements.txt* ./
RUN if [ -f "requirements.txt" ]; then \
      python -m pip install --no-cache-dir -r requirements.txt; \
    fi

# Copy the rest of the API source
COPY api/ .


# ----------------------------
# Final runtime with supervisor
# ----------------------------
FROM node:18-bullseye
# Add Python for API/Worker
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip \
    python3-venv libpq5 curl supervisor && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

# Create app dirs
WORKDIR /app
# Copy built artifacts
COPY --from=apibuild /app/api /app/api
COPY --from=webbuild /app/web/.next /app/web/.next
COPY --from=webbuild /app/web/package.json /app/web/package.json
COPY --from=webbuild /app/web/node_modules /app/web/node_modules

# Python deps are already vendored in /app/api from build stage; ensure gunicorn/celery available
RUN pip install --no-cache-dir gunicorn gevent celery

# Storage path (persist this with a volume)
RUN mkdir -p /temp/api-storage && chown -R node:node /temp /var/log

# Supervisor config & entry
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PORT_WEB=8080 \
    PORT_API=5001

EXPOSE 8080 5001
ENTRYPOINT ["/entrypoint.sh"]
