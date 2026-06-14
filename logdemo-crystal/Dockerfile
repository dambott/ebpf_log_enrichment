FROM crystallang/crystal:1.14.0 AS build
WORKDIR /app
COPY server.cr .
RUN crystal build --release -o logdemo-crystal server.cr

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgc1 libevent-2.1-7 libpcre2-8-0 libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/logdemo-crystal .
EXPOSE 8092
ENTRYPOINT ["./logdemo-crystal"]
