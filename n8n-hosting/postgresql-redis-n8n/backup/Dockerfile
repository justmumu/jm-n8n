FROM alpine:3.22

# Install required tools
RUN apk add --no-cache \
    postgresql-client \
    rclone \
    bash \
    gzip \
    tar \
    curl

# Copy backup script
COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
