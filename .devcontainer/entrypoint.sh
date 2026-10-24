#!/bin/sh
set -eu

echo "Entrypoint identity:"
id

echo "Entrypoint sudo permissions:"
/usr/bin/sudo -n -l

echo "Initializing firewall:"
/usr/bin/sudo -n /usr/local/bin/citewise-firewall.sh

# Important: check access denies and database restrictions
/usr/local/bin/citewise-verify-security.sh

# Start the container command only after security checks succeed.
exec "$@"
