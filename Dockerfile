ARG N8N_VERSION=latest

# ============================================
# Stage 1: Builder - Install tools in Alpine
# ============================================
FROM alpine:3.23 AS builder

# Install dependencies
RUN apk add --no-cache --update go postgresql-client

# Set Go environment
ENV GOPATH=/root/go
ENV PATH="${GOPATH}/bin:${PATH}"

# Install pdtm
RUN go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest

# Create tools directory and install all ProjectDiscovery tools
RUN mkdir -p /tools && \
    /root/go/bin/pdtm -install-all -bp /tools

# ============================================
# Stage 2: Final - Copy to n8n image
# ============================================
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Copy postgresql-client binaries from builder
COPY --from=builder /usr/bin/psql /usr/bin/psql
COPY --from=builder /usr/bin/pg_dump /usr/bin/pg_dump
COPY --from=builder /usr/bin/pg_restore /usr/bin/pg_restore
COPY --from=builder /usr/bin/pg_isready /usr/bin/pg_isready

# Copy required libraries for postgresql-client
COPY --from=builder /usr/lib/libpq.so* /usr/lib/
COPY --from=builder /usr/lib/libldap.so* /usr/lib/
COPY --from=builder /usr/lib/liblber.so* /usr/lib/
COPY --from=builder /usr/lib/libsasl2.so* /usr/lib/

# Copy pdtm and all tools from builder
COPY --from=builder /tools /home/node/.pdtm
RUN chown -R node:node /home/node/.pdtm

USER node

# Set PATH for node user
ENV PATH="/home/node/.pdtm:${PATH}"
