# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS base
WORKDIR /app

# Install build dependencies in base stage
RUN apt update && \
    apt install -y curl git nodejs npm python3 openssh-client less && \
    rm -rf /var/lib/apt/lists/*

# Install Bun (ARM64 compatible)
RUN curl -fsSL https://bun.sh/install | bash

# Add Bun to PATH
ENV BUN_INSTALL="/root/.bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"

# ----------------------------------------------------------------------
FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/desktop/package.json ./packages/desktop/
COPY packages/vscode/package.json ./packages/vscode/

# Install JS dependencies using Bun
RUN bun install --frozen-lockfile --ignore-scripts

# ----------------------------------------------------------------------
FROM deps AS builder
WORKDIR /app
COPY . .
RUN bun run build:web

# ----------------------------------------------------------------------
FROM base AS runtime

# Install runtime dependencies
RUN apt update && \
    apt install -y python3 openssh-client cloudflared git nodejs npm less && \
    rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

# Create openchamber user
RUN useradd -m -s /bin/bash openchamber

# Switch to openchamber user
USER openchamber

# Set npm prefix for user installs
ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN mkdir -p /home/openchamber/.npm-global \
    /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
    npm config set prefix /home/openchamber/.npm-global && \
    npm install -g opencode-ai

# ----------------------------------------------------------------------
WORKDIR /home/openchamber
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist
COPY --chmod=755 scripts/docker-entrypoint.sh /app/openchamber-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/app/openchamber-entrypoint.sh"]
