FROM alpine:latest AS base
RUN apk update \
   && apk add --no-cache \
      doxygen \
      graphviz \
      make \
      ttf-freefont

FROM base AS final
ENV USER="doxygen"
RUN adduser --disabled-password --uid "1000" "$USER"
ENV HOME="/home/$USER"
WORKDIR "$HOME"
USER "$USER"
