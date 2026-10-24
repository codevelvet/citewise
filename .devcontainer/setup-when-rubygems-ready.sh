#!/bin/sh
set -e

# Wait for lockfile
# This is startup synchronization for rubygems
# Success does not prove firewall or database restrictions are active.

attempt=1
# 1. Block here until the Dockerfile firewall script creates the lockfile
while [ ! -f /tmp/firewall_ready.lock ]; do
  if [ "$attempt" -gt 120 ]; then
    echo "Timeout waiting for firewall and verification to complete." >&2
    exit 1
  fi
  echo "Waiting for firewall allowlist and verification initialization ($attempt/120)..." >&2
  attempt=$((attempt + 1))
  sleep 1
done

echo "Firewall initialization detected. Running setup which hits rubygems..."
exec "bin/setup" --skip-server
