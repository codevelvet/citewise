# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.9
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"

USER root

# Setup managed-settings.json
COPY .devcontainer/managed-settings.json /etc/claude-code/managed-settings.json
RUN chown root:root /etc/claude-code/managed-settings.json \
  && chmod 0644 /etc/claude-code/managed-settings.json

# Tools the firewall needs
RUN apt-get update \
 && sudo apt-get install -y --no-install-recommends iptables ipset dnsutils aggregate jq curl conntrack \
 && rm -rf /var/lib/apt/lists/*

# vscode may run the firewall script as root, with no arguments, and nothing else
COPY .devcontainer/init-firewall.sh /usr/local/bin/citewise-firewall.sh
RUN chown root:root /usr/local/bin/citewise-firewall.sh \
 && chmod 0755 /usr/local/bin/citewise-firewall.sh \
 && rm -f /etc/sudoers.d/vscode \
 && echo 'vscode ALL=(root) NOPASSWD: /usr/local/bin/citewise-firewall.sh ""' > /etc/sudoers.d/vscode-firewall \
 && chmod 0440 /etc/sudoers.d/vscode-firewall \
 && visudo -c

# Critical security checks which must pass or the devcontainer is not started
COPY .devcontainer/verify-security.sh /usr/local/bin/citewise-verify-security.sh
RUN chown root:root /usr/local/bin/citewise-verify-security.sh \
 && chmod 0755 /usr/local/bin/citewise-verify-security.sh

# ./bin/setup when rubygems available
COPY .devcontainer/setup-when-rubygems-ready.sh /usr/local/bin/citewise-setup-when-rubygems-ready.sh
RUN chown root:root /usr/local/bin/citewise-setup-when-rubygems-ready.sh \
 && chmod 0755 /usr/local/bin/citewise-setup-when-rubygems-ready.sh

# Copy the script from your host machine to an absolute path in the image
COPY .devcontainer/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chown root:root /usr/local/bin/entrypoint.sh \
  && chmod 0755 /usr/local/bin/entrypoint.sh

# Node and Playwright for browser tests. Node is pinned and checksummed. The
# browsers download here at build time, so tests need no network at runtime.
ARG NODE_VERSION=24.21.0
ARG NODE_SHA256_AMD64=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
ARG NODE_SHA256_ARM64=6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2
ARG TARGETARCH
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
COPY test/playwright/package.json test/playwright/package-lock.json /opt/playwright-cli/
RUN case "$TARGETARCH" in \
      amd64) arch=x64; sum="$NODE_SHA256_AMD64" ;; \
      arm64) arch=arm64; sum="$NODE_SHA256_ARM64" ;; \
      *) echo "Unsupported architecture: $TARGETARCH"; exit 1 ;; \
    esac \
 && file="node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
 && curl -fsSLo "/tmp/$file" "https://nodejs.org/dist/v${NODE_VERSION}/$file" \
 && echo "$sum  /tmp/$file" | sha256sum -c - \
 && tar -xJf "/tmp/$file" -C /usr/local --strip-components=1 --no-same-owner \
 && rm "/tmp/$file" \
 && ln -s /opt/playwright-cli/node_modules/.bin/playwright /usr/local/bin/playwright \
 && npm ci --ignore-scripts --prefix /opt/playwright-cli \
 && playwright install --with-deps --only-shell chromium webkit \
 && chmod -R a+rX,go-w "$PLAYWRIGHT_BROWSERS_PATH" \
 && rm -rf /var/lib/apt/lists/* /root/.npm

USER vscode

# Build-time checks: vscode may run only the firewall script as root, with no
# arguments, and the security files and browser-test tools must stay root-owned and unwritable.
RUN ! sudo -n true 2>/dev/null \
 && sudo -n -l /usr/local/bin/citewise-firewall.sh >/dev/null \
 && ! sudo -n -l /usr/local/bin/citewise-firewall.sh --any-argument >/dev/null 2>&1 \
 && test ! -e /etc/sudoers.d/vscode \
 && test "$(stat -c '%U:%a' /etc/claude-code/managed-settings.json)" = "root:644" \
 && for f in citewise-firewall.sh citewise-verify-security.sh entrypoint.sh; do \
      test "$(stat -c '%U:%a' "/usr/local/bin/$f")" = "root:755" || exit 1; \
    done \
 && test "$(stat -c '%U' /opt/playwright-browsers)" = "root" \
 && ! test -w /opt/playwright-browsers \
 && test "$(stat -c '%U' /opt/playwright-cli)" = "root" \
 && ! test -w /opt/playwright-cli

# Use the absolute path in the ENTRYPOINT
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

