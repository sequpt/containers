FROM docker.io/library/debian:9.13-slim AS base
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        gcc-6 \
        libc6-dev \
        make \
    && apt-get clean \
    && apt-get autoremove --purge \
    && rm --recursive --force /var/lib/apt/lists/* \
    && update-alternatives \
        --install /usr/bin/gcc        gcc        /usr/bin/gcc-6 10 \
        --slave   /usr/bin/gcc-ar     gcc-ar     /usr/bin/gcc-ar-6 \
        --slave   /usr/bin/gcc-nm     gcc-nm     /usr/bin/gcc-nm-6 \
        --slave   /usr/bin/gcc-ranlib gcc-ranlib /usr/bin/gcc-ranlib-6 \
        --slave   /usr/bin/gcov       gcov       /usr/bin/gcov-6 \
        --slave   /usr/bin/gcov-dump  gcov-dump  /usr/bin/gcov-dump-6 \
        --slave   /usr/bin/gcov-tool  gcov-tool  /usr/bin/gcov-tool-6 \
        --slave   /usr/bin/cpp        cpp        /usr/bin/cpp-6 \
    && update-alternatives \
        --install /usr/bin/cc cc /usr/bin/gcc 10

FROM base AS final
ENV USER="gcc"
RUN useradd --uid "1000" --create-home "$USER" --no-log-init
ENV HOME="/home/$USER"
WORKDIR "$HOME"
USER "$USER"
