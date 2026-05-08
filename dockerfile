# Pinned to a Docker Hub digest so a moved `trixie-slim` tag cannot
# silently swap the base image under us. Refresh by running:
#   docker pull --platform=linux/amd64 debian:trixie-slim \
#     && docker inspect --format='{{index .RepoDigests 0}}' debian:trixie-slim
FROM --platform=linux/amd64 debian:trixie-slim@sha256:cedb1ef40439206b673ee8b33a46a03a0c9fa90bf3732f54704f99cb061d2c5a

ARG TAG=polkadot-stable2603
ARG BIN=eth-rpc
# SHA256 of the `eth-rpc` x86_64 release binary published on the
# polkadot-stable2603 GitHub release. Refresh by running:
#   curl -fsSL https://github.com/paritytech/polkadot-sdk/releases/download/${TAG}/${BIN}.sha256
ARG BIN_SHA256=df8462aa78a4940e3b33aecb50509f190002828db80a7089154cb2a05c58da8a

RUN apt-get update && apt-get install -y ca-certificates curl libssl3 && rm -rf /var/lib/apt/lists/*

# Verify the binary against its published SHA256 before installing.
# `sha256sum -c` exits non-zero on mismatch, failing the build, so a
# release retag or a download-MITM cannot land an unverified binary.
RUN curl -fsSL -o /tmp/${BIN} \
    https://github.com/paritytech/polkadot-sdk/releases/download/${TAG}/${BIN} \
  && echo "${BIN_SHA256}  /tmp/${BIN}" | sha256sum -c - \
  && install -m 0755 /tmp/${BIN} /usr/local/bin/${BIN} \
  && rm /tmp/${BIN}

ENTRYPOINT ["eth-rpc"]
