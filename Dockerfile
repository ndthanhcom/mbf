FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    openssl \
    rsync

WORKDIR /opt/mbf
COPY . /opt/mbf

RUN chmod +x /opt/mbf/bin/mbf /opt/mbf/framework.sh

ENV MBF_HOME=/opt/mbf \
    MBF_NO_UPDATE_CHECK=1 \
    PATH="/opt/mbf/bin:${PATH}"

ENTRYPOINT ["mbf"]
CMD ["--help"]
