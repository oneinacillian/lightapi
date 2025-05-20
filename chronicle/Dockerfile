FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget vim \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/local

# Download and install Chronicle
RUN wget https://github.com/EOSChronicleProject/eos-chronicle/releases/download/v3.3/antelope-chronicle-3.3-Clang-11.0.1-ubuntu22.04-x86_64.deb \
    && apt install -y ./antelope-chronicle-3.3-Clang-11.0.1-ubuntu22.04-x86_64.deb \
    && rm antelope-chronicle-3.3-Clang-11.0.1-ubuntu22.04-x86_64.deb

# Create config directory
RUN mkdir -p /srv/eos/chronicle-config /srv/eos/snapshot

COPY ./config.ini /srv/eos/chronicle-config/
COPY ./start-chronicle.sh /start-chronicle.sh
# COPY ./snapshot/wax.snapshot_1737262622 /srv/eos/snapshot/wax.snapshot
RUN chmod +x /start-chronicle.sh

EXPOSE 8100

ENTRYPOINT ["/start-chronicle.sh"]