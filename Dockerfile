ARG N8N_VERSION=latest
ARG ALPINE_VERSION=3.23

# ============================================
# Stage 1: Builder - Compile Go tools
# ============================================
FROM alpine:${ALPINE_VERSION} AS builder

# Install build dependencies
RUN apk add --no-cache go libpcap-dev git make gcc musl-dev

# Set Go environment
ENV GOPATH=/root/go
ENV PATH="${GOPATH}/bin:${PATH}"

# Build and install massdns (required for shuffledns)
RUN git clone https://github.com/blechschmidt/massdns.git /tmp/massdns && \
    cd /tmp/massdns && \
    make && \
    cp bin/massdns /usr/local/bin/ && \
    rm -rf /tmp/massdns

# Install pdtm
RUN go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest

# Install all ProjectDiscovery tools to default path (/root/.pdtm/go/bin)
RUN /root/go/bin/pdtm -install-all

# ============================================
# Stage 2: Final - n8n with tools
# ============================================
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Copy apk from builder (same Alpine version = compatible)
COPY --from=builder /sbin/apk /sbin/apk
COPY --from=builder /usr/lib/libapk.so* /usr/lib/

# Install packages with apk (no manual library copying needed!)
RUN apk add --no-cache postgresql-client nmap && \
    rm -f /sbin/apk /usr/lib/libapk.so*

# Copy pdtm and all tools from builder
COPY --from=builder /root/.pdtm/go/bin /home/node/.pdtm
RUN chown -R node:node /home/node/.pdtm

# Copy massdns binary (required for shuffledns)
COPY --from=builder /usr/local/bin/massdns /usr/local/bin/massdns

USER node

# Set PATH for node user
ENV PATH="/home/node/.pdtm:${PATH}"

# ============================================
# Verify installations
# ============================================

# PostgreSQL tools (18)
RUN psql --version
RUN pg_dump --version
RUN pg_restore --version
RUN pg_isready --version
RUN clusterdb --version
RUN createdb --version
RUN createuser --version
RUN dropdb --version
RUN dropuser --version
RUN pg_amcheck --version
RUN pg_basebackup --version
RUN pg_dumpall --version
RUN pg_receivewal --version
RUN pg_recvlogical --version
RUN pg_verifybackup --version
RUN pgbench --version
RUN reindexdb --version
RUN vacuumdb --version

# pdtm tools (25)
RUN aix --version
RUN alterx --version
RUN asnmap --version
RUN cdncheck --version
RUN chaos-client --version
RUN cloudlist --version
RUN dnsx --version
RUN httpx --version
RUN interactsh-client --version
RUN interactsh-server --version
RUN katana --version
RUN mapcidr --version
RUN notify --version
RUN nuclei --version
RUN pdtm --version
RUN proxify --version
RUN shuffledns --version
RUN simplehttpserver --version
RUN subfinder --version
RUN tldfinder --version
RUN tlsx --version
RUN tunnelx --help | head -1
RUN uncover --version
RUN urlfinder --version
RUN vulnx version

# Other tools (2)
RUN massdns --help | head -1
RUN nmap --version | head -1

RUN echo "=== All 45 tools verified! ==="
