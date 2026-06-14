FROM --platform=$BUILDPLATFORM eclipse-temurin:17-jdk AS build
RUN curl -fsSL https://github.com/sbt/sbt/releases/download/v1.10.2/sbt-1.10.2.tgz \
    | tar xz -C /usr/local \
    && ln -sf /usr/local/sbt/bin/sbt /usr/local/bin/sbt
WORKDIR /app
COPY build.sbt ./
COPY project ./project/
COPY src ./src
RUN sbt -batch assembly

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/scala-2.13/logdemo-scala.jar app.jar
EXPOSE 8091
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
