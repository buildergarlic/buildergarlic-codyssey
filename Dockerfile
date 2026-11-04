FROM nginx:alpine

LABEL maintainer="buildergarlic"

COPY ./app /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -qO- http://localhost/ || exit 1
