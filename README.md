# docker-selkies-glx-desktop

KDE Plasma Desktop container designed for Kubernetes, supporting OpenGL EGL and GLX, Vulkan, and Wine/Proton for NVIDIA GPUs through WebRTC and HTML5, providing an open-source remote cloud/HPC graphics or game streaming platform. Spawns its own fully isolated X.Org X11 Server instead of using the host X Server, not requiring `/tmp/.X11-unix` host sockets or host configuration.

Use [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop) for a KDE Plasma Desktop container which directly accesses NVIDIA (and unofficially Intel and AMD) GPUs without using an X.Org X11 Server, supports sharing one GPU with many containers, supports [Apptainer](https://github.com/apptainer/apptainer)/[Singularity](https://github.com/sylabs/singularity), and automatically falling back to software acceleration in the absence of GPUs (but with lower graphics performance).

[![Build](https://github.com/selkies-project/docker-selkies-glx-desktop/actions/workflows/container-publish.yml/badge.svg)](https://github.com/selkies-project/docker-selkies-glx-desktop/actions/workflows/container-publish.yml)

[![Discord](https://img.shields.io/badge/dynamic/json?logo=discord&label=Discord%20Members&query=approximate_member_count&url=https%3A%2F%2Fdiscordapp.com%2Fapi%2Finvites%2FwDNGDeSW5F%3Fwith_counts%3Dtrue)](https://discord.gg/wDNGDeSW5F)

**Please read [Troubleshooting](#troubleshooting) first, then use [Discord](https://discord.gg/wDNGDeSW5F) or [GitHub Discussions](https://github.com/selkies-project/docker-selkies-glx-desktop/discussions) for support questions. Please only use [Issues](https://github.com/selkies-project/docker-selkies-glx-desktop/issues) for technical inquiries or bug reports.**

## Usage

Container startup may take some time at first launch as it could automatically install NVIDIA driver libraries compatible with the host.

For Windows applications or games, Wine, Winetricks, Lutris, Heroic Launcher, PlayOnLinux, and q4wine are bundled by default. Comment out the section where it is installed within `Dockerfile` if the user wants containers without Wine.

The container requires host NVIDIA GPU driver versions of at least **450.80.02** and preferably **470.42.01** (the latest minor version in each major version), with the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) to be also configured on the host for allocating GPUs. The latest minor versions (`xx` in `000.xx.00`) are strongly encouraged. All Maxwell or later generation GPUs in the consumer, professional, or datacenter lineups should not have significant issues running this container, although the Selkies high-performance NVENC backend may not be available. Kepler GPUs are untested and likely does not support the NVENC backend, but can be mostly functional using fallback software acceleration.

The high-performance NVENC backend for the Selkies WebRTC interface is only supported in GPUs listed as supporting `H.264 (AVCHD)` under the `NVENC - Encoding` section of NVIDIA's [Video Encode and Decode GPU Support Matrix](https://developer.nvidia.com/video-encode-and-decode-gpu-support-matrix-new). If your GPU is not listed as supporting `H.264 (AVCHD)`, add the [environment variable `SELKIES_ENCODER`](https://github.com/selkies-project/selkies/blob/main/docs/component.md#encoders) to values including `x264enc`, `vp8enc`, or `vp9enc` in your container configuration for falling back to software acceleration, which also has a very good performance depending on your CPU.

There are two web interfaces that may be chosen in this container, the first being the default [Selkies](https://github.com/selkies-project/selkies) WebRTC HTML5 web interface (requires a TURN server or host networking for best performance), and the second being the fallback [KasmVNC](https://github.com/kasmtech/KasmVNC) WebSocket HTML5 web interface. While the KasmVNC interface does not support audio forwarding, it can be useful for troubleshooting the Selkies WebRTC interface or using this container in constrained environments.

The KasmVNC interface can be enabled in place of Selkies by setting `KASMVNC_ENABLE` to `true`. `KASMVNC_THREADS` sets the number of threads KasmVNC should use for frame encoding, defaulting to all threads if not set. When using the KasmVNC interface, environment variables `SELKIES_ENABLE_BASIC_AUTH`, `SELKIES_BASIC_AUTH_USER`, `SELKIES_BASIC_AUTH_PASSWORD`, `SELKIES_ENABLE_RESIZE`, `SELKIES_ENABLE_HTTPS`, `SELKIES_HTTPS_CERT`, `SELKIES_HTTPS_KEY`, `SELKIES_PORT`, `NGINX_PORT`, and `TURN_EXTERNAL_IP`, used with Selkies, are also inherited. As with the Selkies WebRTC interface, the KasmVNC interface username and password will also be set to the environment variables `SELKIES_BASIC_AUTH_USER` and `SELKIES_BASIC_AUTH_PASSWORD`, also using `ubuntu` and the environment variable `PASSWD` by default if not set.

### Running with Docker

**1. Run the container with Docker, Podman, or other NVIDIA-supported container runtimes ([NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) required):**

```bash
docker run --name xgl -it -d --gpus 1 --runtime nvidia --tmpfs /dev/shm:rw -e TZ=UTC -e DISPLAY_SIZEW=1920 -e DISPLAY_SIZEH=1080 -e DISPLAY_REFRESH=60 -e DISPLAY_DPI=96 -e DISPLAY_CDEPTH=24 -e PASSWD=mypasswd -e SELKIES_ENCODER=nvh264enc -e SELKIES_VIDEO_BITRATE=8000 -e SELKIES_FRAMERATE=60 -e SELKIES_AUDIO_BITRATE=128000 -e SELKIES_BASIC_AUTH_PASSWORD=mypasswd -p 8080:8080 ghcr.io/selkies-project/nvidia-glx-desktop:latest
```

**Alternatively, use Docker Compose by editing the [`docker-compose.yml`](docker-compose.yml) file:**

```bash
# Start the container from the path containing docker-compose.yml
docker compose up -d
# Stop the container
docker compose down
```

**If the Selkies WebRTC HTML5 interface does not connect or is extremely slow, read Step 3 and the [WebRTC and Firewall Issues](#webrtc-and-firewall-issues) section very carefully.**

> NOTE: The container tags available are `latest` and `24.04` for Ubuntu 24.04, `22.04` for Ubuntu 22.04, and `20.04` for Ubuntu 20.04. [Persistent container tags](https://github.com/selkies-project/docker-selkies-glx-desktop/pkgs/container/nvidia-glx-desktop) are available in the form `24.04-20210101010101`. Replace all instances of `mypasswd` with your desired password. `SELKIES_BASIC_AUTH_PASSWORD` will default to `PASSWD` if unspecified. The container must NOT be run in privileged mode.

Change `SELKIES_ENCODER` to `x264enc`, `vp8enc`, or `vp9enc` when using the Selkies interface if your GPU does not support `H.264 (AVCHD)` under the `NVENC - Encoding` section in NVIDIA's [Video Encode and Decode GPU Support Matrix](https://developer.nvidia.com/video-encode-and-decode-gpu-support-matrix-new).

**2. Connect to the web server with a browser on port 8080. You may also separately configure a reverse proxy to this port for external connectivity.**

The default username is `ubuntu` for both the web authentication prompt and the container Linux username. The environment variable `PASSWD` (defaulting to `mypasswd`) is the password for the container Linux user account, and `SELKIES_BASIC_AUTH_PASSWORD` is the password for the HTML5 interface authentication prompt. If `SELKIES_ENABLE_BASIC_AUTH` is set to `true` for Selkies but `SELKIES_BASIC_AUTH_PASSWORD` is unspecified, the HTML5 interface password will default to `PASSWD`.

> NOTE: Only one web browser can be connected at a time with the Selkies WebRTC interface. If the signaling connection works, but the WebRTC connection fails, read Step 3 and the [WebRTC and Firewall Issues](#webrtc-and-firewall-issues) section.

Additional configurations and environment variables for the Selkies WebRTC HTML5 interface are listed in lines that start with `parser.add_argument` within the [Selkies Main Script](https://github.com/selkies-project/selkies/blob/master/src/selkies_gstreamer/__main__.py) or `selkies-gstreamer --help`.

**3. (Not Applicable for KasmVNC) Read carefully if the Selkies WebRTC HTML5 interface does not connect or is extremely slow.**

A [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) is required because you are self-hosting WebRTC, unlike commercial services using WebRTC.

Choose whether to use host networking, an internal [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server), or an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server).

- **Internal TURN Server:**

<details markdown>
  <summary>Open Section</summary>

There is an internal [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) inside the container that may be used when an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) or host networking is not available.

Add environment variables `-e SELKIES_TURN_PROTOCOL=udp -e SELKIES_TURN_PORT=3478 -e TURN_MIN_PORT=65532 -e TURN_MAX_PORT=65535` (change the ports accordingly) with the `docker run` command (or uncomment the relevant [`docker-compose.yml`](docker-compose.yml) sections), where the `SELKIES_TURN_PORT` should not be used by any other host process or container, and the `TURN_MIN_PORT`/`TURN_MAX_PORT` port range has to contain at least two ports also not used by any other host process or container.

Then, open the ports with the `docker run` arguments `-p 8080:8080 -p 3478:3478 -p 3478:3478/udp -p 65532-65535:65532-65535 -p 65532-65535:65532-65535/udp` (or uncomment the relevant [`docker-compose.yml`](docker-compose.yml) sections) in addition to the web server port.

If UDP cannot be used, at the cost of higher latency and lower performance, omit the ports containing `/udp` and use the environment variable `-e SELKIES_TURN_PROTOCOL=tcp`.

All these ports must be exposed to the internet if you need access over the internet. If you need use TURN within a local network, add `-e SELKIES_TURN_HOST={YOUR_INTERNAL_IP}` with `{YOUR_INTERNAL_IP}` to the internal hostname or IP of the local network. IPv6 addresses must be enclosed with square brackets such as `[::1]`.

</details>

- **Host Networking:**

<details markdown>
  <summary>Open Section</summary>

The Selkies WebRTC HTML5 interface will likely just start working if you open UDP and TCP ports 49152–65535 in your host server network and add `--network=host` to the above `docker run` command, or `network_mode: 'host'` in `docker-compose.yml`. Note that running multiple desktop containers in one host under this configuration may be problematic and is not recommended. When deploying multiple containers, you must also pass new environment variables such as `-e DISPLAY=:22`, `-e NGINX_PORT=8082`, `-e SELKIES_PORT=8083`, and `-e SELKIES_METRICS_HTTP_PORT=9083` into the container, all not overlapping with any other X11 server or container in the same host. Access the container using the specified `NGINX_PORT`.

However, host networking may be restricted or not be desired because of security reasons or when deploying multiple desktop containers in one host. If not available, check if the container starts working after omitting `--network=host`.

</details>

- **External TURN Server:**

<details markdown>
  <summary>Open Section</summary>

If having no TURN server does not work, you need an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server). Read the [WebRTC and Firewall Issues](#webrtc-and-firewall-issues) section and add the environment variables `-e SELKIES_TURN_HOST=`, `-e SELKIES_TURN_PORT=`, and pick one of `-e SELKIES_TURN_SHARED_SECRET=` or both `-e SELKIES_TURN_USERNAME=` and `-e SELKIES_TURN_PASSWORD=` environment variables to the `docker run` command based on your authentication method.

</details>

### Running with Kubernetes

**1. Create the Kubernetes `Secret` with your authentication password (change keys and values as adequate):**

```bash
kubectl create secret generic my-pass --from-literal=my-pass=YOUR_PASSWORD
```

> NOTE: Replace `YOUR_PASSWORD` with your desired password, and change the name `my-pass` to your preferred name of the Kubernetes secret with the `xgl.yml` file changed accordingly as well. It is possible to skip the first step and directly provide the password with `value:` in `xgl.yml`, but this exposes the password in plain text.

**2. Create the pod after editing the `xgl.yml` file to your needs, explanations are available in the file:**

```bash
kubectl create -f xgl.yml
```

**If the Selkies WebRTC HTML5 interface does not connect or is extremely slow, read Step 4 and the [WebRTC and Firewall Issues](#webrtc-and-firewall-issues) section very carefully.**

> NOTE: The container tags available are `latest` and `24.04` for Ubuntu 24.04, `22.04` for Ubuntu 22.04, and `20.04` for Ubuntu 20.04. [Persistent container tags](https://github.com/selkies-project/docker-selkies-glx-desktop/pkgs/container/nvidia-glx-desktop) are available in the form `24.04-20210101010101`. `SELKIES_BASIC_AUTH_PASSWORD` will default to `PASSWD` if unspecified. The container must NOT be run in privileged mode.

Change `SELKIES_ENCODER` to `x264enc`, `vp8enc`, or `vp9enc` when using the Selkies interface if your GPU does not support `H.264 (AVCHD)` under the `NVENC - Encoding` section in NVIDIA's [Video Encode and Decode GPU Support Matrix](https://developer.nvidia.com/video-encode-and-decode-gpu-support-matrix-new).

**3. Connect to the web server spawned at port 8080. You may configure the ingress endpoint or reverse proxy that your Kubernetes cluster provides to this port for external connectivity.**

The default username is `ubuntu` for both the web authentication prompt and the container Linux username. The environment variable `PASSWD` (defaulting to `mypasswd`) is the password for the container Linux user account, and `SELKIES_BASIC_AUTH_PASSWORD` is the password for the HTML5 interface authentication prompt. If `SELKIES_ENABLE_BASIC_AUTH` is set to `true` for Selkies but `SELKIES_BASIC_AUTH_PASSWORD` is unspecified, the HTML5 interface password will default to `PASSWD`.

> NOTE: Only one web browser can be connected at a time with the Selkies WebRTC interface. If the signaling connection works, but the WebRTC connection fails, read Step 4 and the [WebRTC and Firewall Issues](#webrtc-and-firewall-issues) section.

Additional configurations and environment variables for the Selkies WebRTC HTML5 interface are listed in lines that start with `parser.add_argument` within the [Selkies Main Script](https://github.com/selkies-project/selkies/blob/master/src/selkies_gstreamer/__main__.py) or `selkies-gstreamer --help`.

**4. (Not Applicable for KasmVNC) Read carefully if the Selkies WebRTC HTML5 interface does not connect or is extremely slow.**

A [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) is required because you are self-hosting WebRTC, unlike commercial services using WebRTC.

Choose whether to use host networking, an internal [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server), or an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server).

- **Internal TURN Server:**

<details markdown>
  <summary>Open Section</summary>

There is an internal [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) inside the container that may be used when an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) or host networking is not available.

Uncomment the relevant environment variables `SELKIES_TURN_PROTOCOL=udp`, `SELKIES_TURN_PORT=3478`, `TURN_MIN_PORT=65532`, `TURN_MAX_PORT=65535` (change the ports accordingly) within `xgl.yml` (within `name:` and `value:`), where the `SELKIES_TURN_PORT` should not be used by any other host process or container, and the `TURN_MIN_PORT`/`TURN_MAX_PORT` port range has to contain at least two ports also not used by any other host process or container. Then, open all of these ports in the Kubernetes configuration `ports:` section in addition to the web server port.

If UDP cannot be used, at the cost of higher latency and lower performance, omit the UDP ports in the configuration and use the environment variable `SELKIES_TURN_PROTOCOL=tcp` (within `name:` and `value:`).

All these ports must be exposed to the internet if you need access over the internet. If you need use TURN within a local network, add the environment variable `SELKIES_TURN_HOST={YOUR_INTERNAL_IP}` (within `name:` and `value:`) with `{YOUR_INTERNAL_IP}` to the internal hostname or IP of the local network. IPv6 addresses must be enclosed with square brackets such as `[::1]`.

</details>

- **Host Networking:**

<details markdown>
  <summary>Open Section</summary>

Otherwise, the Selkies WebRTC HTML5 interface will likely just start working if you open UDP and TCP ports 49152–65535 in your host server network and uncomment `hostNetwork: true` in `xgl.yml`. Note that running multiple desktop containers in one host under this configuration may be problematic and is not recommended. When deploying multiple containers with `hostNetwork: true`, you must also pass new environment variables such as `DISPLAY=:22`, `NGINX_PORT=8082`, `SELKIES_PORT=8083`, and `SELKIES_METRICS_HTTP_PORT=9083` into the container, all not overlapping with any other X11 server or container in the same host. Access the container using the specified `NGINX_PORT`.

However, host networking may be restricted or not be desired because of security reasons or when deploying multiple desktop containers in one host. If not available, check if the container starts working after commenting out `hostNetwork: true`.

</details>

- **External TURN Server:**

<details markdown>
  <summary>Open Section</summary>

If having no TURN server does not work, you need an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server). Read the [WebRTC and Firewall Issues](#webrtc-and-firewall-issues) section and fill in the environment variables `SELKIES_TURN_HOST` and `SELKIES_TURN_PORT`, then pick one of `SELKIES_TURN_SHARED_SECRET` or both `SELKIES_TURN_USERNAME` and `SELKIES_TURN_PASSWORD` environment variables, based on your authentication method.

</details>

## WebRTC and Firewall Issues

Note that this section is only required for the Selkies WebRTC HTML5 interface.

In most cases when either of your server or client has a permissive firewall, the default Google STUN server configuration will work without additional configuration. However, when connecting from networks that cannot be traversed with STUN, a TURN server is required.

**Read the last steps of each Docker/Kubernetes instruction to use an internal TURN server. Alternatively, read the below sections.**

For an easy fix to when the signaling connection works, but the WebRTC connection fails, **open UDP and TCP ports 49152–65535 in your host server network** (or use Full Cone NAT in your network router/infrastructure settings), then add the option `--network=host` to your Docker command (or `network_mode: 'host'` in `docker-compose.yml`), or uncomment `hostNetwork: true` in your `xgl.yml` file when using Kubernetes (note that your cluster may have not allowed this, resulting in an error). This exposes your container to the host network, which disables network isolation. Note that running multiple desktop containers in one host under this configuration may be problematic and is not recommended. You must also pass new environment variables such as `-e DISPLAY=:22`, `-e NGINX_PORT=8082`, `-e SELKIES_PORT=8083`, and `-e SELKIES_METRICS_HTTP_PORT=9083` into the container, all not overlapping with any other X11 server or container in the same host. Access the container using the specified `NGINX_PORT`.

If this does not fix the connection issue (normally when the host is behind another additional firewall), you cannot use this fix for security or technical reasons, or when deploying multiple desktop containers in one host, read the below text to set up an external [TURN server](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server).

### Deploying a TURN server

**Read the instructions from [Selkies](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md#turn-server) if want to deploy an external TURN server or use a public TURN server instance. Read the last steps of each Docker/Kubernetes instruction to use an internal TURN server instead.**

### Configuring with Docker

More information is available in the [Selkies](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md) documentation.

With Docker (or Podman), use the `-e` option to add the `SELKIES_TURN_HOST`, `SELKIES_TURN_PORT` environment variables. This is the hostname or IP and the port of the TURN server (3478 in most cases).

You may set `SELKIES_TURN_PROTOCOL` to `tcp` if you are only able to open TCP ports for the coTURN container to the internet, or if the UDP protocol is blocked or throttled in your client network. You may also set `SELKIES_TURN_TLS` to `true` with the `-e` option if TURN over TLS/DTLS was properly configured with valid TLS certificates.

You also require to provide either only the environment variable `SELKIES_TURN_SHARED_SECRET` for time-limited shared secret TURN authentication, or both the environment variables `SELKIES_TURN_USERNAME` and `SELKIES_TURN_PASSWORD` for legacy long-term TURN authentication, depending on your TURN server configuration. Provide just one of these authentication methods, not both.

If there is a [TURN REST API](https://github.com/selkies-project/selkies/blob/main/docs/component.md#turn-rest) server, provide the environment variable `SELKIES_TURN_REST_URI` but not any other authentication credentials to the TURN REST URI within this infrastructure. If there is a shared TURN server within an infrastructure, consider reading the [TURN REST API](https://github.com/selkies-project/selkies/blob/main/docs/component.md#turn-rest) documentation or provide the link to your infrastructure administrator to deploy a TURN REST API server.

### Configuring with Kubernetes

More information is available in the [Selkies](https://github.com/selkies-project/selkies/blob/main/docs/firewall.md) documentation.

Your TURN server will use only one out of three ways to authenticate the client, so only provide one type of authentication method. The time-limited shared secret TURN authentication only requires the Base64 encoded `SELKIES_TURN_SHARED_SECRET`. The legacy long-term TURN authentication requires both `SELKIES_TURN_USERNAME` and `SELKIES_TURN_PASSWORD` credentials. The [TURN REST API](https://github.com/selkies-project/selkies/blob/main/docs/component.md#turn-rest) method only requires the `SELKIES_TURN_REST_URI` URI.

#### TURN REST API

If there is a shared TURN server within an infrastructure, consider reading the [TURN REST API](https://github.com/selkies-project/selkies/blob/main/docs/component.md#turn-rest) documentation or provide the link to your infrastructure administrator to deploy a TURN REST API server.

<details markdown>
  <summary>Open Section</summary>

Then, uncomment the lines in the `xgl.yml` file related to TURN server usage, updating the `SELKIES_TURN_REST_URI` environment variable as needed:

```yaml
- name: SELKIES_TURN_REST_URI
  value: "https://turn-rest.myinfrastructure.io:8443/myturnrest"
- name: SELKIES_TURN_PROTOCOL
  value: "udp"
- name: SELKIES_TURN_TLS
  value: "false"
```

</details>

#### Time-limited shared secret authentication

<details markdown>
  <summary>Open Section</summary>

**1. Create a secret containing the TURN shared secret:**

```bash
kubectl create secret generic turn-shared-secret --from-literal=turn-shared-secret=MY_SELKIES_TURN_SHARED_SECRET
```

> NOTE: Replace `MY_SELKIES_TURN_SHARED_SECRET` with the shared secret of the TURN server, then changing the name `turn-shared-secret` to your preferred name of the Kubernetes secret, with the `xgl.yml` file also being changed accordingly.

**2. Uncomment the lines in the `xgl.yml` file related to TURN server usage, updating the `SELKIES_TURN_HOST` and `SELKIES_TURN_PORT` environment variables as needed:**

```yaml
- name: SELKIES_TURN_HOST
  value: "turn.example.com"
- name: SELKIES_TURN_PORT
  value: "3478"
- name: SELKIES_TURN_SHARED_SECRET
  valueFrom:
    secretKeyRef:
      name: turn-shared-secret
      key: turn-shared-secret
- name: SELKIES_TURN_PROTOCOL
  value: "udp"
- name: SELKIES_TURN_TLS
  value: "false"
```

> NOTE: It is possible to skip the first step and directly provide the shared secret with `value:`, but this exposes the shared secret in plain text. Set `SELKIES_TURN_PROTOCOL` to `tcp` if you were able to only open TCP ports while creating your own coTURN Deployment/DaemonSet, or if your client network throttles or blocks the UDP protocol at the cost of higher latency and lower performance.

</details>

#### Legacy long-term authentication

<details markdown>
  <summary>Open Section</summary>

**1. Create a secret containing the TURN password:**

```bash
kubectl create secret generic turn-password --from-literal=turn-password=MY_SELKIES_TURN_PASSWORD
```

> NOTE: Replace `MY_SELKIES_TURN_PASSWORD` with the password of the TURN server, then changing the name `turn-password` to your preferred name of the Kubernetes secret, with the `xgl.yml` file also being changed accordingly.

**2. Uncomment the lines in the `xgl.yml` file related to TURN server usage, updating the `SELKIES_TURN_HOST`, `SELKIES_TURN_PORT`, and `SELKIES_TURN_USERNAME` environment variables as needed:**

```yaml
- name: SELKIES_TURN_HOST
  value: "turn.example.com"
- name: SELKIES_TURN_PORT
  value: "3478"
- name: SELKIES_TURN_USERNAME
  value: "username"
- name: SELKIES_TURN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: turn-password
      key: turn-password
- name: SELKIES_TURN_PROTOCOL
  value: "udp"
- name: SELKIES_TURN_TLS
  value: "false"
```

> NOTE: It is possible to skip the first step and directly provide the TURN password with `value:`, but this exposes the TURN password in plain text. Set `SELKIES_TURN_PROTOCOL` to `tcp` if you were able to only open TCP ports while creating your own coTURN Deployment/DaemonSet, or if your client network throttles or blocks the UDP protocol at the cost of higher latency and lower performance.

</details>

## Troubleshooting

### I have an issue related to the Selkies WebRTC HTML5 interface.

**[Link](https://github.com/selkies-project/selkies/blob/main/docs/README.md)**

### I want to customize this container.

**[Link](https://github.com/selkies-project/selkies/blob/main/docs/development.md)**

### I want to use the keyboard layout of my own language.

<details markdown>
  <summary>Open Answer</summary>

Run `Input Method: Configure Input Method` from the start menu, uncheck `Only Show Current Language`, search and add from available input methods (Hangul, Mozc, Pinyin, and others) by moving to the right, then use `Ctrl + Space` to switch between the input methods. Raise an issue if you need more layouts.

</details>

### The container does not work.

<details markdown>
  <summary>Open Answer</summary>

Check that the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) is properly configured in the host. Next, check that your host NVIDIA GPU driver is not the `nvidia-headless` variant, which lacks the required display and graphics capabilities for this container.

After that, check the environment variable `NVIDIA_DRIVER_CAPABILITIES` after starting a shell interface inside the container. `NVIDIA_DRIVER_CAPABILITIES` should be set to `all`, or include a comma-separated list of `compute` (requirement for CUDA and OpenCL, or for the [Selkies](https://github.com/selkies-project/selkies) WebRTC remote desktop interface), `utility` (requirement for `nvidia-smi` and NVML), `graphics` (requirement for OpenGL and part of the requirement for Vulkan), `video` (required for encoding or decoding videos using NVIDIA GPUs, or for the [Selkies](https://github.com/selkies-project/selkies) WebRTC remote desktop interface), `display` (the other requirement for Vulkan), and optionally `compat32` if you use Wine or 32-bit graphics applications.

Moreover, if you are using custom configurations, check if your shared memory path `/dev/shm` has sufficient capacity, where expanding the capacity is done by adding `--tmpfs /dev/shm:rw` to your Docker command or adding the below lines to your Kubernetes configuration file.

```yaml
spec:
  template:
    spec:
      containers:
        volumeMounts:
        - mountPath: /dev/shm
          name: dshm
      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
```

If you checked everything here, scroll down.

</details>

### I want to use `systemd`, `polkit`, FUSE mounts, or sandboxed (containerized) application distribution systems like Flatpak, Snapcraft (snap), AppImage, Electron, chrome-sandbox, etc.

<details markdown>
  <summary>Open Answer</summary>

**Use the option `--appimage-extract-and-run` or `--appimage-extract` with your AppImage to run them in a container. Alternatively, set `export APPIMAGE_EXTRACT_AND_RUN=1` to your current shell.**

Do not use `systemd`, `polkit`, FUSE mounts, or sandboxed application distribution systems with containers. You can use them if you add unsafe capabilities to your containers, but it will break the isolation of the containers. This is especially bad if you are using Kubernetes. There will likely be an alternative way to install the applications instead of Snapcraft (snap) or Flatpak, including [Personal Package Archives](https://launchpad.net/ubuntu/+ppas). For some applications, there will be options to disable sandboxing when running or options to extract files before running. When applications using Chrome Sandbox (chrome-sandbox) or the [Electron](https://www.electronjs.org/) framework show related errors, use the `--no-sandbox` command-line option when running such applications.

</details>

### I want to use this container with laptops or other integrated/hybrid GPU systems.

<details markdown>
  <summary>Open Answer</summary>

If you need a container that works out of the box, you should use [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop).

This container may work after some substantial configuration with the internal X.Org X11 server of the container, but is not guaranteed or officially supported.

Some references include [https://wiki.archlinux.org/title/NVIDIA_Optimus](https://wiki.archlinux.org/title/NVIDIA_Optimus), [https://wiki.archlinux.org/title/Bumblebee](https://wiki.archlinux.org/title/Bumblebee), and [https://wiki.debian.org/NVIDIA%20Optimus](https://wiki.debian.org/NVIDIA%20Optimus).

</details>

### I want to share one GPU with multiple containers to run GUI workloads.

<details markdown>
  <summary>Open Answer</summary>

Note that because of restrictions from Xorg, it is not possible to share one GPU to multiple Xorg servers running in different containers. Use [docker-selkies-egl-desktop](https://github.com/selkies-project/docker-selkies-egl-desktop) if you intend to do this.

</details>

### The container does not work if an existing GUI, desktop environment, or X server is running in the host outside the container. / I want to use this container in `--privileged` mode or with `--cap-add` and do not want other containers to interfere.

<details markdown>
  <summary>Open Answer</summary>

In order to use an X server on the host for your monitor with one GPU, and provision the other GPUs to the containers, you must change your `/etc/X11/xorg.conf` configuration of the host, **outside the container**.

First, use `nvidia-xconfig --no-probe-all-gpus --busid=$BUS_ID --only-one-x-screen` to generate `/etc/X11/xorg.conf` where `BUS_ID` is generated with the below script. Set `GPU_SELECT` to the ID (from `nvidia-smi`) of the specific GPU you want to provision.

```
HEX_ID=$(nvidia-smi --query-gpu=pci.bus_id --id="$GPU_SELECT" --format=csv,noheader | head -n1)
IFS=":." ARR_ID=($HEX_ID)
unset IFS
BUS_ID=PCI:$((16#${ARR_ID[1]})):$((16#${ARR_ID[2]})):$((16#${ARR_ID[3]}))
```

Then, edit the `/etc/X11/xorg.conf` file of your host outside the container and add the below snippet to the end of the file. If you want to use containers in `--privileged` mode or with `--cap-add`, add the snippet to the `/etc/X11/xorg.conf` files of all other containers running an Xorg server as well (already added for Selkies). The exact file location may vary if not using the NVIDIA graphics driver.

```
Section "ServerFlags"
    Option "AutoAddGPU" "False"
EndSection
```

[Reference](https://man.archlinux.org/man/extra/xorg-server/xorg.conf.d.5.en)

If you restart your OS or the Xorg server, you will now be able to use one GPU for your host X server and your real monitor, and use the other GPUs for the containers.

Then, you must avoid the GPU of which you are using for your host X server. Use `docker --gpus '"device=1,2"'` to provision GPUs with (for example) device IDs 1 and 2 to the container, avoiding the GPU with the ID of 0 that is used by the host X server, if you set `GPU_SELECT` to the ID of 0. Note that `--gpus 1` means any single GPU, not the GPU device ID of 1.

</details>

### Vulkan does not work.

<details markdown>
  <summary>Open Answer</summary>

Make sure that the `NVIDIA_DRIVER_CAPABILITIES` environment variable is set to `all`, or includes both `graphics` and `display`. The `display` capability is especially crucial to Vulkan, but the container does start without noticeable issues other than Vulkan without `display`, despite its name.

</details>

### The container does not work if I set the resolution above 1920 x 1200 or 2560 x 1600 in 60 hz.

**Upgrade to the latest minor version of the NVIDIA driver major version 550 or higher. The answer contains legacy information for people who cannot upgrade.**

<details markdown>
  <summary>Open Answer</summary>

If your GPU is a consumer or professional GPU, change the `VIDEO_PORT` environment variable from `DFP` to `DP-0` if `DP-0` is empty, or any empty `DP-*` port. Set `VIDEO_PORT` to where your monitor is connected if you want to show the remote desktop in a real monitor. If your GPU is a Datacenter (Tesla) GPU, keep the `VIDEO_PORT` environment variable to `DFP`, and your maximum resolution is at 2560 x 1600. To go above this restriction, you may set `VIDEO_PORT` to `none`, but you must use borderless window instead of fullscreen, and this may lead to quite a lot of applications not starting, showing errors related to `XRANDR` or `RANDR`.

The container simulates the GPU to become plugged into a physical DVI-D/HDMI/DisplayPort digital video interface in consumer and professional GPUs with the `ConnectedMonitor` NVIDIA driver option. The container uses virtualized DVI-D ports for this purpose in Datacenter (Tesla) GPUs.

The ports to be used should **only** be connected with an actual monitor if the user wants the remote desktop screen to be shown on that monitor. If you want to show the remote desktop screen spawned by the container in a physical monitor, connect the monitor and set `VIDEO_PORT` to the the video interface identifier that is connected to the monitor. If not, avoid the video interface identifier that is connected to the monitor.

`VIDEO_PORT` identifiers and their connection states can be obtained by typing `xrandr -q` when the `DISPLAY` environment variable is set to the number of the spawned X server display (for example `:0`). As an alternative, you may set `VIDEO_PORT` to `none` (which effectively sets `--use-display-device=None`), but you must use borderless window instead of fullscreen, and this may lead to quite a lot of applications not starting because the `RANDR` extension is not available in the X server.

> NOTE: Do not start two or more X servers for a single GPU. Use a separate GPU (or use Xvfb/Xdummy/Xvnc without hardware acceleration to use no GPUs at all) if you need a host X server unaffiliated with containers, and do not make the GPU available to the container runtime.

Since this container simulates the GPU being virtually plugged into a physical monitor while it actually does not, make sure the resolutions specified with the environment variables `DISPLAY_SIZEW` and `DISPLAY_SIZEH` are within the maximum size supported by the GPU. The environment variable `VIDEO_PORT` can override which video port is used (defaults to `DFP`, the first interface detected in the driver). Therefore, specifying `VIDEO_PORT` to an unplugged DisplayPort (for example numbered like `DP-0`, `DP-1`, and so on) is recommended for resolutions above 1920 x 1200 at 60 hz, because some driver restrictions are applied when the default is set to an unplugged physical DVI-D or HDMI port. The maximum size that should work in all cases is 1920 x 1200 at 60 hz, mainly for when the default `VIDEO_PORT` identifier `DFP` is not set to DisplayPort. The screen sizes over 1920 x 1200 at 60 hz but under the maximum supported display size specified for each port (supported by GPU specifications) will be possible if the port is set to DisplayPort (both physically connected or disconnected), or when a physical monitor or dummy plug to any other type of display ports (including DVI-D and HDMI) has been physically connected. If all GPUs in the cluster have at least one DisplayPort and they are not physically connected to any monitors, simply setting `VIDEO_PORT` to `DP-0` is recommended (but this is not set as default because of legacy GPU compatibility reasons).

Datacenter (Tesla) GPUs seem to only support resolutions of up to around 2560 x 1600 at 60 hz (`VIDEO_PORT` must be kept to `DFP` instead of changing to `DP-0` or other DisplayPort identifiers). The K40 (Kepler) GPU did not support RandR (required for some graphical applications using SDL and other graphical frameworks). Other Kepler generation Datacenter GPUs (maybe except the GRID K1 and K2 GPUs with vGPU capabilities) are also unlikely to support RandR, thus Datacenter GPU RandR support probably starts from Maxwell. Other tested Datacenter GPUs (V100, T4, A40, A100) support all graphical applications that consumer GPUs support. However, the performances were not better than consumer GPUs that usually cost a fraction of Datacenter GPUs, and the maximum supported resolutions were even lower.

</details>

---
This project has been developed and is supported in part by the National Research Platform (NRP) and the Cognitive Hardware and Software Ecosystem Community Infrastructure (CHASE-CI) at the University of California, San Diego, by funding from the National Science Foundation (NSF), with awards #1730158, #1540112, #1541349, #1826967, #2138811, #2112167, #2100237, and #2120019, as well as additional funding from community partners, infrastructure utilization from the Open Science Grid Consortium, supported by the National Science Foundation (NSF) awards #1836650 and #2030508, and infrastructure utilization from the Chameleon testbed, supported by the National Science Foundation (NSF) awards #1419152, #1743354, and #2027170. This project has also been funded by the Seok-San Yonsei Medical Scientist Training Program (MSTP) Song Yong-Sang Scholarship, College of Medicine, Yonsei University, the MD-PhD/Medical Scientist Training Program (MSTP) through the Korea Health Industry Development Institute (KHIDI), funded by the Ministry of Health & Welfare, Republic of Korea, and the Student Research Bursary of Song-dang Institute for Cancer Research, College of Medicine, Yonsei University.
