FROM quay.io/curl/curl:8.15.0

USER root

COPY entrypoint.sh /app/entrypoint.sh

RUN apk add --no-cache --update bash jq\
    && rm -rf /var/cache/apk/* \
    && adduser -D -u 1000 vm_exporter \
    && chown vm_exporter:vm_exporter /app/entrypoint.sh \
    && chmod +x /app/entrypoint.sh

USER vm_exporter

WORKDIR /app

ENTRYPOINT ["bash", "/app/entrypoint.sh"]