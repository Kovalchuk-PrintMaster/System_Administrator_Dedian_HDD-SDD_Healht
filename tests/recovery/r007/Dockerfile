# Debian 12 userspace only. Container is NOT a Debian VM or systemd PID 1.
FROM debian:12-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates coreutils curl findutils gawk git gnupg grep \
      procps sed smartmontools systemd util-linux \
 && rm -rf /var/lib/apt/lists/*
COPY repo/ /root/disk-health-restore/
COPY r007_container_acceptance.sh /usr/local/bin/r007_container_acceptance.sh
RUN chmod 0755 /usr/local/bin/r007_container_acceptance.sh
WORKDIR /root/disk-health-restore
CMD ["/bin/bash", "/usr/local/bin/r007_container_acceptance.sh"]
