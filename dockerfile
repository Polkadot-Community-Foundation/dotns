FROM rust:1.92-slim AS builder

RUN apt-get update && apt-get install -y \
    clang \
    llvm \
    llvm-dev \
    libclang-dev \
    cmake \
    protobuf-compiler \
    libssl-dev \
    pkg-config \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN rustup component add rust-src
RUN rustup target add wasm32-unknown-unknown

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo install pallet-revive-eth-rpc


FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/cargo/bin/eth-rpc /usr/local/bin/eth-rpc

EXPOSE 8545
ENTRYPOINT ["eth-rpc"]