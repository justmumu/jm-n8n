ARG N8N_VERSION=latest

# ============================================
# Stage 1: Builder - Install tools in Alpine
# ============================================
FROM alpine:3.23 AS builder

# Install Go and build dependencies
RUN apk add --no-cache --update go curl

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

# Install postgresql-client from Alpine repos (need to add apk first)
COPY --from=alpine:3.23 /sbin/apk /sbin/apk
COPY --from=alpine:3.23 /etc/apk /etc/apk
COPY --from=alpine:3.23 /lib/apk /lib/apk
COPY --from=alpine:3.23 /usr/share/apk /usr/share/apk
COPY --from=alpine:3.23 /var/cache/apk /var/cache/apk

RUN apk add --no-cache postgresql-client && \
    rm -rf /sbin/apk /etc/apk /lib/apk /usr/share/apk /var/cache/apk

# Copy pdtm and all tools from builder
COPY --from=builder /tools /home/node/.pdtm
RUN chown -R node:node /home/node/.pdtm

USER node

# Set PATH for node user
ENV PATH="/home/node/.pdtm:${PATH}"
