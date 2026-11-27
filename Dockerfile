ARG UV_VERSION=0.13.10

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM debian:trixie-slim AS base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/usr/share/keyrings/ /usr/share/keyrings/
COPY rootfs/etc/apt/ /etc/apt/

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    fd-find \
    gh \
    git \
    jq \
    less \
    locales \
    nodejs \
    openssh-client \
    procps \
    python-is-python3 \
    python3 \
    ripgrep \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen en_US.UTF-8

COPY --from=uv /uv /uvx /usr/local/bin/

ENV LANG=en_US.UTF-8

FROM base AS slim-root

ARG DEBIAN_FRONTEND=noninteractive
ARG AGENT_UID=1000
ARG AGENT_GID=1000
ARG CLAUDE_CODE_VERSION=2.1.332
ARG CODEX_VERSION=0.172.0
ARG PI_CODING_AGENT_VERSION=1.6.1
ARG REX_COMMIT=b070aae645f5cbfac65d65d031a8b712b2ebca36
ARG REX_SHA256=37908dc3e79386b05fcd2e26d1bcf3c28f34536fc816eb8126a9b9c65266f630

RUN apt-get update && apt-get install -y --no-install-recommends \
    apparmor \
    bash-completion \
    bind9-dnsutils \
    docker-ce \
    docker-ce-cli \
    file \
    iproute2 \
    iputils-ping \
    lsof \
    make \
    netcat-openbsd \
    patch \
    rsync \
    shellcheck \
    shfmt \
    socat \
    strace \
    sudo \
    time \
    tmux \
    vim \
    xxd \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "$AGENT_GID" agent \
    && useradd --uid "$AGENT_UID" --gid "$AGENT_GID" --groups docker --create-home --shell /bin/bash agent \
    && mkdir -p /home/agent/.local/bin /workspace \
    && chown -R agent:agent /home/agent /workspace \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent

RUN runuser -u agent -- npm config set prefix /home/agent/.local \
    && runuser -u agent -- npm install -g \
    "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    "@earendil-works/pi-coding-agent@${PI_CODING_AGENT_VERSION}" \
    "@openai/codex@${CODEX_VERSION}" \
    && runuser -u agent -- npm cache clean --force

RUN set -eu; \
    rex_tmp="$(mktemp -d)"; \
    trap 'rm -rf "$rex_tmp"' EXIT; \
    curl -fsSL "https://blob.superlogical.com/download/rex/preview/${REX_COMMIT}/rex-linux-arm64.tar.gz" \
      -o "$rex_tmp/rex.tar.gz"; \
    printf '%s  %s\n' "$REX_SHA256" "$rex_tmp/rex.tar.gz" | sha256sum -c -; \
    tar -xzf "$rex_tmp/rex.tar.gz" -C "$rex_tmp" rex; \
    install -m 0755 "$rex_tmp/rex" /usr/local/bin/rex; \
    rex version

ENV PATH="/home/agent/.local/bin:$PATH" \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    LESS=-R \
    DISABLE_AUTOUPDATER=1

FROM slim-root AS full-root

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    chromium \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^CHROMIUM_FLAGS=""/CHROMIUM_FLAGS="--no-sandbox"/' /usr/bin/chromium

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

FROM slim-root AS slim
COPY rootfs/etc/docker/ /etc/docker/
COPY rootfs/usr/local/ /usr/local/
USER agent
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
CMD ["bash"]

FROM full-root AS full
COPY rootfs/etc/docker/ /etc/docker/
COPY rootfs/usr/local/ /usr/local/
USER agent
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
CMD ["bash"]
