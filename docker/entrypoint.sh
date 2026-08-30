#!/bin/sh
# Start the Web UI and, in bridge networking, republish it on the container interface.
set -eu

PORT="${DSH_WEB_PORT:-3080}"

# `dsh web` rejects --host 0.0.0.0 by design (it would expose host-authority
# command execution to the network), so the server binds container loopback and
# socat forwards from the container's own address on the SAME port. Same port,
# different address: the tokenized URL printed at startup then works verbatim in
# a host browser reached through `-p 127.0.0.1:3080:3080`.
# Skip it with DSH_WEB_PROXY=0 under --network host, where the loopback bind is
# already the host's and this forward would publish the agent to the LAN.
if [ "${DSH_WEB_PROXY:-0}" = "1" ]; then
  container_ip="$(ip -4 -o addr show scope global | awk '{ print $4 }' | cut -d/ -f1 | head -n 1)"
  if [ -z "$container_ip" ]; then
    echo "dsh-entrypoint: no global IPv4 address to publish on; set DSH_WEB_PROXY=0" >&2
    exit 1
  fi
  socat "TCP-LISTEN:${PORT},bind=${container_ip},fork,reuseaddr" "TCP:127.0.0.1:${PORT}" &
fi

# No browser in the container to hand the URL to; it is printed for the host.
exec dsh web --no-open --port "$PORT" "$@"
