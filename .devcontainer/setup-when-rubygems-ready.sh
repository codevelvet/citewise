#!/bin/sh
set -eu

# Wait for RubyGems connectivity before installing dependencies.
# This is startup synchronization only, NOT security verification.
# Success does not prove firewall or database restrictions are active.
attempt=1
while [ "$attempt" -le 30 ]; do
  if curl --noproxy '*' -4 -fsS \
      --connect-timeout 2 --max-time 3 \
      --output /dev/null \
      https://index.rubygems.org/info/rails; then
    exec bin/setup --skip-server
  fi

  echo "Waiting for RubyGems HTTPS access ($attempt/30)..." >&2
  attempt=$((attempt + 1))
  sleep 1
done

echo "RubyGems is unreachable; setup aborted." >&2
exit 1
