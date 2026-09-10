FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates coreutils device-tree-compiler dosfstools dpkg \
    e2fsprogs fdisk file findutils gzip jq kmod mount perl shellcheck \
    tar u-boot-tools util-linux xz-utils && rm -rf /var/lib/apt/lists/*
WORKDIR /armbian
CMD ["bash", "/src/ci/build.sh"]
