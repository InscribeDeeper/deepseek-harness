# DeepSeek Harness Web UI, one container.
# Installs the published CLI instead of building the monorepo: the npm `alpha`
# dist-tag tracks this repository's prerelease line.
FROM node:22-bookworm-slim

ARG DSH_VERSION=alpha

# git: the agent's own tooling shells out to it in a workspace.
# socat + iproute2: republish the loopback-only web server on the container
#   interface (see docker/entrypoint.sh).
# ca-certificates: HTTPS to the model endpoint.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates git socat iproute2 procps \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" \
 && npm cache clean --force

# All harness user data (sessions, settings, credentials, profiles) lives under
# one root; mount a volume here or every session dies with the container.
ENV DSH_HOME=/data/dsh
ENV DSH_WEB_PORT=3080
# Bridge networking: republish the loopback bind on the container interface.
ENV DSH_WEB_PROXY=1

RUN mkdir -p /data/dsh /workspace && chown -R node:node /data /workspace

COPY --chmod=0755 entrypoint.sh /usr/local/bin/dsh-entrypoint

USER node
# The invoking directory is the default workspace root.
WORKDIR /workspace
EXPOSE 3080

ENTRYPOINT ["dsh-entrypoint"]
