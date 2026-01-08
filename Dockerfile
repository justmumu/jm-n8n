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
    ln -s /usr/libexec/postgresql/pg_isready /usr/bin/pg_isready

# Copy required libraries for postgresql-client
COPY --from=builder /usr/lib/libpq.so* /usr/lib/
COPY --from=builder /usr/lib/libldap.so* /usr/lib/
COPY --from=builder /usr/lib/liblber.so* /usr/lib/
COPY --from=builder /usr/lib/libsasl2.so* /usr/lib/

# Copy pdtm and all tools from builder default path
COPY --from=builder /root/.pdtm/go/bin /home/node/.pdtm
RUN chown -R node:node /home/node/.pdtm

# Copy massdns binary (required for shuffledns)
COPY --from=builder /usr/local/bin/massdns /usr/local/bin/massdns

# Copy nmap
COPY --from=builder /usr/bin/nmap /usr/bin/nmap
COPY --from=builder /usr/share/nmap /usr/share/nmap

USER node

# Set PATH for node user
ENV PATH="/home/node/.pdtm:${PATH}"

# ============================================
# Verify installations
# ============================================
RUN echo "=== Verifying PostgreSQL client ===" && psql --version

RUN echo "=== Verifying pdtm tools ===" && ls -la /home/node/.pdtm/

RUN echo "=== nuclei ===" && nuclei --version

RUN echo "=== httpx ===" && httpx --version

RUN echo "=== subfinder ===" && subfinder --version

RUN echo "=== massdns ===" && massdns --help | head -1

RUN echo "=== nmap ===" && nmap --version | head -1

RUN echo "=== All verifications passed! ==="
