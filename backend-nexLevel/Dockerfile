FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 4567

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["NexChat.API/NexChat.API.csproj", "NexChat.API/"]
COPY ["NexChat.Core/NexChat.Core.csproj", "NexChat.Core/"]
COPY ["NexChat.Infrastructure/NexChat.Infrastructure.csproj", "NexChat.Infrastructure/"]

RUN dotnet restore "NexChat.API/NexChat.API.csproj"

COPY . .
RUN dotnet build "NexChat.API/NexChat.API.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "NexChat.API/NexChat.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# مجلد التخزين للملفات والصور (يُربط من السيرفر)
RUN mkdir -p /app/wwwroot/uploads

ENV ASPNETCORE_URLS=http://+:4567
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "NexChat.API.dll"]
