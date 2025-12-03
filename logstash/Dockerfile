FROM ubuntu:24.04

RUN --mount=type=cache,target=/var/cache/apt/archives,sharing=locked \
    apt-get update && apt-get install -y \
        neovim \
        wget \
        curl \
        vim \
        jq

RUN --mount=type=cache,target=/tmp/downloads \
    wget -nc -P /tmp/downloads https://artifacts.elastic.co/downloads/logstash/logstash-7.17.12-amd64.deb && \
    apt-get install -y -f /tmp/downloads/logstash-7.17.12-amd64.deb && \
    rm -rf /var/lib/apt/lists/*

COPY build/* /logstash/
WORKDIR /logstash

RUN chmod +x *.sh

ENV PATH="/usr/share/logstash/bin:${PATH}"
ENTRYPOINT ["bash"]
CMD ["/logstash/entrypoint.sh"]