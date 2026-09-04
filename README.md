# docker-selkies-glx-desktop

KDE Plasma desktop container for [Selkies](https://github.com/selkies-project/selkies) on an X.Org server of its own, built on the [Selkies base container](https://github.com/selkies-project/selkies/tree/main/addons/base): a complete remote desktop streamed over WebSockets or WebRTC to a browser, with the GPU driving the whole X server. OpenGL and Vulkan reach applications through the vendor's own X driver, with nothing translating in between: the proprietary NVIDIA driver, or the modesetting driver on any GPU with a kernel KMS driver (AMD, Intel). The X server is the container's own, so no `/tmp/.X11-unix` host socket or host X configuration is involved, and one GPU carries one container.

Use [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop) for the same desktop on the base's own display servers, reaching the GPU through EGL without an X.Org server: it shares one GPU between many containers, runs without a GPU at all, and offers the Wayland backend.

[![Build](https://github.com/selkies-project/docker-selkies-glx-desktop/actions/workflows/container-publish.yml/badge.svg)](https://github.com/selkies-project/docker-selkies-glx-desktop/actions/workflows/container-publish.yml)

[![Discord](https://img.shields.io/badge/dynamic/json?logo=discord&label=Discord%20Members&query=approximate_member_count&url=https%3A%2F%2Fdiscordapp.com%2Fapi%2Finvites%2FwDNGDeSW5F%3Fwith_counts%3Dtrue)](https://discord.gg/wDNGDeSW5F)

**Please read [Troubleshooting](#troubleshooting) first, then use [Discord](https://discord.gg/wDNGDeSW5F) or [GitHub Discussions](https://github.com/selkies-project/docker-selkies-glx-desktop/discussions) for support questions. Please only use [Issues](https://github.com/selkies-project/docker-selkies-glx-desktop/issues) for technical inquiries or bug reports.**

## What is in the image

The [Selkies base container](https://github.com/selkies-project/selkies/blob/main/docs/component.md#desktop-container) supplies everything but the desktop and the X server: PipeWire audio, the GPU runtime wiring for NVIDIA, VA-API and Vulkan, the gamepad and webcam plumbing, [s6](https://skarnet.org/software/s6/) service supervision, an embedded [coTURN](https://github.com/coturn/coturn) server for the WebRTC transport, and Selkies itself. This image replaces the base's framebuffer server with an X.Org server on the GPU (the `xorg` service, configured at start by `selkies-xorg-config` for the GPU the session was given), and adds KDE Plasma on X11 (`plasma-desktop` with Dolphin, Konsole, KWrite, Gwenview, Ark and System Settings), Firefox and Google Chrome, and the [proot-apps](https://github.com/linuxserver/proot-apps) runner behind the dashboard's apps panel, which installs portable applications into the home directory without touching the image.

The NVIDIA X server modules (`nvidia_drv.so` and the GLX server module) are shipped only inside NVIDIA's driver installer, and the container toolkit injects the driver's libraries but not those, so the first start on an NVIDIA GPU downloads the installer matching the host driver version and lifts the two modules out of it; a container that keeps its filesystem keeps them across restarts. `NVIDIA_DRIVER_VERSION` overrides the version to fetch when the host's cannot be read.

This image is X11 only; the base's Wayland backend is not offered here. Container tags are `26.04` for the current Ubuntu 26.04 build, `latest` for the same, and persistent tags of the form `26.04-20260101010101` for a specific build.

## Usage

### Running with Docker

**1. Run the container with Docker or Podman.**

With an NVIDIA GPU (the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) is required):

```bash
docker run --name xgl -it -d --gpus 1 --runtime nvidia --shm-size=2g -e TZ=UTC -e PASSWD=mypasswd -e VIDEO_PORT=DFP -p 8080:8080 ghcr.io/selkies-project/selkies-glx-desktop:26.04
```

With an AMD or Intel GPU, pass the DRM devices in instead. The session user inside the container (uid 1000) must be able to open them, which `--group-add` covers when the host's `render` and `video` groups own the nodes, and no X server or compositor on the host may be driving that GPU:

```bash
docker run --name xgl -it -d --device=/dev/dri:rwm --group-add="$(getent group render | cut -d: -f3)" --group-add="$(getent group video | cut -d: -f3)" --shm-size=2g -e TZ=UTC -e PASSWD=mypasswd -p 8080:8080 ghcr.io/selkies-project/selkies-glx-desktop:26.04
```

**Alternatively, use Docker Compose by editing [`docker-compose.yml`](docker-compose.yml):**

```bash
# Start the container from the path containing docker-compose.yml
docker compose up -d
# Stop the container
docker compose down
```

`--shm-size=2g` matters because the browsers inside the desktop crash on Docker's 64 MB default. Replace `mypasswd` with your own password. The container must NOT be run in privileged mode. The first start on an NVIDIA GPU takes a minute longer while the driver installer is fetched.

**2. Connect to the web server on port 8080 with a browser.** You may also put a reverse proxy in front of it for external connectivity.

The container serves HTTPS by default on a certificate it mints per install, so the browser warns once until you trust it or name a real certificate with `-e SELKIES_HTTPS_CERT=` and `-e SELKIES_HTTPS_KEY=`; `-e SELKIES_ENABLE_HTTPS=false` serves plain HTTP for a deployment that terminates TLS in front of the container.

The login is `ubuntu` with the password from `PASSWD` (which is also the container's Linux user password) unless `SELKIES_BASIC_AUTH_USER` and `SELKIES_BASIC_AUTH_PASSWORD` name another one.

**3. If the desktop loads but does not stream, or streams very slowly, read [WebRTC and Firewall Issues](#webrtc-and-firewall-issues).** The default WebSocket transport needs nothing but the web port. The WebRTC transport (`-e SELKIES_MODE=webrtc`) needs a TURN server or host networking, because you are self-hosting WebRTC.

### Running with Kubernetes

**1. Create the Kubernetes `Secret` with your password (change keys and values as adequate):**

```bash
kubectl create secret generic my-pass --from-literal=my-pass=YOUR_PASSWORD
```

> NOTE: Replace `YOUR_PASSWORD` with your desired password, and change the name `my-pass` to your preferred name of the Kubernetes secret with the `xgl.yml` file changed accordingly as well. It is possible to skip this step and provide the password with `value:` in `xgl.yml`, but this exposes the password in plain text.

**2. Create the pod after editing [`xgl.yml`](xgl.yml) to your needs; explanations are in the file:**

```bash
kubectl create -f xgl.yml
```

The file requests an NVIDIA GPU through the NVIDIA device plugin. AMD and Intel GPUs are requested through their own device plugins (`amd.com/gpu`, `gpu.intel.com/i915`) in the same `resources:` section; the node must not run an X server or compositor on that GPU.

**3. Connect to the web server on port 8080** through the ingress or reverse proxy your cluster provides. The login is the same as with Docker.

**4. If the desktop loads but does not stream, read [WebRTC and Firewall Issues](#webrtc-and-firewall-issues).**


### Running with Apptainer

On a cluster without Docker, the image runs under Apptainer as an ordinary user, pulled straight from the registry, and its X.Org server runs on the GPU without root. Besides what the [Selkies documentation](https://selkies-project.github.io/selkies/start/#apptainer) explains for every image (a display number and a port no other session on the node uses, a private `/tmp`, a home directory of your own, `--writable-tmpfs`, `--nv`), this image needs the host driver's two X server modules bound to the paths the server loads them from, because Apptainer's `--nv` carries the driver's libraries but not its X modules; the version in the file names is the host driver's:

```bash
#!/bin/bash
N=$((RANDOM % 900 + 100))
PORT=$((RANDOM % 10000 + 20000))
mkdir -p "$HOME/selkies/home" "$HOME/selkies/tmp"
X=/usr/lib/xorg/modules
V=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
apptainer run --nv --writable-tmpfs --contain --cleanenv \
    --home "$HOME/selkies/home:/home/ubuntu" -B "$HOME/selkies/tmp:/tmp" -B /dev/dri \
    -B "$X/drivers/nvidia_drv.so:$X/drivers/nvidia_drv.so" \
    -B "$X/extensions/libglxserver_nvidia.so.$V:$X/extensions/libglxserver_nvidia.so.$V" \
    --env "DISPLAY=:$N,SELKIES_PORT=$PORT,PASSWD=mypasswd" \
    docker://ghcr.io/selkies-project/selkies-glx-desktop:26.04
```

Reach it with `ssh -L 8080:<node>:$PORT <login-node>` and open `https://localhost:8080`. Where the host keeps the modules elsewhere, `find / -name nvidia_drv.so` finds them; a module bound under its plain name (`libglxserver_nvidia.so`) is accepted too. Without the binds the image fetches the modules from the driver installer matching the host on every start, which needs the node to reach NVIDIA's download server; `--nvccli` binds no X modules either.

## Configuration

Everything Selkies reads is an environment variable named in [`docs/settings.md`](https://github.com/selkies-project/selkies/blob/main/docs/settings.md) (`selkies --help` inside the container lists the same). The ones this image adds or that matter most:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PASSWD` | `mypasswd` | Password of the container's Linux user, and of the web login unless `SELKIES_BASIC_AUTH_PASSWORD` is set |
| `TZ` | `UTC` | Time zone |
| `DISPLAY_SIZEW`, `DISPLAY_SIZEH`, `DISPLAY_REFRESH`, `DISPLAY_CDEPTH` | `1920`, `1080`, `60`, `24` | The X server's initial mode, replaced by the client's size once it connects (dynamic resizing is on by default) |
| `VIDEO_PORT` | `DFP` | NVIDIA GPUs: the video port the driver reports a monitor on (`DFP`, a `DP-*` port, or `none` to leave the server without RandR outputs, which hands the session to the framebuffer server); a monitor plugged into that port shows the desktop |
| `NVIDIA_DRIVER_VERSION` | (the host's) | The driver installer to take the X server modules from, when the host's version cannot be read |
| `SELKIES_MODE` | `websockets` | Transport: `websockets` or `webrtc`; both can be switched from the web interface |
| `SELKIES_ENCODER` | `h264enc` | Video encoder: `h264enc` (hardware NVENC or VA-API when the GPU has it, x264 otherwise), `h264enc-striped`, or `jpeg` |
| `SELKIES_VIDEO_BITRATE`, `SELKIES_FRAMERATE`, `SELKIES_AUDIO_BITRATE` | `8000`, `60`, `128000` | Initial stream parameters, adjustable from the web interface |
| `SELKIES_ENABLE_HTTPS` | `true` | Serve TLS; `SELKIES_HTTPS_CERT` and `SELKIES_HTTPS_KEY` name a real certificate |
| `SELKIES_ENABLE_BASIC_AUTH` | `true` | The web login, `ubuntu` and `PASSWD` unless `SELKIES_BASIC_AUTH_USER` and `SELKIES_BASIC_AUTH_PASSWORD` are set |
| `SELKIES_SCALING_DPI` | `96` | The desktop's DPI, also adjustable from the web interface |
| `SELKIES_AUTO_GPU`, `SELKIES_RENDER_DRI` | `true`, (empty) | Which GPU the X server and the session run on when the container was given several: the auto-selection pick, or a render node named outright |
| `SELKIES_COMMAND_ENABLED` | `true` | The command channel behind the dashboard's apps panel; `false` disables it |
| `START_PLASMA` | `true` | `false` runs the X server with kwin alone, no Plasma shell: a single application started from the apps panel or an attached shell is managed, resized and maximized without a desktop around it |

The `SELKIES_TURN_*` variables configure the WebRTC transport, and `DISABLE_ZINK` is preset here: OpenGL goes through the X server's own GLX vendor, the NVIDIA driver included, rather than through Zink.

### The X server

`selkies-xorg-config` writes `/etc/X11/xorg.conf` at every start for the GPU the base container resolved for the session (the `SELKIES_AUTO_GPU` pick, or `SELKIES_RENDER_DRI`), read back from its render node; an NVIDIA GPU exposed without a DRM node is found through the driver's own `/proc` tree. NVIDIA GPUs take the `nvidia` driver with the video port from `VIDEO_PORT` reported connected, so RandR has an output to hang the client's sizes on and a monitor plugged into that port shows the desktop; every other GPU takes the `modesetting` driver over its `/dev/dri` node, and the configured mode is attached to the first output the server lists, connected or not. The server runs as the session user, sharing a virtual terminal it never switches to; the log is at `/tmp/runtime-ubuntu/Xorg.log` inside the container.

On X11 the Plasma shell lays its panels and wallpaper out for the DPI it started at and follows a later change only in part, so the image replaces the shell when the dashboard's UI scaling changes: the desktop lays out afresh at the new size within a few seconds, and open windows stay where they are. A second display is opened from the dashboard in a second browser window: each display is a RandR monitor on the X server's one output. The Plasma shell lays its panels and desktop out per monitor, and the image's `kwin_x11` is rebuilt to take its screens from those monitors too (`patches/kwin-x11/`): a stock kwin_x11 reads them from RandR CRTCs, of which that output has one, and would span both displays with a maximized window. A server without RandR outputs at all is a desktop with no screen: the toolkits take their screens from the outputs, so the Plasma shell places no panel and the session is a black stream. The NVIDIA driver reports no display device on a board that has no display engine, the datacenter GPUs, and `VIDEO_PORT=none` asks for the same thing; either way the service says so and runs the base container's framebuffer server in place of this one, which serves the same session on an output of its own. OpenGL then goes through the software stack, as in the EGL image, while Vulkan and the encoders still reach the GPU. Where the GPU can drive a display, the native server keeps the desktop.

### Apps panel

The dashboard's apps panel installs applications from the [proot-apps](https://github.com/linuxserver/proot-apps) catalogue into the home directory. They persist with the home directory (mount a volume at `/home/ubuntu` to keep them) and never touch the image. `sudo apt-get install` works inside the session as well, through fakeroot, for packages the image should carry; `sudo-root` is the real thing, for device nodes and permissions only.

## WebRTC and Firewall Issues

This section applies only to the WebRTC transport (`SELKIES_MODE=webrtc`, or switching to it in the web interface); the default WebSocket transport needs only the web port.

Self-hosted WebRTC needs a [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) when the client and the container cannot reach each other directly, which is the case behind most NATs and firewalls, and always inside Docker's network isolation. Choose one of the following.

- **Internal TURN server:** the container runs its own coTURN when it has no external one. Publish its ports with `-p 3478:3478 -p 3478:3478/udp -p 65532-65535:65532-65535 -p 65532-65535:65532-65535/udp` (or uncomment them in `docker-compose.yml` / `xgl.yml`) and set `-e TURN_MIN_PORT=65532 -e TURN_MAX_PORT=65535` to that range, which must contain at least two ports no other process uses. Set `-e SELKIES_TURN_HOST=` to the address clients reach the container on when it is not the public one, and `-e SELKIES_TURN_PROTOCOL=tcp` when UDP cannot be used, at the cost of latency.

- **Host networking:** `--network=host` (or `network_mode: 'host'` / `hostNetwork: true`) with UDP and TCP ports 49152–65535 open in the host's firewall usually just works. Display `:20` must then be free on the host, and a second container needs its own `-e DISPLAY=:22 -e SELKIES_PORT=8082`; the cluster may not allow it.

- **External TURN server:** set `SELKIES_TURN_HOST` and `SELKIES_TURN_PORT`, then either `SELKIES_TURN_SHARED_SECRET` (time-limited shared secret authentication) or both `SELKIES_TURN_USERNAME` and `SELKIES_TURN_PASSWORD` (long-term credentials), never both methods at once. `SELKIES_TURN_PROTOCOL=tcp` when UDP is blocked; `SELKIES_TURN_TLS=true` when the TURN server has a valid certificate. A [TURN REST API](https://github.com/selkies-project/selkies/blob/main/docs/component.md#turn-rest) is named with `SELKIES_TURN_REST_URI` alone. The Selkies [firewall documentation](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md) covers deploying one; with Kubernetes, keep the credentials in a `Secret` the way `xgl.yml` shows.

## Troubleshooting

### The container does not work with an NVIDIA GPU.

<details markdown>
  <summary>Open Answer</summary>

Check that the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) is configured on the host and the container was started with `--gpus`, that the host driver is not the `nvidia-headless` variant (it lacks the graphics libraries), and that `NVIDIA_DRIVER_CAPABILITIES` inside the container is `all` or includes `graphics` (OpenGL, Vulkan), `video` (NVENC), `display` (the X driver's modesetting device, and Vulkan) and `compute`. An X server needs to be the GPU's only display server: on a GPU that also drives the host's own session, the driver refuses the container's server its modesetting permission, and the container then runs the session on the base's framebuffer server and says so in its log; the EGL image renders on such a GPU through its render node, with the desktop on either of its backends. The container's log shows the X server configuration it wrote and, if the server did not come up, the errors from its log; `docker exec xgl cat /tmp/runtime-ubuntu/Xorg.log` reads the rest. The first start needs to download the driver installer matching the host driver, so it needs network access to NVIDIA's download servers; `NVIDIA_DRIVER_VERSION` names the version when the host's cannot be read.

</details>

### The container does not work with an AMD or Intel GPU.

<details markdown>
  <summary>Open Answer</summary>

The container needs `/dev/dri` (`--device=/dev/dri:rwm`) and the session user must be able to open the nodes: add the host's `render` and `video` groups with `--group-add`, or as a last resort `sudo chmod -R 777 /dev/dri` on the host. An X server needs to be the GPU's only display server: a desktop or another X server on the host driving the same GPU keeps this one from taking it, and the container then runs the session on the framebuffer server and says so in its log. GPUs without a display engine (datacenter accelerators) have no output to light and belong on [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop).

</details>

### The container does not work with a resolution above 2560 x 1600, or with a laptop or hybrid GPU.

<details markdown>
  <summary>Open Answer</summary>

On consumer and professional NVIDIA GPUs, set `VIDEO_PORT` to an empty `DP-*` port (`xrandr -q` inside the session lists them and their connection states) rather than the default `DFP`; the ports should only carry a monitor if you want the desktop shown on it. Datacenter (Tesla) GPUs keep `DFP`, and answer resolutions up to around 2560 x 1600 at 60 Hz. `VIDEO_PORT=none` starts the server with no RandR outputs, which loses dynamic resizing and second displays. Laptops and other hybrid GPU systems may need substantial X server configuration of their own and are not supported here; [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop) works out of the box on them.

</details>

### I want to share one GPU with multiple containers, or run without a GPU.

**Use [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop).** An X server owns its GPU, so two of them cannot share one, and this image has no framebuffer fallback.

### The container does not work when a desktop or X server runs on the host.

<details markdown>
  <summary>Open Answer</summary>

Keep the GPU the host's X server drives away from the container. With NVIDIA GPUs, generate the host's `/etc/X11/xorg.conf` with `nvidia-xconfig --no-probe-all-gpus --busid=$BUS_ID --only-one-x-screen` for the host's own GPU, add the snippet below to it (the container's configuration already carries it), and give the container the other GPUs with `docker --gpus '"device=1,2"'` (note that `--gpus 1` means any single GPU, not device ID 1). The `BUS_ID` is `PCI:bus:device:function` in decimal, from the hexadecimal `nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader` address.

```
Section "ServerFlags"
    Option "AutoAddGPU" "False"
EndSection
```

</details>

### The browser inside the desktop, or another application, crashes at once.

<details markdown>
  <summary>Open Answer</summary>

Give the container more shared memory: `--shm-size=2g`, or the `/dev/shm` memory-backed `emptyDir` `xgl.yml` mounts. Applications that bring their own sandbox (Chrome, Electron, AppImages) cannot set it up inside a container, which grants neither the capabilities Chrome's setuid helper needs nor unprivileged user namespaces: the container is the isolation boundary instead. Chrome's launcher in this image therefore carries `--no-sandbox`, Electron applications need the same switch, and AppImages are extracted rather than FUSE-mounted (`APPIMAGE_EXTRACT_AND_RUN` is set). Do not use `systemd`, Flatpak or Snap inside the container; they need privileges a container should not have.

</details>

### Vulkan does not work.

<details markdown>
  <summary>Open Answer</summary>

Make sure `NVIDIA_DRIVER_CAPABILITIES` is `all`, or includes both `graphics` and `display`; `vulkaninfo --summary` inside the session shows which driver answers.

</details>

### I want to customize this container.

Build on it the way [`docs/development.md`](https://github.com/selkies-project/selkies/blob/main/docs/development.md#container-customization) describes: use this image as the base and replace or add s6 service files under `/etc/service/`. Every service here is one `run` script: `xorg` (the X server, configured by `selkies-xorg-config`), `plasma` (the session), `dbus-session` (the session bus), and the base's own.

## Building

```bash
docker build -t selkies-glx-desktop --build-arg BASE_IMAGE=ghcr.io/selkies-project/selkies/base:main-ubuntu26.04 .
```

`BASE_IMAGE` is any Ubuntu 26.04 Selkies base container, by tag or digest; `SELKIES_REF` names the Selkies revision the shared helper scripts are taken from (`main`).

---
This project has been developed and is supported in part by the National Research Platform (NRP) and the Cognitive Hardware and Software Ecosystem Community Infrastructure (CHASE-CI) at the University of California, San Diego, by funding from the National Science Foundation (NSF), with awards #1730158, #1540112, #1541349, #1826967, #2138811, #2112167, #2100237, and #2120019, as well as additional funding from community partners, infrastructure utilization from the Open Science Grid Consortium, supported by the National Science Foundation (NSF) awards #1836650 and #2030508, and infrastructure utilization from the Chameleon testbed, supported by the National Science Foundation (NSF) awards #1419152, #1743354, and #2027170. This project has also been funded by the Seok-San Yonsei Medical Scientist Training Program (MSTP) Song Yong-Sang Scholarship, College of Medicine, Yonsei University, the MD-PhD/Medical Scientist Training Program (MSTP) through the Korea Health Industry Development Institute (KHIDI), funded by the Ministry of Health & Welfare, Republic of Korea, and the Student Research Bursary of Song-dang Institute for Cancer Research, College of Medicine, Yonsei University.

<sub><sup>\* Funding agencies including, but not limited to the National Science Foundation, remain neutral with regard to jurisdictional claims in published articles and software code of this Code Repository. In the context including, but not limited to this Code Repository, as well as in the context including, but not limited to any and all derivative works based on this Code Repository, all trademarks, trade names, logos, patents, or any and all other forms of external intellectual property, that are mentioned or used, unless otherwise stated, are the property of their respective owners, including but not limited to, The Linux Foundation®, Linus Torvalds, The Apache Software Foundation, Canonical Ltd., Google LLC, Alphabet Inc., NumFOCUS Foundation, Anaconda Inc., conda-forge, Project Jupyter, Coder Technologies, Inc., Docker®, Inc., SchedMD LLC, NVIDIA Corporation, Intel Corporation, Advanced Micro Devices, Inc., Valve Corporation, Epic Games, Inc., Unity Software Inc., Cendio AB, RealVNC® Limited, Amazon.com, Inc., Amazon Web Services, Inc., or its affiliates including but not limited to NICE s.r.l. or NICE USA LLC, Microsoft Corporation, Cloudflare, Inc., Oracle Corporation, StarNet Communications Corporation, TeamViewer SE, Fabrice Bellard, Moonlight Project, and LizardByte. Every best effort has been undertaken to properly identify and attribute trademarks, trade names, logos, patents, or any and all other forms of external intellectual property to their respective owners, unless otherwise stated, wherever possible and practical. The inclusion of such trademarks, trade names, logos, patents, or any and all other forms of external intellectual property in association with this project, unless otherwise stated, serves solely for the purpose of description and must never be construed as an indication of affiliation, competition, endorsement, or a challenge to any and all legal standings of the trademarks, trade names, logos, patents, or any and all other forms of external intellectual property. All project contributors, maintainers, owners, or organizations agree to not willfully breach or infringe legal regulations, in any and all global law, regarding trademarks, trade names, logos, patents, or any and all other forms of external intellectual property. Therefore, all project contributors, maintainers, owners, or organizations, are immune to, and are not to be in any and all cases held legally liable for, any and all jurisdictional claims on trademarks, trade names, logos, patents, or any and all other forms of external intellectual property. No component of this Code Repository is an official product of Google LLC or Alphabet Inc.</sup></sub>
