FROM debian:bookworm-slim

ADD https://github.com/superfly/flyctl/releases/download/v0.4.115/flyctl_0.4.115_Linux_x86_64.tar.gz /tmp/flyctl.tar.gz
RUN echo "8b99a37a546c6c5b3ecb10c0c1d962c62b1cda328934f17c55180281cbdeb72f  /tmp/flyctl.tar.gz" \
    | sha256sum --check - \
    && apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates jq \
    && tar --extract --gzip --file /tmp/flyctl.tar.gz --directory /usr/local/bin flyctl \
    && chmod 0755 /usr/local/bin/flyctl \
    && rm /tmp/flyctl.tar.gz \
    && rm --recursive --force /var/lib/apt/lists/*

COPY --chmod=0755 backup-trigger/trigger-backup.sh /usr/local/bin/trigger-backup

ENV HOME=/tmp/fly-home
RUN mkdir --parents "$HOME" && chmod 0700 "$HOME"

ENTRYPOINT ["/usr/local/bin/trigger-backup"]
