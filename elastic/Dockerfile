FROM ubuntu:24.04

RUN --mount=type=cache,target=/var/cache/apt/archives,sharing=locked \
    apt-get update && apt-get install -y \
        neovim \
        wget \
        curl \
        vim \
        jq
        
RUN wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.12-amd64.deb
RUN apt-get install -y -f ./elasticsearch-7.17.12-amd64.deb
RUN rm elasticsearch-7.17.12-amd64.deb

COPY build/* /elastic/
RUN cp -r /var/lib/elasticsearch /tmp/elasticsearch_data_lib
WORKDIR /elastic

RUN chmod +x *.sh

ENV PATH="/usr/share/elasticsearch/bin:${PATH}"
ENTRYPOINT ["bash"]
CMD ["/elastic/entrypoint.sh"]