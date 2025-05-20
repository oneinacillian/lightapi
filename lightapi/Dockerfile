FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install MySQL and other dependencies
RUN apt-get update && apt-get install -y \
    git \
    make \
    cpanminus \
    gcc \
    g++ \
    mariadb-server \
    mariadb-client \
    libmysqlclient-dev \
    libdbi-perl \
    libjson-xs-perl \
    libjson-perl \
    libdatetime-format-iso8601-perl \
    libdatetime-perl \
    curl \
    netcat \
    procps

# Configure MySQL to listen on all interfaces
RUN sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

# Install Perl dependencies
RUN cpanm --notest DBD::MariaDB \
    Starman \
    Net::WebSocket::Server \
    Crypt::Digest::RIPEMD160 \
    DateTime::Format::ISO8601

# Install Node.js
RUN curl -sL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Clone and setup LightAPI
RUN git clone https://github.com/cc32d9/eosio_light_api.git /opt/eosio_light_api

# Create necessary directories
RUN mkdir -p /etc/default /var/log/lightapi /var/run/lightapi /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld

# Install Node.js dependencies
WORKDIR /opt/eosio_light_api/wsapi
RUN npm install

# Create a patch file
COPY ./wsapi_patch.js /tmp/
RUN cat /tmp/wsapi_patch.js >> /opt/eosio_light_api/wsapi/lightapi_wsapi.js

# Setup database and tables
WORKDIR /opt/eosio_light_api
COPY ./setup-db.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3306 5101 5102 5103 5104 5105 8100

ENTRYPOINT ["/docker-entrypoint.sh"]