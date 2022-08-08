#!/bin/bash

cat <<EOF
Welcome to the gregewing/UBUNTU container
EOF

# only on container boot
INITIALIZED="/.initialized"
if [ ! -f "$INITIALIZED" ]; then
  touch "$INITIALIZED"

  echo ">> adding desktop files"

  if echo "$VNC_SCREEN_RESOLUTION" | grep 'x' 2>/dev/null >/dev/null; then
echo ">> set default resolution to: $VNC_SCREEN_RESOLUTION"
cat <<EOF > /home/app/.config/autostart/autostart_custom_resolution.desktop
[Desktop Entry]
Type=Application
Icon=application-x-executable
Name=Custom Resolution
GenericName=Custom Resolution 
Exec=/bin/bash -c "xrandr --output VNC-0 --mode $VNC_SCREEN_RESOLUTION"
EOF
  fi

if [ -f "/home/app/Desktop/announcement.txt" ]; then
cat <<EOF > /home/app/.config/autostart/announcement.desktop
#!/usr/bin/env xdg-open
[Desktop Entry]
Type=Application
Terminal=false
Exec=gedit /home/app/Desktop/announcement.txt
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enables=true
Name=Announcement
EOF
fi

cat <<EOF > /home/app/.config/autostart/plank.desktop
[Desktop Entry]
Type=Application
Exec=plank
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enables=true
Name=Plank
EOF

cat <<EOF > /home/app/.config/autostart/autostart_custom_settings.desktop
[Desktop Entry]
Type=Application
Icon=application-x-executable
Name=Custom Settings
GenericName=Custom Settings
Exec=gconf-settings.sh
EOF

  chown app:app /home/app/.config/autostart/*.desktop
  chmod +x      /home/app/.config/autostart/*.desktop

  echo ">> import proxy settings if set"
  if [ ! -z ${HTTP_PROXY+x} ]; then
    echo "HTTP_PROXY=$HTTP_PROXY" >> /etc/environment
    echo "http_proxy=$HTTP_PROXY" >> /etc/environment
  fi

  if [ ! -z ${HTTPS_PROXY+x} ]; then
    echo "HTTPS_PROXY=$HTTPS_PROXY" >> /etc/environment
    echo "https_proxy=$HTTPS_PROXY" >> /etc/environment
  fi

  if [ ! -z ${FTP_PROXY+x} ]; then
    echo "FTP_PROXY=$FTP_PROXY" >> /etc/environment
    echo "ftp_proxy=$FTP_PROXY" >> /etc/environment
  fi

  if [ ! -z ${NO_PROXY+x} ]; then
    echo "NO_PROXY=$NO_PROXY" >> /etc/environment
    echo "no_proxy=$NO_PROXY" >> /etc/environment
  fi

  if [ ! -z ${APT_PROXY+x} ]; then
    echo "Acquire::http::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf.d/99custom_proxy
  fi

  #Optionally install/remove filebot based on ENV variable.
  if [ -z ${ENABLE_FILEBOT+x} ]; then
    if [ "yes" = "${ENABLE_FILEBOT,,}" ]; then
        mkdir -p /opt/jdk
        tar -C /opt/jdk -zxvf /usr/local/bin/jdk-8u241-linux-x64.tar.gz
        update-alternatives --install /usr/bin/java java /opt/jdk/jdk1.8.0_241/bin/java 100
        dpkg -i /usr/local/bin/filebot_4.7.9_amd64.deb
    fi
  fi

  #Optionally install additional tools based on ENV variables.
  if [ ! -z ${INSTALL_ADDITIONAL_PACKAGES+x} ]; then
    if [ ! -z "$INSTALL_ADDITIONAL_PACKAGES" ]; then
      echo "  >> Installing additional packages :  $INSTALL_ADDITIONAL_PACKAGES"
      su -l -s /bin/sh -c "apt-get update"
      su -l -s /bin/sh -c "apt-get install -y $INSTALL_ADDITIONAL_PACKAGES "
      su -l -s /bin/sh -c "apt-get -y autoremove"
    fi
  fi

  if [ ! -f "/config/ssl-cert.crt" ] || [ ! -f "/config/ssl-cert.key" ]; then
    echo ">> generating self signed cert"
    mkdir -p /config
    openssl req -x509 \
    -newkey "rsa:4086" \
    -days 3650 \
    -subj "/C=XX/ST=XXXX/L=XXXX/O=XXXX/CN=127.0.0.1" \
    -out "/config/ssl-cert.crt" \
    -keyout "/config/ssl-cert.key" \
    -nodes \
    -sha256
  fi


  ###
  # RUNIT
  ###

  echo ">> RUNIT - create services"
  mkdir -p /etc/sv/rsyslog /etc/sv/sshd /etc/sv/tigervnc
  mkdir -p /etc/sv/novnc /etc/sv/novnc-ssl
  echo -e '#!/bin/sh\nexec /usr/sbin/rsyslogd -n' > /etc/sv/rsyslog/run
  echo -e '#!/bin/sh\nrm /var/run/rsyslogd.pid' > /etc/sv/rsyslog/finish
  echo -e "#!/bin/sh\nexec /usr/sbin/sshd -D" > /etc/sv/sshd/run
  echo -e "#!/bin/sh\nexec /usr/share/novnc/utils/launch.sh --listen 80 --vnc localhost:5901" > /etc/sv/novnc/run
  echo -e "#!/bin/sh\nexec /usr/share/novnc/utils/launch.sh --listen 443 --ssl-only --cert /config/ssl-cert.crt  --vnc localhost:5901" > /etc/sv/novnc-ssl/run



  echo ">> RUNIT - enable services"
  echo "  >> enabling rsyslog"
  ln -s /etc/sv/rsyslog /etc/service/rsyslog

  if [ ! -z ${ENABLE_VNC+x} ]; then
    if [ "yes" = "${ENABLE_VNC,,}" ]; then

       #Chose which vnc settings to user based on presence of VNC_INITIAL_PASSWORD environment variable.
       if [ ! -z ${VNC_INITIAL_PASSWORD+x} ]; then
         if [ -z "$VNC_INITIAL_PASSWORD" ]; then
           # Running in insecure mode
           # Set up the VNC Server configuration
           echo "  >> enabling vnc (no password)"
           echo -e "#!/bin/sh\nrm -rif /tmp/.X1*\nexec /bin/su -s /bin/sh -c \"vncserver :1 -SecurityTypes none -depth 24 -fg -localhost no --I-KNOW-THIS-IS-INSECURE\" app" > /etc/sv/tigervnc/run
         else
           # Running in SECURE mode
           # Set the vnc password (if provided in ENV variable - which is why we are here in this part of the conditional.
           myuser="app"
           mypasswd=$VNC_INITIAL_PASSWORD
           mkdir /home/$myuser/.vnc
           echo $mypasswd | vncpasswd -f > /home/$myuser/.vnc/passwd
           chown -R $myuser:$myuser /home/$myuser/.vnc
           chmod 0600 /home/$myuser/.vnc/passwd
           # Set up the VNC Server configuration
           echo "  >> enabling vnc (with password)"
           echo -e "#!/bin/sh\nrm -rif /tmp/.X1*\nexec /bin/su -s /bin/sh -c \"vncserver :1 -depth 24 -fg -localhost no -SecurityTypes VncAuth,TLSVnc -passwd /home/app/.vnc/passwd\" app" > /etc/sv/tigervnc/run
         fi
         ln -s /etc/sv/tigervnc /etc/service/tigervnc
       fi

       # Check if NoVNC has been requested in the ENVs.
       if [ ! -z ${ENABLE_NOVNC+x} ]; then
         if [ "yes" = "${ENABLE_NOVNC,,}" ]; then
           echo "  >> enabling novnc"
           ln -s /etc/sv/novnc           /etc/service/novnc
           ln -s /etc/sv/novnc-ssl       /etc/service/novnc-ssnl
         else
           echo "  >> disabling novnc"
           # do nothing
         fi
       fi


    else
      # vnc not desired, remove runit service files
      echo "  >> disabling vnc"
      rm -rf /etc/service/tigervnc /etc/sv/tigervnc
      # with vnc switched off, theres no point having NoVNC either. Disable it now.
      echo "  >> disabling novnc"
      rm -rf /etc/service/novnc* /etc/sv/novnc*
    fi
  fi


  #Optionally enable the 'app' user for all admin functions in the sudoers file
  if [ ! -z ${ENABLE_SUDO+x} ]; then
    if [ "yes" = "${ENABLE_SUDO,,}" ]; then
      echo "  >> enabling sudo for user 'app'"
      echo "app ALL = NOPASSWD: ALL" >> /etc/sudoers
    else
      echo "  >> disabling sudo for user 'app'"
    fi
  fi


  if [ ! -z ${ENABLE_SSHD+x} ]; then
    if [ "yes" = "${ENABLE_SSHD,,}" ]; then
      echo "  >> enabling sshd"
      ln -s /etc/sv/sshd /etc/service/sshd
    else
      echo "  >> disabling sshd"
    fi
  fi
fi

chmod a+x /etc/sv/*/run /etc/sv/*/finish
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo ">> starting services"
exec runsvdir -P /etc/service

