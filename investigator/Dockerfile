ARG NODE_VERSION
FROM node:${NODE_VERSION}-bookworm-slim

ARG OPENCODE_CLI_VERSION

RUN apt-get update \
    && apt-get install --no-install-recommends --yes bash ca-certificates curl dnsutils grep jq ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global "opencode-ai@${OPENCODE_CLI_VERSION}"

RUN mkdir -p /investigator-workspace /home/node/.local/share/opencode \
    && chown -R node:node /investigator-workspace /home/node/.local

USER node
WORKDIR /investigator-workspace
CMD ["bash"]
