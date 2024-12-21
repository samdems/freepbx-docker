# This dockerfile and configuration is derived by
# Jason Martin <jason@greenpx.co.uk>
# Many Thanks to the  author in this place!


FROM debian:12
MAINTAINER Michael Mayer <swd@michael-mayer.biz>


# Set environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV ASTERISKUSER asterisk

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    libnewt-dev \
    libssl-dev \
    libncurses5-dev \
    subversion \
    libsqlite3-dev \
    libjansson-dev \
    libxml2-dev \
    uuid-dev \
    default-libmysqlclient-dev \
    htop \
    sngrep \
    lame \
    ffmpeg \
    mpg123 && \
    apt-get install -y \
    linux-headers-amd64 \
    openssh-server \
    apache2 \
    mariadb-server \
    mariadb-client \
    bison \
    flex \
    php8.2 \
    php8.2-curl \
    php8.2-cli \
    php8.2-common \
    php8.2-mysql \
    php8.2-gd \
    php8.2-mbstring \
    php8.2-intl \
    php8.2-xml \
    php-pear \
    curl \
    sox \
    libncurses5-dev \
    libssl-dev \
    mpg123 \
    libxml2-dev \
    libnewt-dev \
    sqlite3 \
    pkg-config \
    automake \
    libtool \
    autoconf \
    git \
    unixodbc-dev \
    uuid \
    uuid-dev \
    libasound2-dev \
    libogg-dev \
    libvorbis-dev \
    libicu-dev \
    libcurl4-openssl-dev \
    odbc-mariadb \
    libical-dev \
    libneon27-dev \
    libsrtp2-dev \
    libspandsp-dev \
    sudo \
    subversion \
    libtool-bin \
    python-dev-is-python3 \
    unixodbc \
    vim \
    wget \
    libjansson-dev \
    software-properties-common \
    nodejs \
    npm \
    ipset \
    iptables \
    fail2ban \
    unzip \
    libjansson4 \
    asterisk \
    
    php-soap && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* 


RUN mkdir -p /var/run/asterisk \ 
	&& mkdir -p /etc/asterisk \
	&& mkdir -p /var/lib/asterisk \
	&& mkdir -p /var/log/asterisk \
	&& mkdir -p /var/spool/asterisk \
	&& mkdir -p /usr/lib/asterisk \
	&& mkdir -p /var/www/

# Add Asterisk user
RUN useradd -m $ASTERISKUSER \
	&& chown $ASTERISKUSER. /var/run/asterisk \ 
	&& chown -R $ASTERISKUSER. /etc/asterisk \
	&& chown -R $ASTERISKUSER. /var/lib/asterisk \
	&& chown -R $ASTERISKUSER. /var/log/asterisk \
	&& chown -R $ASTERISKUSER. /var/spool/asterisk \
	&& chown -R $ASTERISKUSER. /usr/lib/asterisk \
	&& chown -R $ASTERISKUSER. /var/www/ 
	

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

CMD ["/sbin/my_init"]

# *Loosely* Following steps on FreePBX wiki
# http://wiki.freepbx.org/display/FOP/Installing+FreePBX+13+on+Ubuntu+Server+14.04.2+LTS


# Install Required Dependencies


# Replace default conf files to reduce memory usage
COPY conf/my-small.cnf /etc/mysql/my.cnf
COPY conf/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf

RUN chown -R $ASTERISKUSER. /var/www/* \
	&& rm -rf /var/www/html


# Compile and install pjproject
WORKDIR /usr/src
RUN curl -sf -o pjproject.tar.gz -L https://github.com/pjsip/pjproject/archive/refs/tags/2.15.1.tar.gz \
	&& tar -xzvf pjproject.tar.gz \
	&& rm -f pjproject.tar.gz \
	&& cd pjproject-* \
	&& CFLAGS='-DPJ_HAS_IPV6=1' ./configure --enable-shared --disable-sound --disable-resample --disable-video --disable-opencore-amr \
	&& make dep \
	&& make \ 
	&& make install \
	&& rm -r /usr/src/pjproject-*


WORKDIR /usr/src/asterisk
RUN ./configure 
RUN contrib/scripts/get_mp3_source.sh 
RUN make menuselect.makeopts 

# RUN ./menuselect/menuselect --list-options  
RUN ./menuselect/menuselect --enable=chan_sip --enable=format_mp3 --disable=BUILD_NATIVE
RUN	cat menuselect.makeopts 
RUN make 
RUN make install \
	&& make config \
	&& ldconfig \
	&& update-rc.d -f asterisk remove 

RUN rm -r /usr/src/asterisk

WORKDIR /tmp


# 2nd dependency download (Placing it here avoids recompiling asterisk&co during docker build)
RUN apt-get install -y \
		sudo \
		net-tools \
		coreutils 

# Configure apache
RUN sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php5/apache2/php.ini \
	&& sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf \
	&& sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
	&& sed -i 's/VirtualHost \*:80/VirtualHost \*:8082/' /etc/apache2/sites-available/000-default.conf \
	&& sed -i 's/Listen 80/Listen 8082/' /etc/apache2/ports.conf


# Setup services
COPY start-apache2.sh /etc/service/apache2/run
RUN chmod +x /etc/service/apache2/run

COPY start-mysqld.sh /etc/service/mysqld/run
RUN chmod +x /etc/service/mysqld/run

COPY start-asterisk.sh /etc/service/asterisk/run
RUN chmod +x /etc/service/asterisk/run

COPY start-amportal.sh /etc/my_init.d/start-amportal.sh
	

#Make CDRs work
COPY conf/cdr/odbc.ini /etc/odbc.ini
COPY conf/cdr/odbcinst.ini /etc/odbcinst.ini
COPY conf/cdr/cdr_adaptive_odbc.conf /etc/asterisk/cdr_adaptive_odbc.conf
RUN chown asterisk:asterisk /etc/asterisk/cdr_adaptive_odbc.conf \
	&& chmod 775 /etc/asterisk/cdr_adaptive_odbc.conf

# Download and prepare FreePBX
WORKDIR /usr/src

# Download and unzip 
RUN curl -f -o freepbx.tgz -L http://mirror.freepbx.org/modules/packages/freepbx/freepbx-13.0-latest.tgz 
RUN tar xfz freepbx.tgz
RUN rm -rf freepbx.tgz

# Prepare install
RUN a2enmod rewrite
COPY ./conf/asterisk.conf /etc/asterisk/

# install
COPY install-freepbx.sh /
RUN chmod +x /install-freepbx.sh
RUN /install-freepbx.sh
RUN rm -rf /usr/src/freepbx



RUN apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

VOLUME ["/etc/asterisk","/etc/apache2","/var/www/html","/var/lib/mysql","/var/spool/asterisk","/var/lib/asterisk"]
