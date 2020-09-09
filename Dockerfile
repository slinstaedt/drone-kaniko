FROM gcr.io/kaniko-project/executor:debug

SHELL [ "/busybox/sh", "-c" ]
RUN mkdir -p /tmp && chmod 1777 /tmp

COPY docker-entrypoint.sh /
ENTRYPOINT [ "/docker-entrypoint.sh" ]
