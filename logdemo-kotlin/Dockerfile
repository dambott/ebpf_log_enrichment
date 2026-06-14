FROM --platform=$BUILDPLATFORM gradle:8.11-jdk17 AS build
WORKDIR /app
COPY build.gradle.kts settings.gradle.kts ./
COPY src ./src
RUN gradle --no-daemon jar

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/build/libs/logdemo-kotlin-1.0.0.jar app.jar
EXPOSE 8090
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
