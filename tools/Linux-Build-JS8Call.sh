#!/bin/bash
set -e

# (C) copyright 2025 Chris Olson AC9KH, Joseph Counsil K0OG
# Builds and installs JS8Call from source for local user.

# --- Variables ---
red="\033[0;31m"
clear_color="\033[0m"
JS8_VERSION="release/3.0.2"
JS8_QT_DIR="$HOME/.local/lib/Qt"
JS8_LIB_DIR="$HOME/.local/lib/js8lib"

# --- Functions ---
divider() {
  echo "######################################################################"
}

error() {
  echo "Installation has exited with an error."
  exit 1
}

clear

# --- Must not run as root ---
if [ "$(id -u)" -eq 0 ]; then
  divider
  echo -e "${red}You are logged in as root.

You MUST be logged in as a normal user to run this script.

It is recommended to add your username to the sudo group. We need to
install system libraries that are required to build JS8Call. This must
be done as a sudo user.

This script will NOT RUN AS ROOT!${clear_color}"
  divider
  exit 1
fi

# --- Detect distro ---
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "Cannot detect Linux distribution. Exiting."
  exit 1
fi

install_deps() {
  if [[ "$DISTRO" == "fedora" || "$DISTRO" == "rhel" || \
        "$DISTRO" == "centos" || "$DISTRO" == "rocky" || \
        "$DISTRO" == "almalinux" ]]; then
    echo "Detected Red Hat-based system ($DISTRO), using dnf..."
    sudo dnf install -y \
      cmake ninja-build gcc-c++ perl python3 git wget file \
      openssl-devel fontconfig-devel freetype-devel \
      harfbuzz-devel libjpeg-turbo-devel libpng-devel \
      zlib-devel brotli-devel dbus-devel glib2-devel \
      at-spi2-core-devel mesa-libGL-devel mesa-libEGL-devel \
      mesa-libgbm-devel libdrm-devel libinput-devel \
      vulkan-loader-devel \
      libxkbcommon-devel libxkbcommon-x11-devel \
      xcb-util-devel xcb-util-image-devel xcb-util-keysyms-devel \
      xcb-util-renderutil-devel xcb-util-wm-devel xcb-util-cursor-devel \
      libXrender-devel libXi-devel \
      pulseaudio-libs-devel alsa-lib-devel \
      gstreamer1-devel gstreamer1-plugins-base-devel \
      wayland-devel wayland-protocols-devel

  elif [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" || \
          "$DISTRO" == "linuxmint" || "$DISTRO" == "pop" ]]; then
    echo "Detected Debian-based system ($DISTRO), using apt..."
    sudo apt-get update
    sudo apt-get install -y --ignore-missing \
      build-essential file wget git cmake ninja-build perl python3 \
      libssl-dev libfontconfig1-dev libfreetype-dev \
      libharfbuzz-dev libjpeg-dev libpng-dev \
      zlib1g-dev libbrotli-dev libdbus-1-dev libglib2.0-dev \
      libatspi2.0-dev libgl-dev libegl-dev libgbm-dev \
      libdrm-dev libinput-dev libvulkan-dev \
      mesa-utils libglu1-mesa-dev freeglut3-dev mesa-common-dev \
      libxkbcommon-dev libxkbcommon-x11-dev \
      libxcb-util-dev libxcb-image0-dev libxcb-keysyms1-dev \
      libxcb-render-util0-dev libxcb-icccm4-dev libxcb-cursor0 \
      libxrender-dev libxi-dev \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      libwayland-dev wayland-protocols
      
    # Handle libasound rename in Ubuntu 24+
    sudo apt-get install -y libasound2-dev || sudo apt-get install -y libasound2t64
    
  elif [[ "$DISTRO" == "arch" || "$DISTRO" == "manjaro" || \
          "$DISTRO" == "endeavouros" || "$DISTRO" == "garuda" ]]; then
    echo "Detected Arch-based system ($DISTRO), using pacman..."
    sudo pacman -Syu --noconfirm \
      cmake ninja gcc perl python git wget \
      openssl fontconfig freetype2 \
      harfbuzz libjpeg-turbo libpng \
      zlib brotli dbus glib2 \
      at-spi2-core mesa libglvnd \
      libdrm libinput \
      vulkan-icd-loader \
      libxkbcommon \
      xcb-util xcb-util-image xcb-util-keysyms \
      xcb-util-renderutil xcb-util-wm xcb-util-cursor \
      libxrender libxi \
      libpulse alsa-lib \
      gst-plugins-base \
      wayland wayland-protocols \
      libxrandr libxext libxfixes \
      libxcb libxshmfence \
      libx11 \
      yasm nasm \
      clang llvm

  else
    echo "Unsupported distribution: $DISTRO"
    echo "Please install dependencies manually and re-run."
    exit 1
  fi
}

# --- Check for existing installation ---
clear
divider
echo "Checking for existing installation....."
if [ -e "$HOME/.local/bin/JS8"* ] 2>/dev/null; then
  divider
  echo "An existing JS8Call installation was found. Do you want to
uninstall it? Selecting No will overwrite it with the new version."
  read -p "Uninstall current JS8Call? Yes(y) / No(n): " UNINSTALL </dev/tty
  if [ "${UNINSTALL}" = "y" ]; then
    echo "Removing JS8Call binary..."
    rm -f "$HOME/.local/bin/JS8"*
    echo "Removing Qt 6.9.3..."
    rm -rf "$JS8_QT_DIR"
    echo "Removing libraries..."
    rm -rf "$JS8_LIB_DIR"
    echo "Removing desktop entry..."
    rm -f "$HOME/.local/share/applications/JS8Call.desktop"
    echo "Removing icon..."
    rm -f "$HOME/.local/share/icons/icon_128.svg"
    divider
    echo "JS8Call has been uninstalled.
To reinstall, run this script again."
    divider
    exit 0
  fi
fi

# --- Introduction ---
clear
divider
echo -e "This script will fetch necessary sources and dependencies to build
JS8Call and install it for the local user only on your system.
If you already have an existing JS8Call installation from your distribution
or downloaded from the Releases it will not affect that and you will be able
to run either version of the program, but not at the same time.
Please see the NOTES on the next page:"
divider
read -p "Press Enter to continue" </dev/tty

clear
echo "NOTES:
The newest versions of JS8Call require Qt v6.9.3 to run correctly. Most
linux distributions do not package Qt6.9.3. The JS8Call project has pre-compiled
Qt6.9.3 libraries by Chris-AC9KH that this script will fetch and install. This
will not affect whatever version of Qt you have installed from your distribution.
The two versions can co-exist and JS8Call will be linked with the
Qt6.9.3 installation, which will be in your ~/.local/lib/Qt6 directory.

If you run this script a second time after installation, it will ask if you want
to uninstall JS8Call. The Qt6.9.3 library will also be removed during uninstall.
The Qt6.9.3 archive downloaded by this script will be saved in your Downloads
folder. Delete it if you no longer need it.

This script has been tested on Debian 12/13, Mint, Fedora, and Ubuntu 24.

The JS8Call menu item is tested with Gnome. It should work on KDE since linux
desktops follow freedesktop.org conventions, though this is not always the case.
If you don't see a menu item on KDE under the Other category, the binary is at
~/.local/bin/JS8Call — you can symlink it or launch it directly. KDE may require
a logout/login to refresh menus."
divider
read -p "Press Enter to continue" </dev/tty

clear
echo "AUDIO:
Newer versions of Qt use the FFmpeg audio backend. ALSA audio is deprecated.
JS8Call 2.3 and later requires PipeWire or PulseAudio — there will be no audio
without one of these. When JS8Call starts it will use your existing settings if
you have a prior installation. Note there is some incompatibility with audio and
text encoding between JS8Call 2.2 (Fortran/Qt5) and 2.3+ (C++/Qt6)."
divider
read -p "Press Enter to continue" </dev/tty

# --- Sudo warning for Debian users ---
if [[ "$DISTRO" == "debian" ]]; then
  clear
  echo -e "NOTE for Debian users:
Debian does not add users to the sudo group by default. If you have not
already done this, run the following as root, replacing
${red}your_username${clear_color} with your login name:

  ${red}usermod -aG sudo your_username${clear_color}

You will need to reboot for this change to take effect."
  divider
fi

read -p "Continue with installation? Yes(y) / No(n): " INSTALL </dev/tty
if [ ! "${INSTALL}" = "y" ]; then
  echo "Installation cancelled."
  exit 0
fi

# --- Install system dependencies ---
clear
echo "Installing build dependencies..."
install_deps

# --- Create development directory ---
mkdir -p "$HOME/development"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/lib"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons"

# --- Detect architecture ---
clear
divider
JS8_ARCH=$(uname -m)
echo "System architecture: $JS8_ARCH"
divider
sleep 2

# --- Fetch Qt6 and js8lib if not already installed ---
echo "Checking for Qt 6.9.3..."
divider
sleep 2

cd "$HOME/development"

if [ ! -d "$JS8_QT_DIR" ]; then
  if [ "${JS8_ARCH}" = "aarch64" ]; then
    wget -c https://github.com/JS8Call-improved/js8lib/releases/download/lib%2F3.0/Qt6.9.3_Linux_aarch64.tar.gz
    wget -c https://github.com/JS8Call-improved/js8lib/releases/download/lib%2F3.0/js8lib3.0-Linux_aarch64.tar.gz
    tar -xzvf Qt6.9.3_Linux_aarch64.tar.gz -C "$HOME/.local/lib/"
    mv Qt6.9.3_Linux_aarch64.tar.gz "$HOME/Downloads/"
    tar -xzvf js8lib3.0-Linux_aarch64.tar.gz -C "$HOME/.local/lib/"
    mv js8lib3.0-Linux_aarch64.tar.gz "$HOME/Downloads/"
  else
    wget -c https://github.com/JS8Call-improved/js8lib/releases/download/lib%2F3.0/Qt6.9.3_Linux_x86_64.tar.gz
    wget -c https://github.com/JS8Call-improved/js8lib/releases/download/lib%2F3.0/js8lib3.0-Linux_x86_64.tar.gz
    tar -xzvf Qt6.9.3_Linux_x86_64.tar.gz -C "$HOME/.local/lib/"
    mv Qt6.9.3_Linux_x86_64.tar.gz "$HOME/Downloads/"
    tar -xzvf js8lib3.0-Linux_x86_64.tar.gz -C "$HOME/.local/lib/"
    mv js8lib3.0-Linux_x86_64.tar.gz "$HOME/Downloads/"
  fi
  echo "Qt 6.9.3 and library archives moved to Downloads folder."
else
  echo "Qt 6.9.3 already installed — skipping download."
  divider
  sleep 2
fi

# Fix hardcoded paths in pkgconfig files — always runs regardless of
# whether libraries were just downloaded or already existed.
# Handles builds from any username
for pc in "$HOME/.local/lib/js8lib/lib/pkgconfig/"*.pc; do
  sed -i "s|prefix=.*local/lib/js8lib|prefix=$HOME/.local/lib/js8lib|g" "$pc"
done
for pc in "$HOME/.local/lib/Qt/lib/pkgconfig/"*.pc; do
  sed -i "s|prefix=.*local/lib/Qt|prefix=$HOME/.local/lib/Qt|g" "$pc"
done

# --- Fetch JS8Call source ---
clear
echo "Fetching JS8Call source code..."
divider

if [ ! -d "$HOME/development/JS8Call-improved" ]; then
  git clone "https://github.com/JS8Call-improved/JS8Call-improved.git"
  cd JS8Call-improved
  git checkout "${JS8_VERSION}"
else
  echo "Source directory already exists — checking for updates..."
  cd JS8Call-improved
  git fetch origin
  git checkout "${JS8_VERSION}"
  git pull origin "${JS8_VERSION}"
fi
sleep 2

# --- Build JS8Call ---
cd "$HOME/development/JS8Call-improved"
BRANCH=$(git branch --show-current)

clear
divider
echo "JS8Call Build Details:
  Qt version : 6.9.3 with FFmpeg audio (requires PulseAudio or PipeWire)
  Branch     : JS8Call-improved ${BRANCH}
  Distro     : ${DISTRO} / ${JS8_ARCH}"
divider
read -p "Press Enter to continue" </dev/tty

# Remove any previous build directory to avoid stale config
rm -rf "$HOME/development/JS8Call-improved/build"
mkdir build
cd build

cmake \
  -DCMAKE_PREFIX_PATH="$HOME/.local/lib/js8lib;$HOME/.local/lib/Qt" \
  -DHAMLIB_ROOT="$HOME/.local/lib/js8lib" \
  -Dhamlib_ROOT="$HOME/.local/lib/js8lib" \
  ..
cmake --build . --parallel $(nproc)

# --- Install ---
cp JS8Call "$HOME/.local/bin/"

# --- Desktop entry ---
cat > "$HOME/.local/share/applications/JS8Call.desktop" << EOF
[Desktop Entry]
Type=Application
Name=JS8Call
Exec=$HOME/.local/bin/JS8Call
Icon=$HOME/.local/share/icons/icon_128.svg
Terminal=false
Categories=HamRadio;Network;
EOF

cp ../artwork/icon_128.svg "$HOME/.local/share/icons/"

# --- Cleanup prompt ---
clear
divider
echo "DONE!"
echo "Do you want to remove the JS8Call development directory?
The program will run fine without it and you can re-fetch it with this
script at any time."
divider
read -p "Remove JS8Call source tree? Yes(y) / No(n): " CLEANUP </dev/tty

if [ "${CLEANUP}" = "y" ]; then
  rm -rf "$HOME/development"
  echo "Source tree removed."
else
  echo "Source tree kept at ~/development."
fi

divider
echo "JS8Call is installed. The launcher should appear in your application menu.
On KDE you may need to log out and back in to refresh the menu."
divider
exit 0
