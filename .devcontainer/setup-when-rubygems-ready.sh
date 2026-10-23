#!/bin/sh
set -e

# Wait for RubyGems connectivity before installing dependencies.
# This is startup synchronization only, NOT security verification.
# Success does not prove firewall or database restrictions are active.

attempt=1
# 1. Block here until the Dockerfile firewall script creates the lockfile
while [ ! -f /tmp/firewall_ready.lock ]; do
  if [ "$attempt" -gt 30 ]; then
    echo "Timeout waiting for firewall initialization script to complete." >&2
    exit 1
  fi
  echo "Waiting for firewall allowlist initialization ($attempt/30)..." >&2
  attempt=$((attempt + 1))
  sleep 1
done

echo "Firewall initialization detected. Testing actual RubyGems network path..."
exec "bin/setup" --skip-server
