# syntax=docker/dockerfile:1
# Build SDK stage on the host arch (fast on Apple Silicon); publish linux/amd64 for EKS.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG TARGETARCH
WORKDIR /src
COPY logdemo-dotnet.csproj .
RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet restore -a "${TARGETARCH}"
COPY Program.cs .
RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet publish -c Release -o /app/publish /p:UseAppHost=false -a "${TARGETARCH}" --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8085
ENV ASPNETCORE_URLS=http://0.0.0.0:8085
ENTRYPOINT ["dotnet", "logdemo-dotnet.dll"]
