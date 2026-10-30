#!/bin/bash
# Dev container egress firewall for Citewise.
#
# Adapted from Anthropic's reference dev container (anthropics/claude-code,
# .devcontainer/init-firewall.sh), with these changes:
#   - Fails closed: traffic is blocked before anything else happens, and any
#     error leaves only loopback open. The network is never open while this runs.
#   - Outbound traffic to allowlisted addresses is HTTPS (TCP 443) only.
#   - No outbound SSH, and no direct DNS to outside servers. DNS goes through
#     Docker's resolver at 127.0.0.11, which is on loopback.
#   - No inbound rules keyed on source port alone, and no inbound access from
#     the Docker network.
#   - The local network is limited to Postgres on 5432, not a whole subnet.
#   - Connections tracked before setup are cleared, so none survive it.
#   - IPv6 is blocked whenever the container has it, and failure to block it
#     fails the setup.
#   - Safe to run more than once in the same container.
#
# Runs as root through a sudo rule that allows this script and nothing else.

set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

DB_SERVICE="postgres"  # Compose service name for the database
DB_PORT="5432"

# Fail closed: on any failed exit, drop every rule except loopback, so a
# half-finished setup can't leave earlier allow rules in place.
fail_closed() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "Firewall setup FAILED (exit $rc): blocking all traffic except loopback" >&2
    iptables -P INPUT DROP || true
    iptables -P FORWARD DROP || true
    iptables -P OUTPUT DROP || true
    iptables -F || true
    iptables -A INPUT -i lo -j ACCEPT || true
    iptables -A OUTPUT -o lo -j ACCEPT || true
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    ip6tables -F 2>/dev/null || true
    ip6tables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
    conntrack -F >/dev/null 2>&1 || true
  fi
}
trap fail_closed EXIT

# 1. Save Docker's internal DNS rules before flushing anything.
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# 2. Block everything first. From here on, only what is added below is allowed.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 3. Remove rules and sets from any earlier run.
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 4. Block IPv6 whenever the kernel has it. If blocking fails, setup fails.
if [ -e /proc/net/if_inet6 ]; then
  ip6tables -P INPUT DROP
  ip6tables -P FORWARD DROP
  ip6tables -P OUTPUT DROP
  ip6tables -F
  ip6tables -A INPUT -i lo -j ACCEPT
  ip6tables -A OUTPUT -o lo -j ACCEPT
  echo "IPv6 blocked (loopback only)"
else
  echo "IPv6 not available in this container"
fi

# 5. Clear tracked connections, so nothing opened before setup survives it
#    through the ESTABLISHED rule below.
conntrack -F >/dev/null 2>&1 || {
  echo "ERROR: Failed to clear tracked connections"
  exit 1
}

# 6. Restore only Docker's internal DNS resolution.
if [ -n "$DOCKER_DNS_RULES" ]; then
  echo "Restoring Docker DNS rules..."
  iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
  iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
  echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
  echo "No Docker DNS rules to restore"
fi

# 7. Loopback (includes Docker's resolver at 127.0.0.11) and replies to
#    connections allowed after this point.
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 8a. Rails dev server, reachable through the compose port mapping. Published-port
# traffic arrives from the Docker gateway, so allow only that source.
host_gw=$(ip route show default | awk 'NR==1 {print $3}')
host_if=$(ip route show default | awk 'NR==1 {print $5}')
[ -n "$host_gw" ] && [ -n "$host_if" ] || { echo "ERROR: no default route for port 3000 rule"; exit 1; }
iptables -A INPUT -i "$host_if" -p tcp -s "$host_gw" --dport 3000 -j ACCEPT

# 8b. Postgres only: its address on the Compose network, on its port.
db_ips=$(getent ahostsv4 "$DB_SERVICE" | awk '{print $1}' | sort -u)
if [ -z "$db_ips" ]; then
  echo "ERROR: Failed to resolve $DB_SERVICE"
  exit 1
fi
while read -r ip; do
  echo "Allowing $DB_SERVICE at $ip:$DB_PORT"
  iptables -A OUTPUT -p tcp -d "$ip" --dport "$DB_PORT" -j ACCEPT
done <<< "$db_ips"

# 9. The allowlist: HTTPS only, to addresses in the set. The set starts empty
#    and is filled below, so nothing outside is reachable until it's added.
ipset create allowed-domains hash:net
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-domains dst -j ACCEPT

# Reject everything else outbound, so failures are immediate instead of timeouts.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# Resolve a domain and add its IPv4 addresses to the allowlist.
add_domain() {
  local domain="$1"
  local ips
  echo "Resolving $domain..."
  ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
  if [ -z "$ips" ]; then
    echo "ERROR: Failed to resolve $domain"
    exit 1
  fi
  while read -r ip; do
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      echo "ERROR: Invalid IP from DNS for $domain: $ip"
      exit 1
    fi
    echo "Adding $ip for $domain"
    ipset -exist add allowed-domains "$ip"
  done <<< "$ips"
}

# 10. Allow api.github.com first, so GitHub's address ranges can be fetched
#     through the firewall.
add_domain "api.github.com"

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -fsS --connect-timeout 10 --max-time 30 https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
  echo "ERROR: Failed to fetch GitHub IP ranges"
  exit 1
fi
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
  echo "ERROR: GitHub API response missing required fields"
  exit 1
fi

echo "Processing GitHub IPs..."
# Capture the list first: a failure inside process substitution wouldn't stop
# the script, but a failure here does (set -e with pipefail).
gh_cidrs=$(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
if [ -z "$gh_cidrs" ]; then
  echo "ERROR: No GitHub IP ranges after processing"
  exit 1
fi
while read -r cidr; do
  if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
    exit 1
  fi
  echo "Adding GitHub range $cidr"
  ipset -exist add allowed-domains "$cidr"
done <<< "$gh_cidrs"

# 11. Everything else the container needs.
for domain in \
  "api.anthropic.com" \
  "sentry.io" \
  "statsig.com" \
  "marketplace.visualstudio.com" \
  "vscode.blob.core.windows.net" \
  "update.code.visualstudio.com" \
  "rubygems.org" \
  "index.rubygems.org" \
  "ai.mongodb.com"; do
  add_domain "$domain"
done

echo "Firewall configuration complete"

# 12. Verify: blocked where it should be, open where it should be.
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - was able to reach https://example.com"
  exit 1
fi
echo "Firewall verification passed - unable to reach https://example.com as expected"

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
  exit 1
fi
echo "Firewall verification passed - able to reach https://api.github.com as expected"

# github.com isn't added by name, only through GitHub's published ranges, so
# reaching it shows the ranges were actually loaded.
if ! curl --connect-timeout 5 -sI https://github.com >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - unable to reach https://github.com (GitHub ranges missing?)"
  exit 1
fi
echo "Firewall verification passed - able to reach https://github.com through GitHub's ranges"

if ! timeout 5 bash -c "</dev/tcp/$DB_SERVICE/$DB_PORT" 2>/dev/null; then
  echo "ERROR: Firewall verification failed - unable to reach $DB_SERVICE:$DB_PORT"
  exit 1
fi
echo "Firewall verification passed - able to reach $DB_SERVICE:$DB_PORT as expected"

if [ "$(iptables -S OUTPUT | head -1)" != "-P OUTPUT DROP" ]; then
  echo "ERROR: Firewall verification failed - IPv4 OUTPUT policy is not DROP"
  exit 1
fi
if [ -e /proc/net/if_inet6 ] && [ "$(ip6tables -S OUTPUT | head -1)" != "-P OUTPUT DROP" ]; then
  echo "ERROR: Firewall verification failed - IPv6 OUTPUT policy is not DROP"
  exit 1
fi
echo "Firewall verification passed - default policies are DROP"

