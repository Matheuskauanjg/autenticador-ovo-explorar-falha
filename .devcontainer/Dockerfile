FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl unzip default-jdk xvfb x11vnc novnc websockify libgl1 libegl1 libpulse0 libxcb-cursor0 libxkbcommon-x11-0 libnss3 libdbus-1-3 && rm -rf /var/lib/apt/lists/*
