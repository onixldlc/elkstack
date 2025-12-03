FROM ubuntu:24.04

RUN --mount=type=cache,target=/var/cache/apt/archives,sharing=locked \
    apt-get update && apt-get install -y \
        adduser \
        openssl \
        neovim \
        wget \
        curl \
        vim \
        jq

RUN wget https://artifacts.elastic.co/downloads/kibana/kibana-7.17.12-amd64.deb
RUN apt-get install -y -f ./kibana-7.17.12-amd64.deb
RUN rm kibana-7.17.12-amd64.deb

COPY build/* /kibana/
WORKDIR /kibana

RUN chmod +x *.sh

ENV PATH="/usr/share/kibana/bin:${PATH}"
ENTRYPOINT ["bash"]
CMD ["/kibana/entrypoint.sh"]
