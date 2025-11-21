#FROM ghcr.io/home-assistant/amd64-base-debian:bookworm
# Multistage build
FROM ghcr.io/hassio-addons/debian-base/amd64:9.0.0 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

COPY brhl2240cups_src-2.0.4-2.tar.gz /
COPY cupswrapperHL2240-2.0.4-2.i386.tar.gz /
COPY hl2240lpr-2.1.0-1.i386.tar.gz /

# Repackage LPR drivers
RUN tar -zxvf hl2240lpr-2.1.0-1.i386.tar.gz \
    && dpkg -x hl2240lpr-2.1.0-1.i386.deb hl2240lpr-2.1.0-1.amd64.extracted \
    && dpkg-deb -e hl2240lpr-2.1.0-1.i386.deb hl2240lpr-2.1.0-1.amd64.extracted/DEBIAN \
    && sed -i 's/Architecture: i386/Architecture: amd64/' hl2240lpr-2.1.0-1.amd64.extracted/DEBIAN/control \
    && echo true > hl2240lpr-2.1.0-1.amd64.extracted/usr/local/Brother/Printer/HL2240/inf/braddprinter

RUN cd hl2240lpr-2.1.0-1.amd64.extracted \
    && find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums \
    && cd .. \
    && chmod 755 hl2240lpr-2.1.0-1.amd64.extracted/DEBIAN/p* hl2240lpr-2.1.0-1.amd64.extracted/usr/local/Brother/Printer/HL2240/inf/* hl2240lpr-2.1.0-1.amd64.extracted/usr/local/Brother/Printer/HL2240/lpd/* \
    && dpkg-deb -b hl2240lpr-2.1.0-1.amd64.extracted hl2240lpr-2.1.0-1.amd64.deb

# build cups wrapper
RUN tar -zxvf brhl2240cups_src-2.0.4-2.tar.gz
RUN cd brhl2240cups_src-2.0.4-2 \
    && gcc brcupsconfig3/brcupsconfig.c -o brcupsconfig4 \
    && cd ..

# extract i386 cupswrapper
RUN tar -zxvf cupswrapperHL2240-2.0.4-2.i386.tar.gz \
    && dpkg -x cupswrapperHL2240-2.0.4-2.i386.deb cupswrapperHL2240-2.0.4-2.amd64.extracted \
    && dpkg-deb -e cupswrapperHL2240-2.0.4-2.i386.deb cupswrapperHL2240-2.0.4-2.amd64.extracted/DEBIAN \
    && sed -i 's/Architecture: i386/Architecture: amd64/' cupswrapperHL2240-2.0.4-2.amd64.extracted/DEBIAN/control

# copy build wrapper to extracted deb    
RUN cp brhl2240cups_src-2.0.4-2/brcupsconfig4 cupswrapperHL2240-2.0.4-2.amd64.extracted/usr/local/Brother/Printer/HL2240/cupswrapper

# repack deb
RUN cd cupswrapperHL2240-2.0.4-2.amd64.extracted \
    && find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums \
    && cd .. \
    && chmod 755 cupswrapperHL2240-2.0.4-2.amd64.extracted/DEBIAN/p* cupswrapperHL2240-2.0.4-2.amd64.extracted/usr/local/Brother/Printer/HL2240/cupswrapper/* \
    && dpkg-deb -b cupswrapperHL2240-2.0.4-2.amd64.extracted cupswrapperHL2240-2.0.4-2.amd64.deb

RUN mkdir results \
    && mv cupswrapperHL2240-2.0.4-2.amd64.deb ./results \
    && mv hl2240lpr-2.1.0-1.amd64.deb ./results

# HAOS IMAGE
FROM ghcr.io/hassio-addons/debian-base/amd64:9.0.0 AS image

LABEL io.hass.version="1.5" io.hass.type="addon" io.hass.arch="amd64"

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt update \
    && apt install -y --no-install-recommends \
        sudo \
        locales \
        cups \
        cups-filters \
        avahi-daemon \
        libnss-mdns \
        dbus \
        colord \
        printer-driver-all-enforce \
        # printer-driver-all \
        # printer-driver-splix \
        # printer-driver-brlaser \
        # printer-driver-gutenprint \
        openprinting-ppds \
        # hpijs-ppds \
        # hp-ppd  \
        # hplip \
        # printer-driver-foo2zjs \
        # printer-driver-hpcups \
        # printer-driver-escpr \
        printer-driver-cups-pdf \
        gnupg2 \
        lsb-release \
        nano \
        samba \
        bash-completion \
        procps \
        whois \
    && apt clean -y \
    && rm -rf /var/lib/apt/lists/*

# add HL2240 driver
RUN --mount=type=bind,from=build,source=/results,target=/results \
    apt install /results/hl2240lpr-2.1.0-1.amd64.deb \
    && apt install /results/cupswrapperHL2240-2.0.4-2.amd64.deb \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs /

# Add user and disable sudo password checking
RUN useradd \
  --groups=sudo,lp,lpadmin \
  --create-home \
  --home-dir=/home/print \
  --shell=/bin/bash \
  --password=$(mkpasswd print) \
  print \
&& sed -i '/%sudo[[:space:]]/ s/ALL[[:space:]]*$/NOPASSWD:ALL/' /etc/sudoers

EXPOSE 631

RUN chmod a+x /run.sh

CMD ["/run.sh"]
