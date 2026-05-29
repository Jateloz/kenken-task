FROM python:3.13-slim-bookworm@sha256:751dafd410bc9e0f1a3c1f87fd90bf85ef7e2a02eb2a57ace1b03a89ab2b3618

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tmux \
        asciinema \
        curl \
        gnupg \
        ca-certificates \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir \
    pytest==8.4.1 \
    pytest-json-ctrf==0.3.5

COPY verifier-package.json /opt/ui-task-tests/package.json

RUN cd /opt/ui-task-tests \
    && npm install \
    && npx playwright install-deps chromium \
    && npx playwright install chromium

WORKDIR /app
