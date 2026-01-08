ARG N8N_VERSION=latest

# ============================================
# Stage 1: Builder - Install tools in Alpine
# ============================================
FROM alpine:3.23 AS builder

# Install dependencies
RUN apk add --no-cache --update go postgresql-client libpcap-dev git make gcc musl-dev nmap

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
# Stage 2: Final - Copy to n8n image
# ============================================
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Copy postgresql binaries (actual binaries, not symlinks)
COPY --from=builder /usr/libexec/postgresql /usr/libexec/postgresql

# Create symlinks for postgresql commands
RUN ln -s /usr/libexec/postgresql/psql /usr/bin/psql && \
    ln -s /usr/libexec/postgresql/pg_dump /usr/bin/pg_dump && \
    ln -s /usr/libexec/postgresql/pg_restore /usr/bin/pg_restore && \
    ln -s /usr/libexec/postgresql/pg_isready /usr/bin/pg_isready && \
    ln -s /usr/libexec/postgresql/clusterdb /usr/bin/clusterdb && \
    ln -s /usr/libexec/postgresql/createdb /usr/bin/createdb && \
    ln -s /usr/libexec/postgresql/createuser /usr/bin/createuser && \
    ln -s /usr/libexec/postgresql/dropdb /usr/bin/dropdb && \
    ln -s /usr/libexec/postgresql/dropuser /usr/bin/dropuser && \
    ln -s /usr/libexec/postgresql/pg_amcheck /usr/bin/pg_amcheck && \
    ln -s /usr/libexec/postgresql/pg_basebackup /usr/bin/pg_basebackup && \
    ln -s /usr/libexec/postgresql/pg_dumpall /usr/bin/pg_dumpall && \
    ln -s /usr/libexec/postgresql/pg_receivewal /usr/bin/pg_receivewal && \
    ln -s /usr/libexec/postgresql/pg_recvlogical /usr/bin/pg_recvlogical && \
    ln -s /usr/libexec/postgresql/pg_verifybackup /usr/bin/pg_verifybackup && \
    ln -s /usr/libexec/postgresql/pgbench /usr/bin/pgbench && \
    ln -s /usr/libexec/postgresql/reindexdb /usr/bin/reindexdb && \
    ln -s /usr/libexec/postgresql/vacuumdb /usr/bin/vacuumdb

# Copy required libraries for postgresql-client
COPY --from=builder /usr/lib/libpq.so* /usr/lib/
COPY --from=builder /usr/lib/libldap.so* /usr/lib/
COPY --from=builder /usr/lib/liblber.so* /usr/lib/
COPY --from=builder /usr/lib/libsasl2.so* /usr/lib/
COPY --from=builder /usr/lib/libreadline.so* /usr/lib/
COPY --from=builder /usr/lib/libssl.so* /usr/lib/
COPY --from=builder /usr/lib/libcrypto.so* /usr/lib/
COPY --from=builder /usr/lib/libncursesw.so* /usr/lib/
COPY --from=builder /usr/lib/liblz4.so* /usr/lib/
COPY --from=builder /usr/lib/libzstd.so* /usr/lib/

# Copy pdtm and all tools from builder default path
COPY --from=builder /root/.pdtm/go/bin /home/node/.pdtm
RUN chown -R node:node /home/node/.pdtm

# Copy massdns binary (required for shuffledns)
COPY --from=builder /usr/local/bin/massdns /usr/local/bin/massdns

# Copy nmap
COPY --from=builder /usr/bin/nmap /usr/bin/nmap
COPY --from=builder /usr/share/nmap /usr/share/nmap

# Copy required libraries for nmap
COPY --from=builder /usr/lib/libpcap.so* /usr/lib/
COPY --from=builder /usr/lib/libssh2.so* /usr/lib/
COPY --from=builder /usr/lib/liblua-5.4.so* /usr/lib/

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
RUN tunnelx --version
RUN uncover --version
RUN urlfinder --version
RUN vulnx --version

# Other tools (2)
RUN massdns --help | head -1
RUN nmap --version | head -1

RUN echo "=== All 45 tools verified! ==="
