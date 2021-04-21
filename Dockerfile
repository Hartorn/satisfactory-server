#syntax=docker/dockerfile:1.2

FROM steamcmd/steamcmd:latest AS builder
# ARG STEAMUSER
# ARG STEAMPWD
# ARG STEAMCODE
ARG STEAMBETA

ENV STEAMAPPID 526870

# ENV STEAMAPPID=526870 \
#     STEAMBETA=false

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


# RUN set -x \
#     && dpkg --add-architecture i386 \
#     && apt-get update \
#     && apt-get install -y \
#         cron \
#         libfreetype6 \
#         libfreetype6:i386 \
#         # nano \
#         # python3 \
#         # tmux \
#         # vim \
#         # winbind \
#         wine-stable \
#     && mkdir -p /config /config/gamefiles /config/saves \
#     && rm -rf /var/lib/apt/lists/* 

FROM ubuntu:20.04

COPY --from=builder /gamefiles /config/gamefiles

ENV GAMECONFIGDIR="/root/.wine/drive_c/users/root/Local Settings/Application Data/FactoryGame/Saved"
RUN mkdir -p /config/gamefiles /config/savefiles /config/saves "${GAMECONFIGDIR}/Config/WindowsNoEditor" "${GAMECONFIGDIR}/Logs" "${GAMECONFIGDIR}/SaveGames/common"
RUN touch "${GAMECONFIGDIR}/Logs/FactoryGame.log"

# RUN mkdir -p /config/gamefiles /config/saves

# touch "${GAMECONFIGDIR}/Config/WindowsNoEditor/Engine.ini" "${GAMECONFIGDIR}/Config/WindowsNoEditor/Game.ini" "${GAMECONFIGDIR}/Logs/FactoryGame.log"

# RUN mkdir -p /config/gamefiles /config/saves

RUN set -x \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y cron sudo wine-stable \
    && mkdir -p /config \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash satisfactory

COPY Game.ini Engine.ini Scalability.ini /home/satisfactory/
COPY backup.sh init.sh /

RUN chmod +x "/backup.sh" "/init.sh"

# VOLUME /config
# WORKDIR /config

ENV GAMECONFIGDIR="/home/satisfactory/.wine/drive_c/users/satisfactory/Local Settings/Application Data/FactoryGame/Saved" \
    STEAMAPPID="526870" \
    STEAMBETA="false"

EXPOSE 7777/udp

ENTRYPOINT [ "bash", "-c" ]
CMD ["wine start FactoryGame.exe -nosteamclient -nullrhi -nosplash -nosound && tail -f \"${GAMECONFIGDIR}/Logs/FactoryGame.log\""]
