# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.7
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"

USER root

# Tools the firewall needs
RUN apt-get update \
 && sudo apt-get install -y --no-install-recommends iptables ipset dnsutils aggregate jq curl \
 && rm -rf /var/lib/apt/lists/*

# vscode may run the firewall script as root, with no arguments, and nothing else
COPY .devcontainer/init-firewall.sh /usr/local/bin/citewise-firewall.sh
RUN chown root:root /usr/local/bin/citewise-firewall.sh \
 && chmod 0755 /usr/local/bin/citewise-firewall.sh \
 && rm -f /etc/sudoers.d/vscode \
 && echo 'vscode ALL=(root) NOPASSWD: /usr/local/bin/citewise-firewall.sh ""' > /etc/sudoers.d/vscode-firewall \
 && chmod 0440 /etc/sudoers.d/vscode-firewall \
 && visudo -c
USER vscode
