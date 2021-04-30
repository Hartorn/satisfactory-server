#syntax=docker/dockerfile:1.2

FROM steamcmd/steamcmd:latest AS builder
ARG STEAMBETA
ENV DEBIAN_FRONTEND noninteractive

ENV STEAMAPPID 526870

RUN dpkg --add-architecture i386 && \
    apt-get update &&\
    apt-get install -y --no-install-recommends lib32gcc1 libstdc++6 libstdc++6:i386 

RUN mkdir -p /gamefiles
RUN --mount=type=secret,id=steam_user \
    --mount=type=secret,id=steam_password \
    --mount=type=secret,id=steam_guard_code \
    steamcmd +@sSteamCmdForcePlatformType windows \
    +login "$(cat /run/secrets/steam_user)" "$(cat /run/secrets/steam_password)" "$(cat /run/secrets/steam_guard_code)" \
    +force_install_dir /gamefiles \
    +app_update "${STEAMAPPID}" ${STEAMBETAFLAGS} \
    +quit

FROM ubuntu:20.04
ENV DEBIAN_FRONTEND noninteractive

ENV GAMECONFIGDIR="/root/.wine/drive_c/users/root/Local Settings/Application Data/FactoryGame/Saved"
RUN mkdir -p /config/gamefiles "${GAMECONFIGDIR}/Config/WindowsNoEditor" "${GAMECONFIGDIR}/Logs" "${GAMECONFIGDIR}/SaveGames/common"
RUN touch "${GAMECONFIGDIR}/Logs/FactoryGame.log"

RUN set -x \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y wine-stable \
    && mkdir -p /config \
    && rm -rf /var/lib/apt/lists/*

COPY Game.ini Engine.ini Scalability.ini /home/satisfactory/

EXPOSE 7777/udp

WORKDIR /config/gamefiles

ENTRYPOINT [ "bash", "-c" ]
CMD ["wine start FactoryGame.exe -nosteamclient -nullrhi -nosplash -nosound && tail -f \"${GAMECONFIGDIR}/Logs/FactoryGame.log\""]
