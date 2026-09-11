# orca-serve — an always-on Orca agent server (github.com/stablyai/orca),
# paired to from the Orca DESKTOP or MOBILE app, not a browser. Orca's own
# browser client can't run terminals/agents against a headless server yet
# (upstream issue stablyai/orca#9047) — this is for "keep agents running
# while my laptop sleeps," not a dashboard-clickable IDE (see workspace/
# for that: code-server). Build context is the dojo repo root.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LIBGL_ALWAYS_SOFTWARE=1 \
    NPM_CONFIG_PREFIX=/usr/local

# Orca is Electron — libgtk.../libx... is exactly what its own .deb declares
# as Depends (confirmed via `dpkg-deb -I` on orca-ide_*.deb). xvfb/xauth/
# x11-utils back Orca's own internal virtual-display launch (see
# entrypoint.sh — Orca starts its own Xvfb when DISPLAY is unset, and this
# is what it needs present to do that; confirmed live, not assumed from docs).
# Node from nodesource, not trixie's bundled apt package — trixie's older
# npm hit real integrity-checksum failures pulling the agent CLIs below.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git gh xvfb xauth x11-utils \
        libgtk-3-0t64 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libgbm1 \
        libasound2t64 libxtst6 libcups2t64 libdrm2 libxkbcommon0 \
        libpango-1.0-0 libcairo2 libatspi2.0-0t64 libxcomposite1 libxdamage1 \
        libxfixes3 libxrandr2 libxrender1 libx11-xcb1 libxcb-dri3-0 libxss1 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Same agent CLIs as workspace/Dockerfile — orca needs them on PATH to run
# and to authenticate (`orca account add --agent claude`, etc.).
RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @github/copilot \
        @qwen-code/qwen-code \
        opencode-ai

# No FUSE device in a container, so extract once at build time instead of
# running the AppImage directly (the documented container approach).
RUN curl -fsSL -o /tmp/orca.AppImage \
        https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage \
    && chmod +x /tmp/orca.AppImage \
    && cd /opt && /tmp/orca.AppImage --appimage-extract >/dev/null \
    && rm /tmp/orca.AppImage

RUN useradd --create-home --uid 10001 orca
COPY workspace/orca/entrypoint.sh /usr/local/bin/orca-serve-entrypoint
RUN chmod +x /usr/local/bin/orca-serve-entrypoint

USER orca
WORKDIR /home/orca
EXPOSE 6768
ENTRYPOINT ["/usr/local/bin/orca-serve-entrypoint"]
