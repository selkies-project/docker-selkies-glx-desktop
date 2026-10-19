# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# KDE Plasma desktop container for Selkies on an X.Org server of its own: the
# desktop environment on top of the Selkies base container
# (ghcr.io/selkies-project/selkies/base), with the base's framebuffer server
# replaced by X.Org running on the GPU.
#
# The base is the whole session apart from what it looks like -- display
# servers, audio, GPU wiring, s6, coTURN, and Selkies itself. This layer adds
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

ARG BASE_IMAGE="ghcr.io/selkies-project/selkies/base:latest-ubuntu26.04"
ARG DISTRIB_IMAGE="ubuntu"
ARG DISTRIB_RELEASE="26.04"
# The Selkies revision the shared helper scripts are taken from
ARG SELKIES_REF="main"
# The proot-next revision Steam's installer is taken from; it installs the latest
# proot-next release as Steam's bubblewrap stand-in
ARG PROOT_NEXT_REF="main"

# The X11 window manager, rebuilt from the archive with a patch: stock kwin_x11
# makes one screen per CRTC and spans the displays Selkies publishes as RandR
# monitors over the one CRTC a framebuffer server has, so a maximized window
# would cover both.
FROM ${DISTRIB_IMAGE}:${DISTRIB_RELEASE} AS kwinx11build
ARG DEBIAN_FRONTEND="noninteractive"
# The archive's kwin-x11 source version, which CI reads before the build: a new one
# rebuilds this stage where a build cache would hand back the last one's packages
ARG KWIN_X11_VERSION=""
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
    echo "kwin-x11 ${KWIN_X11_VERSION:-as the archive serves}" && \
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
LABEL org.opencontainers.image.description="KDE Plasma desktop on the Selkies base container, on an X.Org server that owns the GPU (NVIDIA, AMD, or Intel): OpenGL and Vulkan through the vendor's own X driver, s6 service supervision, embedded coTURN. X11 only."
LABEL org.opencontainers.image.source="https://github.com/selkies-project/docker-selkies-glx-desktop"
LABEL org.opencontainers.image.licenses="MPL-2.0"

ARG DEBIAN_FRONTEND="noninteractive"
ARG SELKIES_REF
ARG PROOT_NEXT_REF

# The base ships its setuid and setgid files owned by root, and dpkg replaces a
# file by hardlinking the old one aside first -- which the kernel denies uid
# 1000 on a setuid file it does not own. Released for the layers below, an
# archive update to util-linux, shadow, sudo, fuse3, or dbus is just another
# package; without this it fails the layer that takes it. The helper is the
# base's own; a base published before it carried one is given the copy the
# Selkies repository ships. Every download below is checked against the hash its
# source publishes for it (fetch-verified, with the build's token as the secret
# github_token where one is given).
USER 0
SHELL ["/bin/sh", "-c"]
COPY --chmod=755 fetch-verified /usr/local/bin/fetch-verified
RUN --mount=type=secret,id=github_token if ! command -v selkies-privileged-files > /dev/null; then \
        fetch-verified file selkies-project/selkies "${SELKIES_REF}" \
            addons/base/selkies-privileged-files /usr/local/bin/selkies-privileged-files && \
        chown 1000:1000 /usr/local/bin/selkies-privileged-files && chmod 755 /usr/local/bin/selkies-privileged-files; \
    fi && \
    selkies-privileged-files release && \
    # ucf and ucfr through fakeroot, which a base from before selkies' ucf-fakeroot lacks:
    # under it they install none of the configuration files they manage, LibreOffice's
    # registry among them, and LibreOffice aborts at start
    if [ ! -e /usr/local/bin/ucf-fakeroot ]; then \
        fetch-verified file selkies-project/selkies "${SELKIES_REF}" \
            addons/base/ucf-fakeroot /usr/local/bin/ucf-fakeroot && \
        chown 1000:1000 /usr/local/bin/ucf-fakeroot && chmod 755 /usr/local/bin/ucf-fakeroot && \
        for tool in ucf ucfr; do \
            dpkg-divert --quiet --local --rename --add "/usr/bin/${tool}" && \
            ln -snf /usr/local/bin/ucf-fakeroot "/usr/bin/${tool}" || exit 1; \
        done && \
        chown -h 1000:1000 /usr/bin/ucf /usr/bin/ucfr /var/lib/dpkg/diversions*; \
    fi

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
        # volume applet the panel loads, and the system monitor it links to
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

# Session defaults in the system scope, so a user's own settings still win: no
# splash on a streamed desktop, no lock screen (a locked container session has
# no local seat to unlock it), no leave actions (logging out ends the session
# the stream is showing, and shutdown addresses an init this container does not
# run), no compositing (every animation is bandwidth for nothing), no file
# indexing of a container home, and Firefox as the web browser: kdeglobals names
# it to KDE, and the MIME defaults name it to everything that resolves one from
# them (the task manager's browser launcher, xdg-open), where Chrome's hidden
# alias entry would otherwise win by sorting first.
RUN mkdir -pm755 /etc/xdg && \
    printf '[KSplash]\nEngine=none\n' > /etc/xdg/ksplashrc && \
    printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > /etc/xdg/kscreenlockerrc && \
    printf '[KDE Action Restrictions]\naction/lock_screen=false\naction/switch_user=false\nlogout=false\n\n[General]\nBrowserApplication=firefox.desktop\n' > /etc/xdg/kdeglobals && \
    printf '[Default Applications]\ntext/html=firefox.desktop\nx-scheme-handler/http=firefox.desktop\nx-scheme-handler/https=firefox.desktop\n' > /etc/xdg/mimeapps.list && \
    printf '[Compositing]\nEnabled=false\n' > /etc/xdg/kwinrc && \
    printf '[Basic Settings]\nIndexing-Enabled=false\n' > /etc/xdg/baloofilerc && \
    # Plasma's device notifier and Dolphin's places poll UDisks2, which the
    # system bus cannot activate here (a container mounts nothing); without
    # the activation file the service is simply absent, and Solid is told
    # not to ask for it (SOLID_DISABLE_UDISKS2 below)
    rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service

# The browsers, in one apt operation: Firefox from Mozilla's own APT repository,
# which serves real .deb builds and is pinned over the distribution package, and
# Google Chrome as a downloaded .deb for the H.264/AV1 media stack the
# distribution Chromium builds do not carry. Chrome's own launcher script gains
# two switches, so every way of starting it -- menu entry, xdg-open, a shell --
# carries them. --no-sandbox where the container denies Chrome's sandbox, which
# needs CAP_SYS_ADMIN for its setuid helper or unprivileged user namespaces for
# its zygote: a container's default seccomp profile grants neither, and a stock
# Chrome aborts at the zygote (the container is the isolation boundary there).
# The launcher asks for the namespaces the zygote creates at every start and
# keeps the sandbox wherever they are granted, as under an unconfined seccomp
# profile. And the basic password store, because the container runs no keyring
# daemon to unlock and Chrome otherwise blocks on a prompt nobody can answer.
# Both come from their vendors' apt repositories, whose packages apt checks
# against the signing key each names; the keys are checked against the
# fingerprints Mozilla and Google publish. Chrome's package rewrites
# google-chrome.sources to trust a key it carries itself, and writes one on a
# first install; the entry here is named apart from it and the package's
# defaults file keeps it from writing its own.
RUN mkdir -pm755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d && \
    fetch-verified key "https://packages.mozilla.org/apt/repo-signing-key.gpg" \
        35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3 /etc/apt/keyrings/packages.mozilla.org.asc && \
    printf 'Types: deb\nURIs: https://packages.mozilla.org/apt\nSuites: mozilla\nComponents: main\nSigned-By: /etc/apt/keyrings/packages.mozilla.org.asc\n' > /etc/apt/sources.list.d/mozilla.sources && \
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla && \
    fetch-verified key "https://dl.google.com/linux/linux_signing_key.pub" \
        EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 /etc/apt/keyrings/google-chrome.asc && \
    printf 'Types: deb\nURIs: https://dl.google.com/linux/chrome/deb/\nSuites: stable\nComponents: main\nSigned-By: /etc/apt/keyrings/google-chrome.asc\n' > /etc/apt/sources.list.d/google-linux.sources && \
    printf 'repo_add_once="false"\nrepo_reenable_on_distupgrade="false"\n' > /etc/default/google-chrome && \
    apt-get clean && apt-get update && \
    apt-get install --no-install-recommends -y firefox google-chrome-stable && \
    sed -i 's#^exec -a "$0" "$HERE/chrome" "$@"$#exec -a "$0" "$HERE/chrome" $(unshare --user --map-root-user --pid --net --fork true 2> /dev/null || echo --no-sandbox) --password-store=basic "$@"#' /opt/google/chrome/google-chrome && \
    grep -q -- '|| echo --no-sandbox) --password-store=basic "$@"' /opt/google/chrome/google-chrome && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# proot-apps (https://github.com/linuxserver/proot-apps) backs the dashboards'
# apps panel: portable per-user applications in a proot, installed and removed
# through the selkies-proot wrapper without touching the image. The release
# tarball is staged here and linked into each user's ~/.local/bin, because
# proot-apps runs its tools from there by absolute path. proot traces every
# process it starts, so a second copy carries CAP_SYS_PTRACE for the hosts that
# restrict ptrace (set below as real root); it is kept apart because a file
# capability the container's bounding set does not hold stops that binary from
# execing at all, and the wrapper picks whichever of the two runs. The wrapper
# is the one the Selkies desktop container ships, taken from the same revision
# as the base. The token is mounted for uid 1000, which these layers run as.
RUN --mount=type=secret,id=github_token,uid=1000 mkdir -pm755 /opt/proot-apps && \
    PAPPS_RELEASE="$(fetch-verified release linuxserver/proot-apps latest \
        "proot-apps-$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/').tar.gz" /tmp/proot-apps.tar.gz)" && \
    tar -xzf /tmp/proot-apps.tar.gz -C /opt/proot-apps/ && rm -f /tmp/proot-apps.tar.gz && \
    printf '%s\n' "${PAPPS_RELEASE}" > /opt/proot-apps/pversion && \
    if ! command -v setcap > /dev/null; then \
        apt-get update && apt-get install --no-install-recommends -y libcap2-bin && \
        apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*; \
    fi && \
    mkdir -pm755 /opt/proot-apps-cap && \
    cp /opt/proot-apps/proot /opt/proot-apps-cap/proot && \
    fetch-verified file selkies-project/selkies "${SELKIES_REF}" addons/desktop/selkies-proot /usr/local/bin/selkies-proot && \
    chmod -f 755 /usr/local/bin/selkies-proot

# Steam, and the games it launches, in a container without user namespaces.
# The client runs its browser helper, its compatibility tools, and every game
# through pressure-vessel, which builds a container with bubblewrap; bubblewrap
# needs a user namespace or CAP_SYS_ADMIN and a container's seccomp profile
# grants neither, so a stock Steam stops at its own requirements check with
# "Steam now requires user namespaces to be enabled". proot-next, under the
# bwrap name, takes the place pressure-vessel reads from $BWRAP when its own
# bubblewrap fails, and builds those containers by path translation without a
# namespace, the client's browser helper included. The Steam Linux
# Runtime is used exactly as Valve ships it, so native Linux games get the
# libraries they were built against and Proton runs through the runtime it asks
# for. The installer brings Steam itself, the 32-bit libraries its client and
# games need, and the wiring into Steam's own launcher, so every way of
# starting it carries the stand-in. The Steam client is x86 only and is left
# out of every other architecture.
RUN --mount=type=secret,id=github_token,uid=1000 if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        fetch-verified file selkies-project/proot-next "${PROOT_NEXT_REF}" install-steam.sh /tmp/install-steam.sh && \
        sh /tmp/install-steam.sh; \
    fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# Wine, for the Windows applications that are not games and the games that
# Steam does not manage. WineHQ's own repository rather than the distribution
# package, because Wine moves fast and the staging branch is what the
# compatibility reports assume; the repository publishes per Ubuntu codename,
# so the codename is read from the image rather than pinned. Wine is x86 and
# needs the 32-bit runtime for anything older than 64-bit Windows, so this is
# amd64 only. WineHQ's key is checked against its fingerprint, and the entry
# is written here as WineHQ publishes it for the codename. Winetricks comes
# from its own repository, where it is released continuously and the packaged
# copy is always behind: its newest commit, each file checked against the hash
# GitHub names for it there.
RUN --mount=type=secret,id=github_token,uid=1000 if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        dpkg --add-architecture i386 && \
        mkdir -pm755 /etc/apt/keyrings && \
        fetch-verified key "https://dl.winehq.org/wine-builds/winehq.key" \
            D43F640145369C51D786DDEA76F1A20FF987672F /etc/apt/keyrings/winehq-archive.asc && \
        codename="$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"')" && \
        printf 'Types: deb\nURIs: https://dl.winehq.org/wine-builds/ubuntu\nSuites: %s\nComponents: main\nArchitectures: amd64 i386\nSigned-By: /etc/apt/keyrings/winehq-archive.asc\n' \
            "${codename}" > "/etc/apt/sources.list.d/winehq-${codename}.sources" && \
        apt-get clean && apt-get update && \
        apt-get install --install-recommends -y winehq-staging && \
        fetch-verified file Winetricks/winetricks master src/winetricks /usr/bin/winetricks \
            src/winetricks.bash-completion /usr/share/bash-completion/completions/winetricks && \
        chmod -f 755 /usr/bin/winetricks; \
    fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# The launchers that stand beside Steam: Lutris for its own runners and Wine,
# Heroic for the Epic and GOG libraries. Neither is in the archive, so the
# newest release is read from GitHub at build time and checked against the
# digest GitHub records for it. x86 only, as Steam and Wine are; Heroic
# publishes no Linux package for another architecture.
RUN --mount=type=secret,id=github_token,uid=1000 if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        fetch-verified release lutris/lutris latest 'lutris_{version}_all.deb' /tmp/lutris.deb && \
        fetch-verified release Heroic-Games-Launcher/HeroicGamesLauncher latest \
            "Heroic-{version}-linux-$(dpkg --print-architecture).deb" /tmp/heroic.deb && \
        apt-get clean && apt-get update && \
        apt-get install --no-install-recommends -y /tmp/lutris.deb /tmp/heroic.deb && \
        rm -f /tmp/lutris.deb /tmp/heroic.deb && \
        # Electron's sandbox wants what Chrome's does, so the menu entry and the
        # name a shell resolves both start it through a wrapper that asks for
        # the same namespaces and passes --no-sandbox where they are denied
        sed -i 's|^Exec=/opt/Heroic/heroic|Exec=/usr/local/bin/heroic|' /usr/share/applications/heroic.desktop && \
        grep -q '^Exec=/usr/local/bin/heroic' /usr/share/applications/heroic.desktop && \
        printf '#!/bin/sh\nexec /opt/Heroic/heroic $(unshare --user --map-root-user --pid --net --fork true 2> /dev/null || echo --no-sandbox) "$@"\n' > /usr/local/bin/heroic && \
        chmod -f 755 /usr/local/bin/heroic; \
    fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# Lutris installs into the games directory, which is on no default PATH.
ENV PATH="${PATH}:/usr/local/games:/usr/games"

# The rest of a desktop: a media player that plays what the browsers will not,
# the KDE applications a Plasma session is expected to come with, and the
# command-line tools a session with a terminal is unusable without. Only the
# Qt6 builds are taken; the Plasma 5 leftovers in the archive would drag a
# second toolkit in for one application each.
RUN apt-get clean && apt-get update && apt-get install --no-install-recommends -y \
        # Media playback; the extra codecs it falls back to are in the base
        vlc \
        vlc-plugin-access-extra \
        vlc-plugin-notify \
        vlc-plugin-samba \
        vlc-plugin-skins2 \
        vlc-plugin-video-splitter \
        vlc-plugin-visualization \
        # Documents and viewers
        libreoffice \
        libreoffice-kf6 \
        libreoffice-plasma \
        libreoffice-style-breeze \
        okular \
        okular-extra-backends \
        # The KDE utilities, and the Plasma add-ons a panel and desktop expect
        kde-baseapps \
        kdeadmin \
        kcalc \
        kcharselect \
        kde-spectacle \
        kdeconnect \
        kfind \
        kget \
        kmag \
        kmouth \
        kmousetool \
        ktimer \
        kdf \
        filelight \
        sweeper \
        kinfocenter \
        kmenuedit \
        dolphin-plugins \
        kdegraphics-thumbnailers \
        kwin-addons \
        plasma-browser-integration \
        plasma-calendar-addons \
        plasma-dataengines-addons \
        plasma-runners-addons \
        plasma-widgets-addons \
        transmission-qt \
        # Discover pulls PackageKit and AppStream in itself
        plasma-discover \
        # The terminal Steam's launcher falls back to, and the Ubuntu-only
        # tools for the archives and drivers this image is built on. The rest
        # of what a shell session wants is in the base, which is not a desktop
        xterm \
        software-properties-common \
        software-properties-qt \
        ubuntu-drivers-common && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# The X.Org drivers for the GPUs this image can be given beyond the ones the
# server has built in: the vendor DDX modules for AMD, NVIDIA's open driver, and
# the rest, the QXL driver for a virtual machine's display, the Wacom input
# driver, and the legacy Intel DDX for hardware older than the modesetting
# driver serves well. None of them is chosen by autoconfiguration here, because
# selkies-xorg-config writes a Device section naming the driver and the GPU's
# bus address; the Intel one in particular loads only if that file is replaced,
# which is the one case it exists for.
RUN apt-get clean && apt-get update && apt-get install --no-install-recommends -y \
        xserver-xorg-video-all \
        xserver-xorg-video-qxl \
        xserver-xorg-input-wacom && \
    # Intel integrated graphics are x86, and so is their driver
    if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        apt-get install --no-install-recommends -y xserver-xorg-video-intel; \
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
# above, which is the base's own set rather than these. A file capability set
# under fakeroot is lost the same way, so the apps panel's ptrace-capable proot
# gets its CAP_SYS_PTRACE here.
SHELL ["/bin/sh", "-c"]
RUN chown -R root:root /opt/proot-apps-cap && setcap cap_sys_ptrace+ep /opt/proot-apps-cap/proot && \
    selkies-privileged-files restore && \
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
# Solid's UDisks2 backend would ask for the absent service at every device
# query and log the refusal each time, so it is left out.
ENV SOLID_DISABLE_UDISKS2="1"
# OpenGL reaches applications through the X server's own GLX vendor here,
# the NVIDIA driver included; the base routes NVIDIA GL through Zink only
# because its framebuffer server has no GPU GLX to offer.
ENV DISABLE_ZINK="true"
# The X server's initial mode: the size and refresh rate the GPU is configured
# with before the client's own size takes over (dynamic resizing is on by
# default). VIDEO_PORT names the video port the NVIDIA driver reports a monitor
# on, so RandR has an output to hang modes on and a monitor plugged there shows
# the desktop; `none` leaves the server without RandR outputs.
ENV DISPLAY_SIZEW="1920"
ENV DISPLAY_SIZEH="1080"
ENV DISPLAY_REFRESH="60"
ENV VIDEO_PORT="DFP"
