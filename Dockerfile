ARG N8N_VERSION=latest

FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install dependencies
RUN apk add --no-cache --update postgresql-client go

# Set Go environment for build
ENV GOPATH=/root/go
ENV PATH="${GOPATH}/bin:${PATH}"

# Install pdtm
RUN go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest

# Create pdtm directory for node user and copy pdtm binary
RUN mkdir -p /home/node/.pdtm && \
    cp /root/go/bin/pdtm /home/node/.pdtm/ && \
    chown -R node:node /home/node/.pdtm

# Clean up Go (no longer needed)
RUN apk del go && rm -rf /root/go /root/.cache

USER node

# Set PATH for node user
ENV PATH="/home/node/.pdtm:${PATH}"

# Install all ProjectDiscovery tools as node user
RUN /home/node/.pdtm/pdtm -install-all -bp /home/node/.pdtm
