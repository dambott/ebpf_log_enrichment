# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM rust:1.83-bookworm AS build
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
    $(case "${TARGETARCH}" in \
      amd64) echo "gcc-x86-64-linux-gnu libc6-dev-amd64-cross" ;; \
      arm64) echo "gcc-aarch64-linux-gnu libc6-dev-arm64-cross" ;; \
    esac) \
    && rm -rf /var/lib/apt/lists/*
RUN case "${TARGETARCH}" in \
      amd64) rustup target add x86_64-unknown-linux-gnu ;; \
      arm64) rustup target add aarch64-unknown-linux-gnu ;; \
    esac
ENV CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
WORKDIR /app
COPY Cargo.toml ./
COPY src ./src
RUN case "${TARGETARCH}" in \
      amd64) cargo build --release --target x86_64-unknown-linux-gnu ;; \
      arm64) cargo build --release --target aarch64-unknown-linux-gnu ;; \
    esac \
    && case "${TARGETARCH}" in \
      amd64) cp target/x86_64-unknown-linux-gnu/release/logdemo-rust /logdemo-rust ;; \
      arm64) cp target/aarch64-unknown-linux-gnu/release/logdemo-rust /logdemo-rust ;; \
    esac

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /logdemo-rust /app/logdemo-rust
EXPOSE 8086
ENTRYPOINT ["/app/logdemo-rust"]
