FROM gcc:14-bookworm AS build
WORKDIR /src
COPY main.cpp .
RUN g++ -O2 -static-libgcc -static-libstdc++ -o logdemo-cpp main.cpp

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /src/logdemo-cpp .
EXPOSE 8089
ENTRYPOINT ["./logdemo-cpp"]
