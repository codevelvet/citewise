#!/bin/sh
set -e

FORBIDDEN_PUBLIC_IP="8.8.8.8"     # A public IP that SHOULD be blocked

echo "=== [PRE-LAUNCH] devcontainer security verification ==="

# 1. OUTBOUND CHECK: Verify Data Exfiltration Prevention is Active
# We attempt to ping or probe a forbidden public asset. It SHOULD timeout.
echo "Testing egress restrictions..."
if nc -z -w 3 \$FORBIDDEN_PUBLIC_IP 53 2>/dev/null; then
    echo "❌ CRITICAL SECURITY FAILURE: Egress firewall is NOT active!" >&2
    echo "The container can freely access the public internet. Aborting AI agent launch." >&2
    exit 1
fi
echo "✅ Egress restriction verified (Public internet blocked)."


echo "🛡️ All security checks passed. Initializing AI Agent..."
echo "=================================================="


