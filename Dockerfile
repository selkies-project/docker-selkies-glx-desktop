# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# KDE Plasma desktop container for Selkies on an X.Org server of its own: the
# desktop environment on top of the Selkies base container
# (ghcr.io/selkies-project/selkies/base), with the base's framebuffer server
# replaced by X.Org running on the GPU.
#
# The base is the whole session apart from what it looks like -- display
# servers, audio, GPU wiring, s6, coTURN and Selkies itself. This layer adds
# the desktop, Plasma on X11, the browsers, the proot-apps runner behind the
# dashboards' apps panel, and the one thing the base does not have: an X.Org
# server that owns a GPU (services/xorg), so OpenGL and Vulkan reach
# applications through the vendor's own X driver, with nothing translating in
# between. NVIDIA GPUs take the proprietary driver, whose X server modules are
# staged from the driver installer at first start since the container runtime
# injects none; every GPU with a KMS driver (AMD, Intel) takes the modesetting
# driver over its /dev/dri node. One GPU carries one X server, which is why
# docker-selkies-egl-desktop, the same desktop on the base's own display
# servers, is the image for sharing a GPU between containers or for running
# without one.
#
# X11 only: the base's Wayland backend is not offered here, since the whole
# point of this image is the X server on the GPU.

ARG BASE_IMAGE="ghcr.io/selkies-project/selkies/base:main-ubuntu26.04"
ARG DISTRIB_IMAGE="ubuntu"
ARG DISTRIB_RELEASE="26.04"
# The Selkies revision the shared helper scripts are taken from
ARG SELKIES_REF="main"
# The selkies-bwrap revision Steam's bubblewrap stand-in is installed from
ARG SELKIES_BWRAP_REF="main"

# The X11 window manager, rebuilt from the archive with a patch: stock kwin_x11
# makes one screen per CRTC and spans the displays Selkies publishes as RandR
# monitors over the one CRTC a framebuffer server has, so a maximized window
# would cover both.
FROM ${DISTRIB_IMAGE}:${DISTRIB_RELEASE} AS kwinx11build
ARG DEBIAN_FRONTEND="noninteractive"
RUN printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::Retries::Delay::Maximum "30";\n' \
        > /etc/apt/apt.conf.d/99-selkies-retries
COPY patches/kwin-x11/ /build/patches/
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get clean && apt-get update && \
    apt-get install --no-install-recommends -y \
        ca-certificates \
        dpkg-dev && \
    apt-get build-dep -y kwin-x11 && \
    mkdir -p /build/src && cd /build/src && \
    apt-get source kwin-x11 && \
    cd kwin-x11-*/ && \
    for kwin_patch in /build/patches/*.patch; do patch -p1 < "${kwin_patch}"; done && \
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        dpkg-buildpackage -b -uc -us && \
    mkdir -p /build/debs && \
    mv /build/src/*.deb /build/debs/

FROM ${BASE_IMAGE}

LABEL maintainer="https://github.com/danisla,https://github.com/ehfd"
LABEL org.opencontainers.image.title="Selkies GLX Desktop Container"
LABEL org.opencontainers.image.description="KDE Plasma desktop on the Selkies base container, on an X.Org server that owns the GPU (NVIDIA, AMD or Intel): OpenGL and Vulkan through the vendor's own X driver, s6 service supervision, embedded coTURN. X11 only."
LABEL org.opencontainers.image.source="https://github.com/selkies-project/docker-selkies-glx-desktop"
LABEL org.opencontainers.image.licenses="MPL-2.0"

ARG DEBIAN_FRONTEND="noninteractive"
ARG SELKIES_REF
ARG SELKIES_BWRAP_REF

# The base ships its setuid and setgid files owned by root, and dpkg replaces a
# file by hardlinking the old one aside first -- which the kernel denies uid
# 1000 on a setuid file it does not own. Released for the layers below, an
# archive update to util-linux, shadow, sudo, fuse3 or dbus is just another
# package; without this it fails the layer that takes it. The helper is the
# base's own; a base published before it carried one is given the copy the
# Selkies repository ships.
USER 0
SHELL ["/bin/sh", "-c"]
RUN if ! command -v selkies-privileged-files > /dev/null; then \
        curl -o /usr/local/bin/selkies-privileged-files -fsSL --retry 5 --retry-delay 3 --retry-connrefused --retry-max-time 180 \
            "https://raw.githubusercontent.com/selkies-project/selkies/${SELKIES_REF}/addons/base/selkies-privileged-files" && \
        chown 1000:1000 /usr/local/bin/selkies-privileged-files && chmod 755 /usr/local/bin/selkies-privileged-files; \
    fi && \
    selkies-privileged-files release

# Rootless like the base: layers run as the session user through fakeroot, so
# the package database and apt cache stay owned by that user and in-session
# package management behaves like `/usr/bin/sudo` (the fakeroot alias) does at
# runtime. Real-root operations in the live session use /usr/bin/sudo-root.
USER 1000
SHELL ["/usr/bin/fakeroot", "--", "/bin/sh", "-c"]

COPY --from=kwinx11build --chown=1000:1000 /build/debs /tmp/kwin-x11-debs

# The Plasma X11 session and the X.Org server it draws on. The server itself is
# in the base (xserver-xorg-core, with the modesetting driver built in); what
# X.Org needs beyond it to drive a GPU is the input and video driver metapackages
# its session package pulls, and the modesetting driver needs no vendor
# package. The NVIDIA X driver is not a package on any base: it is staged at
# runtime from the driver installer matching the host (selkies-xorg-config).
# The patched kwin-x11 then replaces the packaged one: the dpkg -i takes only
# the rebuilt debs whose package the install put on the system, in one
# invocation so dpkg orders them itself.
RUN apt-get clean && apt-get update && apt-get install --no-install-recommends -y \
        plasma-desktop \
        plasma-workspace \
        plasma-session-x11 \
        kwin-x11 \
        # Recommends of the packages above that a session is expected to
        # provide: the theme, the GTK bridge, the PolicyKit agent, the portal
        # backend applications open files and share screens through, the
        # tools KDE launches by name, the system monitor the panel reads
        breeze \
        breeze-gtk-theme \
        breeze-icon-theme \
        kde-config-gtk-style \
        polkit-kde-agent-1 \
        xdg-desktop-portal-kde \
        kde-cli-tools \
        kio-extras \
        ksystemstats \
        systemsettings \
        # The applications a desktop is unusable without: file manager,
        # terminal, editor, image viewer, archiver, dialogs for scripts, the
        # volume applet the panel loads and the system monitor it links to
        dolphin \
        konsole \
        kwrite \
        gwenview \
        ark \
        kdialog \
        plasma-pa \
        plasma-systemmonitor \
        # Image formats past what Qt reads on its own (WebP, TIFF, AVIF, HEIF),
        # which a clipboard image or a download arrives as
        kimageformat6-plugins \
        qt6-image-formats-plugins \
        # proot-apps refreshes the icon cache of the theme it installs into by
        # calling gtk-update-icon-cache; without it that refresh is a silent
        # no-op and the cache a session reads predates the application
        gtk-update-icon-cache && \
    debs="" && \
    for deb in /tmp/kwin-x11-debs/*.deb; do \
        if dpkg -s "$(dpkg-deb -f "${deb}" Package)" > /dev/null 2>&1; then \
            debs="${debs} ${deb}"; \
        fi; \
    done && \
    dpkg -i ${debs} && \
    # The device notifier announces every display Selkies creates, including the
    # session's own at startup. Its KDED module ignores an autoload override, and
    # a container has no hardware hotplug for it to report.
    rm -f /usr/lib/*/qt6/plugins/kf6/kded/devicenotifications.so && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# Session defaults in the system scope, so a user's own settings still win:
# no splash on a streamed desktop, no lock screen (a locked container session
# has no local seat to unlock it) and no leave actions (logging out ends the
# session the stream is showing, and shutdown addresses an init this container
# does not run), no compositing (every animation is bandwidth for nothing), and
# no file indexing of a container home.
RUN mkdir -pm755 /etc/xdg && \
    printf '[KSplash]\nEngine=none\n' > /etc/xdg/ksplashrc && \
    printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > /etc/xdg/kscreenlockerrc && \
    printf '[KDE Action Restrictions]\naction/lock_screen=false\naction/switch_user=false\nlogout=false\n\n[General]\nBrowserApplication=firefox.desktop\n' > /etc/xdg/kdeglobals && \
    printf '[Compositing]\nEnabled=false\n' > /etc/xdg/kwinrc && \
    printf '[Basic Settings]\nIndexing-Enabled=false\n' > /etc/xdg/baloofilerc && \
    # Plasma's device notifier and Dolphin's places poll UDisks2, which the
    # session bus cannot activate here (a container mounts nothing) and would
    # otherwise retry, and log, on every query; without the activation file
    # the service is simply absent
    rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service

# The browsers, in one apt operation: Firefox from Mozilla's own APT repository,
# which serves real .deb builds and is pinned over the distribution package, and
# Google Chrome as a downloaded .deb for the H.264/AV1 media stack the
# distribution Chromium builds do not carry. Chrome's own launcher script gains
# two switches, so every way of starting it -- menu entry, xdg-open, a shell --
# carries them: --no-sandbox, because Chrome's sandbox needs CAP_SYS_ADMIN for
# its setuid helper or unprivileged user namespaces for its zygote, and a
# container's default seccomp profile grants neither, so a stock Chrome aborts
# at the zygote (the container is the isolation boundary here); and the basic
# password store, because the container runs no keyring daemon to unlock and
# Chrome otherwise blocks on a prompt nobody can answer. The downloads retry
# every failure and the Chrome one is held to HTTP/1.1, since its server resets
# HTTP/2 streams mid-transfer often enough to fail a build.
RUN mkdir -pm755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d && \
    curl -o /etc/apt/keyrings/packages.mozilla.org.asc -fsSL --retry 5 --retry-all-errors --retry-delay 3 --retry-connrefused --retry-max-time 180 "https://packages.mozilla.org/apt/repo-signing-key.gpg" && \
    printf 'Types: deb\nURIs: https://packages.mozilla.org/apt\nSuites: mozilla\nComponents: main\nSigned-By: /etc/apt/keyrings/packages.mozilla.org.asc\n' > /etc/apt/sources.list.d/mozilla.sources && \
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla && \
    curl -o /tmp/google-chrome-stable.deb -fsSL --http1.1 --retry 5 --retry-all-errors --retry-delay 3 --retry-connrefused --retry-max-time 180 "https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb" && \
    apt-get clean && apt-get update && \
    apt-get install --no-install-recommends -y firefox /tmp/google-chrome-stable.deb && \
    sed -i 's|^exec -a "$0" "$HERE/chrome" "$@"$|exec -a "$0" "$HERE/chrome" --no-sandbox --password-store=basic "$@"|' /opt/google/chrome/google-chrome && \
    grep -q -- '--no-sandbox --password-store=basic "$@"' /opt/google/chrome/google-chrome && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# proot-apps (https://github.com/linuxserver/proot-apps) backs the dashboards'
# apps panel: portable per-user applications in a proot, installed and removed
# through the selkies-proot wrapper without touching the image. The release
# tarball is staged here and linked into each user's ~/.local/bin, because
# proot-apps runs its tools from there by absolute path. proot traces every
# process it starts, so a second copy carries CAP_SYS_PTRACE for the hosts that
# restrict ptrace; it is kept apart because a file capability the container's
# bounding set does not hold stops that binary from execing at all, and the
# wrapper picks whichever of the two runs. The wrapper is the one the Selkies
# desktop container ships, taken from the same revision as the base.
RUN mkdir -pm755 /opt/proot-apps && \
    PAPPS_RELEASE="$(curl -fsSL --retry 5 --retry-delay 3 --retry-connrefused --retry-max-time 180 -o /dev/null -w '%{url_effective}' "https://github.com/linuxserver/proot-apps/releases/latest" | sed 's|.*/||')" && \
    curl -fsSL --retry 5 --retry-delay 3 --retry-connrefused --retry-max-time 180 "https://github.com/linuxserver/proot-apps/releases/download/${PAPPS_RELEASE}/proot-apps-$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/').tar.gz" \
        | tar -xzf - -C /opt/proot-apps/ && \
    printf '%s\n' "${PAPPS_RELEASE}" > /opt/proot-apps/pversion && \
    if ! command -v setcap > /dev/null; then \
        apt-get update && apt-get install --no-install-recommends -y libcap2-bin && \
        apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*; \
    fi && \
    mkdir -pm755 /opt/proot-apps-cap && \
    cp /opt/proot-apps/proot /opt/proot-apps-cap/proot && \
    setcap cap_sys_ptrace+ep /opt/proot-apps-cap/proot && \
    curl -o /usr/local/bin/selkies-proot -fsSL --retry 5 --retry-delay 3 --retry-connrefused --retry-max-time 180 \
        "https://raw.githubusercontent.com/selkies-project/selkies/${SELKIES_REF}/addons/desktop/selkies-proot" && \
    chmod -f 755 /usr/local/bin/selkies-proot

# Steam, and the games it launches, in a container without user namespaces.
# The client runs its browser helper, its compatibility tools and every game
# through pressure-vessel, which builds a container with bubblewrap; bubblewrap
# needs a user namespace or CAP_SYS_ADMIN and a container's seccomp profile
# grants neither, so a stock Steam stops at its own requirements check with
# "Steam now requires user namespaces to be enabled". selkies-bwrap takes the
# place pressure-vessel reads from $BWRAP when its own bubblewrap fails and
# builds those containers through fakechroot, or the proot above where the
# fakechroot library is missing. The Steam Linux Runtime is used exactly as
# Valve ships it, so native Linux games get the libraries they were built
# against and Proton runs through the runtime it asks for. The installer brings
# Steam itself, the 32-bit libraries its client and games need, and the wiring
# into Steam's own launcher, so every way of starting it carries the stand-in.
# The Steam client is x86 only and is left out of every other architecture.
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        curl -o /tmp/selkies-bwrap-install.sh -fsSL --retry 5 --retry-all-errors --retry-delay 3 --retry-connrefused --retry-max-time 180 \
            "https://raw.githubusercontent.com/selkies-project/selkies-bwrap/${SELKIES_BWRAP_REF}/install.sh" && \
        sh /tmp/selkies-bwrap-install.sh; \
    fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# The X server's configuration tool and the session's own s6 services. The
# xorg service replaces the base's framebuffer server outright, and the
# Wayland backend's session compositor service goes with it: this image is
# X11 only, and a service left in place would start a compositor nothing in
# this image runs a session on.
COPY --chown=1000:1000 selkies-xorg-config /usr/local/bin/selkies-xorg-config
COPY --chown=1000:1000 services/ /etc/service/
RUN chmod -f 755 /usr/local/bin/selkies-xorg-config && \
    install -m 755 /etc/service/xvfb/run /usr/local/bin/selkies-xvfb-server && \
    rm -rf /etc/service/xvfb /etc/service/wayland && \
    find /etc/service \( -name run -o -name finish \) -exec chmod -f 755 {} +

RUN printf "==============================================\n=         Selkies GLX Desktop Container      =\n==============================================\n" > /etc/motd

USER 0
# Real root for the same reason the base needs it: under the fakeroot SHELL an
# ownership change lands only in fakeroot's database, leaving a setuid bit on a
# file owned by uid 1000, which the kernel refuses to honour. The PolicyKit
# agent helper and pkexec need theirs to authenticate at all, and a terminal's
# utempter its setgid to record sessions. `restore` covers everything released
# above, which is the base's own set rather than these.
SHELL ["/bin/sh", "-c"]
RUN selkies-privileged-files restore && \
    for helper in /usr/lib/polkit-1/polkit-agent-helper-1 /usr/libexec/polkit-agent-helper-1 /usr/bin/pkexec; do \
        if [ -e "$helper" ]; then chown -f root:root "$helper" && chmod -f 4755 "$helper" || echo "Failed to restore setuid for $helper"; fi; \
    done && \
    for helper in /usr/lib/*/utempter/utempter /usr/libexec/utempter/utempter; do \
        if [ -e "$helper" ]; then chown -f root:utmp "$helper" && chmod -f 2755 "$helper" || echo "Failed to restore setgid for $helper"; fi; \
    done

USER 1000

# The dashboards' apps panel drives proot-apps through the command channel;
# without this the server tells clients the panel is unusable and they drop it.
# Commands run as the session user, whom the streamed desktop already hands a
# terminal, so the desktop image enables the channel; disable with
# -e SELKIES_COMMAND_ENABLED=false.
ENV SELKIES_COMMAND_ENABLED="true"
# Start the Plasma session; false runs the X server with kwin alone, no shell
ENV START_PLASMA="true"
# Plasma's menu definitions carry its prefix; the base defaults to lxqt-
ENV XDG_MENU_PREFIX="plasma-"
# OpenGL reaches applications through the X server's own GLX vendor here,
# the NVIDIA driver included; the base routes NVIDIA GL through Zink only
# because its framebuffer server has no GPU GLX to offer.
ENV DISABLE_ZINK="true"
# The X server's initial mode: the size, refresh rate and depth the GPU is
# configured with before the client's own size takes over (dynamic resizing is
# on by default). VIDEO_PORT names the video port the NVIDIA driver reports a
# monitor on, so RandR has an output to hang modes on and a monitor plugged
# there shows the desktop; `none` leaves the server without RandR outputs.
ENV DISPLAY_SIZEW="1920"
ENV DISPLAY_SIZEH="1080"
ENV DISPLAY_REFRESH="60"
ENV DISPLAY_CDEPTH="24"
ENV VIDEO_PORT="DFP"
