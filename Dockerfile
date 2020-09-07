FROM gcr.io/kaniko-project/executor:debug

COPY docker-entrypoint.sh /
ENTRYPOINT [ "/docker-entrypoint.sh" ]
