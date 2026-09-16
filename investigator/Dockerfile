ARG NODE_VERSION
FROM node:${NODE_VERSION}-bookworm-slim

ARG OPENCODE_CLI_VERSION

RUN apt-get update \
    && apt-get install --no-install-recommends --yes bash ca-certificates curl dnsutils grep jq ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global "opencode-ai@${OPENCODE_CLI_VERSION}"

RUN mkdir -p /investigator-workspace /home/node/.local/share/opencode \
    && chown -R node:node /investigator-workspace /home/node/.local

COPY --chown=node:node investigator/README.md investigator/architecture.md investigator/INVESTIGATION_PROTOCOL.md investigator/investigation.md /investigator-workspace/
COPY --chown=node:node investigator/bin/promq /investigator-workspace/bin/promq
RUN chmod 0755 /investigator-workspace/bin/promq

USER node
WORKDIR /investigator-workspace
CMD ["bash"]
