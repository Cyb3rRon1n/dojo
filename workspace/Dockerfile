# dojo workspace — VS Code in the browser (code-server) with the coding-agent
# CLIs and dojo's optimizer stack (RTK / graphify / ponytail / token-optimizer
# / Serena) already wired in. Build context is the dojo repo root:
#
#   docker build -f workspace/Dockerfile -t dojo-workspace .
#
FROM codercom/code-server:latest

USER root

# CLIs and uv tools go to system paths so a persisted /home/coder volume never
# shadows them — only config/auth/projects/history live in the volume.
ENV NPM_CONFIG_PREFIX=/usr/local \
    UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_UNMANAGED_INSTALL=/usr/local/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates build-essential python3 python3-venv gh \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# docker CLI + compose plugin (client only — talks to the host's socket via
# docker-compose.manage.yml, no daemon in this image). Static builds, not the
# apt package, so the version is pinned and the image doesn't pull in a full
# dockerd it will never run.
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-29.8.0.tgz \
      | tar xz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
         https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-linux-x86_64 \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Terminal coding agents (npm) — opencode ships as opencode-ai.
RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @github/copilot \
        @qwen-code/qwen-code \
        opencode-ai

# uv-managed tools, baked so first boot doesn't download them into the volume:
# aider (its pinned deps don't build on 3.13), plus the graphify/Serena that
# bootstrap.sh would otherwise fetch at runtime.
RUN uv python install 3.12 3.13 \
    && uv tool install --python 3.12 aider-chat \
    && uv tool install graphifyy \
    && uv tool install --python 3.13 serena-agent

# dojo's optimizer configs + bootstrap.sh (idempotent wiring script). Kept
# outside /home/coder so the home volume can't shadow it; bootstrap.sh
# symlinks from here into the (persisted) home at every start.
COPY . /opt/dojo

# code-server's entrypoint runs every executable in ENTRYPOINTD at start
# (after fixuid, before code-server) — that is where we (re)wire the stack
# into whatever the /home/coder volume currently holds. Also kept outside
# the home volume.
ENV ENTRYPOINTD=/opt/entrypoint.d
COPY workspace/provision.sh /opt/entrypoint.d/10-dojo.sh
RUN chmod +x /opt/entrypoint.d/10-dojo.sh

USER coder
EXPOSE 8080
ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8080", "--disable-telemetry", "/home/coder/projects"]
