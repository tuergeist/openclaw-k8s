# Custom OpenClaw image with DevOps tooling
# Build: docker build -t registry.gitlab.com/gauvendi/infrastructure/openclaw:latest .
FROM node:22-bookworm AS builder

# Clone and build OpenClaw
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

WORKDIR /app
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git . && \
    NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile && \
    pnpm build && \
    OPENCLAW_PREFER_PNPM=1 pnpm ui:build

# --- Final stage ---
FROM node:22-bookworm

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

# Install DevOps tools
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg unzip git jq dnsutils iputils-ping \
    # Docker CLI (for DinD sidecar communication)
    docker.io \
    # Python for awscli
    python3 python3-pip pipx \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# AWS CLI v2
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then AWSARCH="aarch64"; else AWSARCH="x86_64"; fi && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWSARCH}.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip

# GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# GitLab CLI (glab)
RUN ARCH=$(dpkg --print-architecture) && \
    GLAB_VERSION=$(curl -fsSL https://gitlab.com/api/v4/projects/34675721/releases | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['tag_name'].lstrip('v'))") && \
    curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${ARCH}.deb" -o /tmp/glab.deb && \
    dpkg -i /tmp/glab.deb && rm /tmp/glab.deb

# Chromium for browser automation (optional, adds ~300MB)
# RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xvfb && \
#     mkdir -p /home/node/.cache/ms-playwright && \
#     PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright \
#     node /app/node_modules/playwright-core/cli.js install --with-deps chromium && \
#     chown -R node:node /home/node/.cache/ms-playwright

WORKDIR /app
COPY --from=builder /app /app
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && chmod 755 /app/openclaw.mjs

ENV NODE_ENV=production

# Run as node user
USER node
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
