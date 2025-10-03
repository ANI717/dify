# ==========================
# Stage 1: clone repo
# ==========================
FROM alpine/git AS source
ARG DIFY_REF=1.9.1   # can be a tag like 1.9.0 or an exact commit SHA
WORKDIR /src
RUN git clone https://github.com/langgenius/dify.git . \
 && git checkout --detach "$DIFY_REF"

# ==========================
# Stage 2: build web (Next.js)
# ==========================
FROM node:18-bullseye AS webbuild
WORKDIR /app/web

# Copy only lockfiles first for better caching
COPY --from=source /src/web/package.json /src/web/pnpm-lock.yaml* /src/web/yarn.lock* /src/web/package-lock.json* ./

# Use Corepack to get the right package manager versions
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_OPTIONS=--max_old_space_size=4096 \
    PUPPETEER_SKIP_DOWNLOAD=1
RUN corepack enable

# Install deps using the lockfile that exists (prefer pnpm)
# - pnpm (frozen) -> yarn (frozen) -> npm ci -> npm install (legacy peer deps)
RUN if [ -f pnpm-lock.yaml ]; then \
      corepack prepare pnpm@latest --activate && \
      pnpm install --frozen-lockfile; \
    elif [ -f yarn.lock ]; then \
      corepack prepare yarn@stable --activate && \
      yarn install --frozen-lockfile; \
    elif [ -f package-lock.json ]; then \
      npm ci --no-audit --no-fund; \
    else \
      npm install --legacy-peer-deps --no-audit --no-fund; \
    fi

# Now copy the actual sources and build
COPY --from=source /src/web/ ./
ENV NEXT_PUBLIC_API_URL=/api
RUN if [ -f pnpm-lock.yaml ]; then \
      pnpm run build; \
    elif [ -f yarn.lock ]; then \
      yarn build; \
    else \
      npm run build; \
    fi


# ==========================
# Stage 3: build api
# ==========================
FROM python:3.11-slim AS apibuild
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential gcc git pkg-config libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app/api
COPY --from=source /src/api/ ./
RUN pip install --upgrade pip setuptools wheel && \
    if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

# ==========================
# Stage 4: final runtime
# ==========================
FROM node:18-bullseye
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip libpq5 supervisor curl && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
# ---- copy api + web builds
COPY --from=apibuild /app/api /app/api
COPY --from=webbuild /app/web/.next /app/web/.next
COPY --from=webbuild /app/web/package.json /app/web/package.json
COPY --from=webbuild /app/web/node_modules /app/web/node_modules

# ---- prepare storage and logs
RUN mkdir -p /temp/api-storage && chown -R node:node /temp /var/log

# ---- install gunicorn/celery
RUN pip3 install --no-cache-dir gunicorn gevent celery

# ---- copy supervisor + entrypoint
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PORT_WEB=8080 \
    PORT_API=5001 \
    STORAGE_LOCAL_PATH=/temp/api-storage

EXPOSE 8080 5001
ENTRYPOINT ["/entrypoint.sh"]
