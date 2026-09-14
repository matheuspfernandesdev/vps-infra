FROM nginx:1.27-alpine

RUN apk add --no-cache curl \
    && rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY templates /etc/nginx/templates
