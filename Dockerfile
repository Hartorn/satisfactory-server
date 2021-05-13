#syntax=docker/dockerfile:1.2

FROM steamcmd/steamcmd:latest AS builder
ARG STEAMBETA

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
ENV GAMECONFIGDIR="/home/satisfactory/.wine/drive_c/users/satisfactory/Local Settings/Application Data/FactoryGame/Saved"
# ENV GAMECONFIGDIR="/root/.wine/drive_c/users/root/Local Settings/Application Data/FactoryGame/Saved"
RUN mkdir -p /config/gamefiles /config/savefiles /config/saves "${GAMECONFIGDIR}/Config/WindowsNoEditor" "${GAMECONFIGDIR}/Logs" "${GAMECONFIGDIR}/SaveGames/common"
RUN touch "${GAMECONFIGDIR}/Logs/FactoryGame.log"

RUN useradd -ms /bin/bash satisfactory

RUN set -x \
    && dpkg --add-architecture i386 \
    && apt update \
    && apt install -y --no-install-recommends \
    wine-stable winbind ca-certificates \
    && rm -rf /var/lib/apt/lists/* 

COPY --chown=satisfactory:satisfactory Engine.ini "${GAMECONFIGDIR}/Config/WindowsNoEditor/Engine.ini"
COPY --chown=satisfactory:satisfactory Game.ini "${GAMECONFIGDIR}/Config/WindowsNoEditor/Game.ini"
COPY --chown=satisfactory:satisfactory Scalability.ini "${GAMECONFIGDIR}/Config/WindowsNoEditor/Scalability.ini"

COPY --chown=satisfactory:satisfactory --from=builder /gamefiles /config/gamefiles

EXPOSE 7777/udp

WORKDIR /home/satisfactory
RUN chown -R satisfactory:satisfactory /home/satisfactory ${GAMECONFIGDIR}
# RUN chown root:root "${GAMECONFIGDIR}/Config/WindowsNoEditor/Engine.ini" "${GAMECONFIGDIR}/Config/WindowsNoEditor/Game.ini"
USER satisfactory

ENTRYPOINT [ "sh ", "-c" ]
CMD ["wine start FactoryGame.exe -nosteamclient -nullrhi -nosplash -nosound && tail -f \"${GAMECONFIGDIR}/Logs/FactoryGame.log\""]
