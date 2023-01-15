FROM docker.io/library/debian:11.6-slim AS base
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        gcc-9 \
        libc6-dev \
        make \
    && apt-get clean \
    && apt-get autoremove --purge \
    && rm --recursive --force /var/lib/apt/lists/* \
    && update-alternatives \
        --install /usr/bin/gcc        gcc        /usr/bin/gcc-9 10 \
        --slave   /usr/bin/gcc-ar     gcc-ar     /usr/bin/gcc-ar-9 \
        --slave   /usr/bin/gcc-nm     gcc-nm     /usr/bin/gcc-nm-9 \
        --slave   /usr/bin/gcc-ranlib gcc-ranlib /usr/bin/gcc-ranlib-9 \
        --slave   /usr/bin/gcov       gcov       /usr/bin/gcov-9 \
        --slave   /usr/bin/gcov-dump  gcov-dump  /usr/bin/gcov-dump-9 \
        --slave   /usr/bin/gcov-tool  gcov-tool  /usr/bin/gcov-tool-9 \
        --slave   /usr/bin/cpp        cpp        /usr/bin/cpp-9 \
    && update-alternatives \
        --install /usr/bin/cc cc /usr/bin/gcc 10

FROM base AS final
ENV USER="gcc"
RUN useradd --uid "1000" --create-home "$USER" --no-log-init
ENV HOME="/home/$USER"
WORKDIR "$HOME"
USER "$USER"
