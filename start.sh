#!/bin/sh
set -eu

TAILSCALE_STATE_DIR="/var/lib/tailscale"
TAILSCALE_SOCKET="/var/run/tailscale/tailscaled.sock"

: "${TAILSCALE_AUTHKEY:?Set TAILSCALE_AUTHKEY as a Fly secret}"
TS_HOSTNAME="${TS_HOSTNAME:-fly-exit-node}"

mkdir -p "${TAILSCALE_STATE_DIR}" /var/run/tailscale

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

/app/tailscaled \
  --state="${TAILSCALE_STATE_DIR}/tailscaled.state" \
  --socket="${TAILSCALE_SOCKET}" &
tailscaled_pid=$!

cleanup() {
  if kill -0 "${tailscaled_pid}" 2>/dev/null; then
    kill -TERM "${tailscaled_pid}"
  fi
  wait "${tailscaled_pid}" || true
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

attempt=0
until /app/tailscale --socket="${TAILSCALE_SOCKET}" status >/dev/null 2>&1; do
  if ! kill -0 "${tailscaled_pid}" 2>/dev/null; then
    echo "tailscaled exited before its control socket became ready" >&2
    exit 1
  fi

  attempt=$((attempt + 1))
  if [ "${attempt}" -ge 30 ]; then
    echo "Timed out waiting for tailscaled to become ready" >&2
    exit 1
  fi
  sleep 1
done

/app/tailscale --socket="${TAILSCALE_SOCKET}" up \
  --auth-key="${TAILSCALE_AUTHKEY}" \
  --hostname="${TS_HOSTNAME}" \
  --advertise-exit-node

wait "${tailscaled_pid}"
