FROM gregewing/vdesktop_ubuntu_base:latest
MAINTAINER Greg Ewing (https://github.com/gregewing)
ENV LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive TZ=Europe/London ENABLE_FILEBOT=no ENABLE_SUDO=no ENABLE_SSHD=no ENABLE_VNC=yes ENABLE_NOVNC=no VNC_INITIAL_PASSWORD="" INSTALL_ADDITIONAL_PACKAGES=""
COPY scripts /usr/local/bin
COPY announcement /home/app/Desktop/

RUN echo Starting.\
 && apt-get -q -y update \
 && apt-get -q -y install \ 
                         sudo \
                         xterm \
                         iputils-ping \
                         vlc \
                         mediainfo \
                         libchromaprint-tools \
 && apt-get -q -y full-upgrade \
 && apt-get -q -y autoremove \
 && apt-get -q -y clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 && echo Finished.

VOLUME ["/home/app/.java/.userPrefs/net/filebot"]

