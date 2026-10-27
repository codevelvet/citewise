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

USER vscode

# Use the absolute path in the ENTRYPOINT
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

