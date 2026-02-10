FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    conntrack \
    iptables \
    socat \
    containernetworking-plugins \
    cri-tools \
    curl \
    ca-certificates \
    systemd \
    systemd-sysv \
    && rm -rf /var/lib/apt/lists/*

# Download and install MicroShift
ARG MICROSHIFT_VERSION=4.17.0
RUN curl -sSL "https://github.com/openshift/microshift/releases/download/nightly/microshift-linux-amd64" \
    -o /usr/local/bin/microshift && \
    chmod +x /usr/local/bin/microshift

# Create required directories
RUN mkdir -p /var/lib/microshift/manifests && \
    mkdir -p /var/lib/microshift/resources/kubeadmin && \
    mkdir -p /etc/microshift

# Create MicroShift config
RUN cat > /etc/microshift/config.yaml <<EOF
apiServer:
  subjectAltNames:
    - microshift.local
    - localhost
network:
  clusterNetwork:
    - 10.42.0.0/16
  serviceNetwork:
    - 10.43.0.0/16
EOF

# Copy startup scripts
COPY start-container.sh /usr/local/bin/start-microshift
RUN chmod +x /usr/local/bin/start-microshift

# Expose API server port
EXPOSE 6443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -k https://localhost:6443/healthz || exit 1

# Use systemd as init
ENTRYPOINT ["/usr/local/bin/start-microshift"]
