FROM itzg/minecraft-server:java21

COPY --chmod=0755 import-server-data.sh /usr/local/bin/import-server-data
COPY --chmod=0755 backup-server-data.sh /usr/local/bin/backup-server-data

ADD https://github.com/ViaVersion/ViaVersion/releases/download/5.12.1/ViaVersion-5.12.1.jar /plugins/ViaVersion.jar
RUN echo "b8033807e7182c35003a45962352dd642c1e91880ca281da3a43cb6f481a95a2  /plugins/ViaVersion.jar" \
    | sha256sum --check - \
    && chmod 0644 /plugins/ViaVersion.jar

ADD https://download.geysermc.org/v2/projects/geyser/versions/2.11.3/builds/1251/downloads/spigot /plugins/Geyser-Spigot.jar
RUN echo "0bd00484f688c49e45f84f7c8bf9326f52d48a4c697d72a28526f2fe3f55dc36  /plugins/Geyser-Spigot.jar" \
    | sha256sum --check - \
    && chmod 0644 /plugins/Geyser-Spigot.jar

ADD https://github.com/restic/restic/releases/download/v0.16.4/restic_0.16.4_linux_amd64.bz2 /tmp/restic.bz2
RUN echo "3d4d43c169a9e28ea76303b1e8b810f0dcede7478555fdaa8959971ad499e324  /tmp/restic.bz2" \
    | sha256sum --check - \
    && apt-get update \
    && apt-get install --yes --no-install-recommends bzip2 \
    && bunzip2 --stdout /tmp/restic.bz2 > /usr/local/bin/restic \
    && chmod 0755 /usr/local/bin/restic \
    && rm /tmp/restic.bz2 \
    && rm --recursive --force /var/lib/apt/lists/*
