#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e

trap "echo TRAPed signal" HUP INT QUIT TERM

# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done
# Make user directory owned by the default user
chown -f "$(id -nu):$(id -ng)" ~ || sudo-root chown -f "$(id -nu):$(id -ng)" ~ || chown -R -f -h --no-preserve-root "$(id -nu):$(id -ng)" ~ || sudo-root chown -R -f -h --no-preserve-root "$(id -nu):$(id -ng)" ~ || echo 'Failed to change user directory permissions, there may be permission issues'
# Change operating system password to environment variable
(echo "${PASSWD}"; echo "${PASSWD}";) | sudo passwd "$(id -nu)" || (echo "mypasswd"; echo "${PASSWD}"; echo "${PASSWD}";) | passwd "$(id -nu)" || echo 'Password change failed, using default password'
# Remove directories to make sure the desktop environment starts
rm -rf /tmp/.X* ~/.cache || echo 'Failed to clean X11 paths'
# Change time zone from environment variable
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" | tee /etc/timezone > /dev/null || echo 'Failed to set timezone'
# Add Lutris directories to path
export PATH="${PATH:+${PATH}:}/usr/local/games:/usr/games"
# Add LibreOffice to library path
export LD_LIBRARY_PATH="/usr/lib/libreoffice/program${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Configure joystick interposer
export SELKIES_INTERPOSER='/usr/$LIB/selkies_joystick_interposer.so'
export LD_PRELOAD="${SELKIES_INTERPOSER}${LD_PRELOAD:+:${LD_PRELOAD}}"
export SDL_JOYSTICK_DEVICE=/dev/input/js0
mkdir -pm1777 /dev/input || sudo-root mkdir -pm1777 /dev/input || echo 'Failed to create joystick interposer directory'
touch /dev/input/js0 /dev/input/js1 /dev/input/js2 /dev/input/js3 || sudo-root touch /dev/input/js0 /dev/input/js1 /dev/input/js2 /dev/input/js3 || echo 'Failed to create joystick interposer devices'
chmod 777 /dev/input/js* || sudo-root chmod 777 /dev/input/js* || echo 'Failed to change permission for joystick interposer devices'

# Set default display
export DISPLAY="${DISPLAY:-:20}"
# PipeWire-Pulse server socket path
export PIPEWIRE_LATENCY="128/48000"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

if ! command -v nvidia-xconfig >/dev/null 2>&1; then
  # Install NVIDIA userspace driver components including X graphic libraries, keep contents same between docker-selkies-glx-desktop and docker-selkies-egl-desktop
  export NVIDIA_DRIVER_ARCH="$(dpkg --print-architecture | sed -e 's/arm64/aarch64/' -e 's/armhf/32bit-ARM/' -e 's/i.*86/x86/' -e 's/amd64/x86_64/' -e 's/unknown/x86_64/')"
  if [ -z "${NVIDIA_DRIVER_VERSION}" ]; then
    # Driver version is provided by the kernel through the container toolkit, prioritize kernel driver version if available
    if [ -f "/proc/driver/nvidia/version" ]; then
      export NVIDIA_DRIVER_VERSION="$(head -n1 </proc/driver/nvidia/version | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9\.]+/) {print $i; exit}}')"
    elif command -v nvidia-smi >/dev/null 2>&1; then
      # Use NVIDIA-SMI when not available
      export NVIDIA_DRIVER_VERSION="$(nvidia-smi --version | grep 'DRIVER version' | cut -d: -f2 | tr -d ' ')"
    else
      echo 'Failed to find NVIDIA GPU driver version, container will likely not start because of no NVIDIA container toolkit or NVIDIA GPU driver present'
    fi
  fi
  cd /tmp
  # If version is different, new installer will overwrite the existing components
  if [ ! -f "/tmp/NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}.run" ]; then
    # Check multiple sources in order to probe both consumer and datacenter driver versions
    curl -fsSL -O "https://international.download.nvidia.com/XFree86/Linux-${NVIDIA_DRIVER_ARCH}/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}.run" || curl -fsSL -O "https://international.download.nvidia.com/tesla/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}.run" || echo 'Failed NVIDIA GPU driver download'
  fi
  if [ -f "/tmp/NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}.run" ]; then
    # Extract installer before installing
    rm -rf "NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}"
    sh "NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}.run" -x
    cd "NVIDIA-Linux-${NVIDIA_DRIVER_ARCH}-${NVIDIA_DRIVER_VERSION}"
    # Run NVIDIA driver installation without the kernel modules and host components
    sudo ./nvidia-installer --silent \
                      --no-kernel-module \
                      --install-compat32-libs \
                      --no-nouveau-check \
                      --no-nvidia-modprobe \
                      --no-systemd \
                      --no-rpms \
                      --no-backup \
                      --no-check-for-alternate-installs
    rm -rf /tmp/NVIDIA* && cd ~
  else
    echo 'Unless using non-NVIDIA GPUs, container will likely not work correctly'
  fi
fi

# Remove existing Xorg configuration
if [ -f "/etc/X11/xorg.conf" ]; then
  rm -f "/etc/X11/xorg.conf"
fi

# Get first GPU device of specified visible devices when `NVIDIA_VISIBLE_DEVICES` devices are specified
if [ "${NVIDIA_VISIBLE_DEVICES}" != "all" ] && [ "${NVIDIA_VISIBLE_DEVICES}" != "none" ] && [ "${NVIDIA_VISIBLE_DEVICES}" != "void" ] && [ -n "${NVIDIA_VISIBLE_DEVICES}" ]; then
  export GPU_SELECT="$(nvidia-smi --id=$(echo ${NVIDIA_VISIBLE_DEVICES} | cut -d ',' -f1) --query-gpu=uuid --format=csv,noheader | head -n1)"
# Get first GPU device out of all visible devices in other situations
else
  export GPU_SELECT="$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1)"
fi

if [ -z "${GPU_SELECT}" ] || [ "${GPU_SELECT#*No devices}" != "${GPU_SELECT}" ]; then
  export GPU_SELECT="$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1)"
  if [ -z "${GPU_SELECT}" ]; then
    echo "No NVIDIA GPUs detected or NVIDIA Container Toolkit not configured. Exiting."
    exit 1
  fi
fi

# Setting `VIDEO_PORT` to none disables RANDR/XRANDR, causing potential compatibility issues, set to DFP if using datacenter GPUs
if [ "$(echo ${VIDEO_PORT} | tr '[:upper:]' '[:lower:]')" = "none" ]; then
  export CONNECTED_MONITOR="--use-display-device=None"
# The X server is otherwise deliberately set to a specific video port despite not being plugged to enable RANDR/XRANDR, monitor will display the screen if plugged to the specific port
else
  export CONNECTED_MONITOR="--connected-monitor=${VIDEO_PORT:-DFP}"
fi

# Bus ID from nvidia-smi is in hexadecimal format and should be converted to decimal format (including the domain) which Xorg understands, required because nvidia-xconfig doesn't work as intended in a container
HEX_ID="$(nvidia-smi --query-gpu=pci.bus_id --id=${GPU_SELECT} --format=csv,noheader | head -n1)"
IFS=":." ARR_ID=(${HEX_ID})
unset IFS
BUS_ID="PCI:$(printf '%u' 0x${ARR_ID[1]})@$(printf '%u' 0x${ARR_ID[0]}):$(printf '%u' 0x${ARR_ID[2]}):$(printf '%u' 0x${ARR_ID[3]})"
# A custom modeline should be generated because there is no monitor to fetch this information normally
export MODELINE="$(cvt -r ${DISPLAY_SIZEW} ${DISPLAY_SIZEH} ${DISPLAY_REFRESH} | sed -n 2p)"
# Generate /etc/X11/xorg.conf with nvidia-xconfig
nvidia-xconfig --virtual="${DISPLAY_SIZEW}x${DISPLAY_SIZEH}" --depth="${DISPLAY_CDEPTH}" --mode="$(echo ${MODELINE} | awk '{print $2; exit}' | tr -d '\"')" --allow-empty-initial-configuration --no-probe-all-gpus --busid="${BUS_ID}" --include-implicit-metamodes --mode-debug --no-sli --no-base-mosaic --only-one-x-screen ${CONNECTED_MONITOR}
# Guarantee that the X server starts without a monitor by adding more options to the configuration
sed -i '/Driver\s\+"nvidia"/a\    Option         "ModeValidation" "NoMaxPClkCheck,NoEdidMaxPClkCheck,NoMaxSizeCheck,NoHorizSyncCheck,NoVertRefreshCheck,NoVirtualSizeCheck,NoExtendedGpuCapabilitiesCheck,NoTotalSizeCheck,NoDualLinkDVICheck,NoDisplayPortBandwidthCheck,AllowNon3DVisionModes,AllowNonHDMI3DModes,AllowNonEdidModes,NoEdidHDMI2Check,AllowDpInterlaced"' /etc/X11/xorg.conf
# Support external GPUs
sed -i '/Driver\s\+"nvidia"/a\    Option         "AllowExternalGpus" "True"' /etc/X11/xorg.conf
# Add custom generated modeline to the configuration
sed -i '/Section\s\+"Monitor"/a\    '"${MODELINE}" /etc/X11/xorg.conf
# Disable screen blanking in X11
sed -i '/"DPMS"/d' /etc/X11/xorg.conf
sed -i '/Section\s\+"Monitor"/a\    Option         "DPMS" "False"' /etc/X11/xorg.conf
# Prevent interference between GPUs, add this to the host or other containers running Xorg as well
echo -e "Section \"ServerFlags\"\n    Option         \"DontVTSwitch\" \"True\"\n    Option         \"DontZap\" \"True\"\n    Option         \"AllowMouseOpenFail\" \"True\"\n    Option         \"AutoAddGPU\" \"False\"\nEndSection" | tee -a /etc/X11/xorg.conf > /dev/null

# Real sudo (sudo-root) is required in Ubuntu 20.04 but not in newer Ubuntu, this symbolic link enables running Xorg inside a container with `-sharevts`
ln -snf /dev/ptmx /dev/tty7 || sudo-root ln -snf /dev/ptmx /dev/tty7 || echo 'Failed to create /dev/tty7 device'

# Run Xorg server with required extensions
/usr/lib/xorg/Xorg "${DISPLAY}" vt7 -noreset -novtswitch -sharevts -nolisten "tcp" -ac -dpi "${DISPLAY_DPI}" +extension "COMPOSITE" +extension "DAMAGE" +extension "GLX" +extension "RANDR" +extension "RENDER" +extension "MIT-SHM" +extension "XFIXES" +extension "XTEST" &

# Wait for X server to start
echo 'Waiting for X Socket' && until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do sleep 0.5; done && echo 'X Server is ready'

# Start KDE desktop environment
export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"
/usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 &

# Start Fcitx input method framework
/usr/bin/fcitx &

# Add custom processes right below this line, or within `supervisord.conf` to perform service management similar to systemd

echo "Session Running. Press [Return] to exit."
read
