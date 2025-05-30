#!/bin/bash

# Copyright (c) 2025 by Philip Collier, github.com/AB9IL
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version. There is NO warranty; not even for
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Run this script as root user (use sudo). This installer converts an existing
# Debian minimal or desktop system with Xfce into an opinionated respin with
# the same roster of features as in the Skywave Linux iso builds.
#
# Skywave Linux is a respin of Debian Sid. It will work on some, if not most,
# Debian variants. This version uses the Dynamic Window Manager (DWM), but it
# has been tested with i3,Sway, and Awesomewm.
#
# Refs:
# https://blog.aktsbot.in/swaywm-on-debian-11.html
# https://github.com/natpen/awesome-wayland
# https://github.com/swaywm/sway/wiki#gtk-applications-take-20-seconds-to-start
# https://lists.debian.org/debian-live/
#
# Switching to the Xanmod kernels:
# 1. Download the debs from SourceForge (image, headers, libc)
# 2. Install with dpkg -i *.deb
# 3. Purge the old linux-image and linux-image-amd64
# 4. Purge the old linux-headers and linux-headers-amd64
# 5. Pay attention to proper filenames for the initrd and vmlinuz files.

###############################################################################
# ROOT USER CHECK
###############################################################################
SCRIPT_VERSION="0.3"
echo -e "\nSkywave Linux Converter v$SCRIPT_VERSION"
# exit if not root
[[ $EUID -ne 0 ]] && echo -e "\nYou must be root to run this script." && exit

echo -e "You are about to make substantal changes to this system!\n"
echo -e "\n\nAre you sure you want to continue?"
echo ""
echo 'Please answer "yes" or "no"'
read line
case "$line" in
yes | Yes) echo "Okay, starting the conversion process!" ;;
*)
    echo '"yes" not received, exiting the script.'
    exit 0
    ;;
esac

###############################################################################
# SET VARIABLES
###############################################################################

USERNAME="$(logname)"

# most installations will go under the "working directory"
export working_dir="/usr/local/src"

export USERNAME
export ARCH="amd64"
export ARCH2="x86_64"
export GOTGPT_VER="2.9.2"
export OBSIDIAN_VER="1.8.9"
export MeshChatVersion="v1.21.0"
export VPNGateVersion="0.3.1"
export LF_VER="34"
export LAZYGIT_VER="0.48.0"
export TRUNK_VER="0.6.1"
export CYAN_VER="1.2.4"
export STARSH_VER="1.22.1"
export FONT_VER="3.3.0"
export FONTS="Arimo.tar.xz FiraCode.tar.xz Inconsolata.tar.xz \
    NerdFontsSymbolsOnly.tar.xz"

###############################################################################
# START INSTALLING
###############################################################################

# Start this section with an apt configuration
# Then install nala for speed and aptitude for dependency resolution
echo 'APT::Install-Recommends "false";
APT::AutoRemove::RecommendsImportant "false";
APT::AutoRemove::SuggestsImportant "false";' >/etc/apt/apt.conf.d/99_norecommends

echo 'APT::Periodic::Update-Package-Lists "false";
APT::Periodic::Download-Upgradeable-Packages "false";
APT::Periodic::AutocleanInterval "false";
APT::Periodic::Unattended-Upgrade "false";' >/etc/apt/apt.conf.d/10periodic

echo '# Modernized from /etc/apt/sources.list
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: unstable
Components: main contrib non-free-firmware non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Modernized from /etc/apt/sources.list
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: experimental
Components: main contrib non-free-firmware non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
' >/etc/apt/sources.list.d/debian.sources

apt update
apt -y install nala aptitude git aria2

# uv is a great tool for Python. Use the installer script:
curl -fsSL https://astral.sh/uv/install.sh | sh

# Replace UFW with firewalld then set rules:
nala purge --autoremove -y ufw
nala install -y firewalld
firewall-cmd --permanent --add-service={ssh,http,https}
systemctl reload firewalld

# Set up DNS over HTTPS:
nala install -y dnss
sed -i "s/^.*supersede domain-name-servers.*;/supersede domain-name-servers 127.0.0.1" /etc/dhcp/dhclient.conf

echo '[main]
plugins=ifupdown,keyfile
dns=127.0.0.1
rc-manager=unmanaged

[ifupdown]
managed=false

[device]
wifi.scan-rand-mac-address=no' >/etc/NetworkManager/NetworkManager.conf

# Configure dnss to use alternative servers on 9981:
echo '# dnss can be run in 3 different modes, depending on the flags given to it:
# DNS to HTTPS (default), DNS to GRPC, and GRPC to DNS.
# This variable controls the mode, and its parameters.
# The default is DNS to HTTPS mode, which requires no additional
# configuration. For the other modes, see dnss documentation and help.
MODE_FLAGS="--enable_dns_to_https"

# Flag to configure monitoring.
# By default, we listen on 127.0.0.1:9981, but this variable allows you to
# change that. To disable monitoring entirely, leave this empty.
MONITORING_FLAG="--monitoring_listen_addr=127.0.0.1:9981 --https_upstream=https://91.239.100.100/dns-query"
' >/etc/default/dnss
systemctl enable dnss

# Force DNS nameserver to 127.0.0.1 (for dnss):
echo '#!/bin/bash

# This script exists because there seems to be no config which prevents
# from trying to use Google servers, which are blocked in certain regions.

# stop the dnss daemon
systemctl stop dnss

# overwrite Network Managers auto-generated resolv.conf files
ADDR="nameserver 127.0.0.1"
DNS_SERV="91.239.100.100"
FILES=(/run/resolvconf/resolv.conf /run/resolvconf/interface/systemd-resolved /etc/resolv.conf)
IFACEDIR="/run/resolvconf/interfaces"

[[ -d "$IFACEDIR" ]] && rm -rf "$IFACEDIR"/*

for FILE in "${FILES[@]}";do
    [[ -f "$FILE" ]] && echo "$ADDR" > $FILE
done

sleep 0.5

# start dnss socket
dnss --enable_dns_to_https -https_upstream https://"$DNS_SERV"/dns-query
' >/etc/network/if-up.d/zz-resolvconf
chmod +x /etc/network/if-up.d/zz-resolvconf

# Install wireguard-tools from the git mirror:
# https://github.com/WireGuard/wireguard-tools
# Clone the repo, cd into wireguard-tools/src, execute make && make install
(
    git clone https://github.com/WireGuard/wireguard-tools
    cd wireguard-tools/src || exit
    make
    make -j4 install
)

###############################################################################
# START OF GENERIC / SKYWAVE PACKAGE INSTALLS (BASED ON DEBIAN WITH XFCE)
###############################################################################

# Map Caps Lock with ESC key (Get ESC when Caps Lock is pressed)
# Overwrite the file /etc/default/keyboard
echo '# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS="terminate:ctrl_alt_bksp,caps:escape"

BACKSPACE="guess"
' >/etc/default/keyboard

# set x11 resolution:
echo 'Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection' >/etc/X11/xorg.conf.d/99-screen-resolution.conf

# set up the touchpad:
echo 'Section "InputClass"
    Identifier "touchpad"
    MatchIsTouchpad "on"
    Driver  "libinput"
    Option  "Tapping"	"on"
    Option  "TappingButtonMap"	"lrm"
    Option  "NaturalScrolling"	"on"
    Option  "ScrollMethod"	"twofinger"
EndSection' >/etc/X11/xorg.conf.d/90-touchpad.conf

# Udev rules for the SDRplay driver
echo 'SUBSYSTEM=="usb",
ENV{DEVTYPE}=="usb_device",
ATTRS{idVendor}=="1df7",
ATTRS{idProduct}=="2500",
MODE:="0666"' > /etc/udev/rules.d/66-mirics.rules%0A

# create the /etc/environment file
echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"
LC_ALL="en_US.UTF-8"
LANG="en_US.UTF-8"
VISUAL="vi"
export VISUAL
EDITOR="$VISUAL"
export EDITOR
NO_AT_BRIDGE=1
export STARSHIP_CONFIG="/etc/xdg/starship/starship.toml"
PIPEWIRE_LATENCY=256/48000
export PIPEWIRE_LATENCY' >/etc/environment

# enforce sourcing of environmental variables
echo '# make sure key environmental variables are
# picked up in minimalist environments
[ -f /etc/profile ] && . /etc/profile
[ -f /etc/environment ] && . /etc/environmen
' >/etc/X11/Xsession.d/91x11_source_profile

# Set X11 to have a higher key repeat rate
echo '#!/bin/sh

exec /usr/bin/X -nolisten tcp -ardelay 400 -arinterval 17 "$@"
' >/etc/X11/xinit/xserverrc

# Install editors and other items:
PKGS="fzf ripgrep fd-find glow qalc shotcut default-jre default-jre-headless \
ffmpeg lsp-plugins chrony pandoc pandoc-citeproc poppler-utils p7zip ruby-dev \
picom rng-tools-debian haveged irssi newsboat zathura zathura-ps zathura-djvu \
zathura-cb odt2txt atool w3m mediainfo parallel thunar thunar-volman ristretto \
libmpv2 mpv mplayer firmware-misc-nonfree firmware-iwlwifi firmware-brcm80211 \
firmware-intel-graphics firmware-intel-misc firmware-marvell-prestera \
firmware-mediatek firmware-nvidia-graphics meld gnome-screenshot gnome-keyring \
cmake libgtk-3-common audacity shellcheck shfmt luarocks black ruff tidy \
yamllint pypy3 dconf-editor net-tools blueman sqlite3 sqlitebrowser dbus-x11 \
zlib1g-dev libxml2-dev libjansson-dev obs-studio filezilla htop fastfetch tmux \
rofi proxychains4 sshuttle tor torsocks obfs4proxy snowflake-client seahorse \
surfraw surfraw-extra usbreset yad lsp-plugins-vst squashfs-tools genisoimage \
syslinux-utils xorriso"
for PKG in $PKGS; do sudo apt -y install $PKG; done


# This is a separate group of packages specifically involving
# radio or other comms
# For Debian (and derivatives), see this page for SDR packages:
# https://blends.debian.org/hamradio/tasks/sdr

# Consider improved WSJT / JTDX:
# (not changing; the dev from "improved" is now dev'ing the main version)
# https://sourceforge.net/projects/wsjt-x-improved/
# http://dk5ew.com/2022/03/31/jtdx_improved/

# JS8Call
# https://js8call.com/

# install from the repos:
PKGS="fldigi gpredict libhamlib4 libhamlib-dev libairspy0 libairspy-dev \
libairspyhf1 libairspyhf-dev aptitude install libbladerf2 libbladerf-dev \
libhackrf0 libhackrf-dev limesuite liblimesuite-dev limesuite-udev \
libboost-filesystem-dev libboost-chrono-dev libboost-serialization-dev \
libboost-thread-dev multimon-ng qtel uhd-host cubicsdr wsjtx jtdx js8call \
soapysdr-tools libzmq3-dev libliquid-dev libconfig++-dev libglew2.2 libmirisdr4 \
libosmosdr0 librtlsdr2 libsoapysdr0.8 libuhd4.6.0 libwxgtk-gl3.2-1  \
soapyosmo-common0.8 soapysdr0.8-module-airspy soapysdr0.8-module-all \
soapysdr0.8-module-audio soapysdr0.8-module-bladerf soapysdr0.8-module-hackrf \
soapysdr0.8-module-lms7 soapysdr0.8-module-mirisdr soapysdr0.8-module-osmosdr \
soapysdr0.8-module-redpitaya soapysdr0.8-module-remote soapysdr0.8-module-rfspace \
soapysdr0.8-module-rtlsdr soapysdr0.8-module-uhd libfftw3-dev libglfw3-dev \
libvolk2-dev libzstd-dev libsoapysdr-dev libairspyhf-dev libiio-dev libad9361-dev \
librtaudio-dev libhackrf-dev gpsd gpsd-clients gpsd-tools libproj-dev libgeos-dev"
for PKG in $PKGS; do sudo apt -y install $PKG; done

# Create a link for acarsdec and other apps to find librtlsdr.so.0
ln -sf /usr/lib/x86_64-linux-gnu/librtlsdr.so.2 /usr/lib/x86_64-linux-gnu/librtlsdr.so.0

# Build libacars from source from: https://github.com/szpajder/libacars
# libacars requires zlib1g-dev libxml2-dev libjansson-dev

# Get SatDump:
# Debian Package or https://github.com/SatDump/SatDump#linux
# Do not get WxtoImg, Glrpt, or Noaa-apt


# lsp-plugins should be hidden, but are not.
# append code in the launchers
sed -i '$aHidden=true' /usr/share/applications/in.lsp_plug*.desktop

# Note: use xfce4-appearance-settings to configure themes, icons, and fonts.

# get useful python tools:
PKGS="python3-numpy python3-scipy python3-sympy python3-bs4 python3-sql \
python3-pandas python3-html5lib python3-seaborn python3-matplotlib python3-pep8 \
python3-ruff python3-ijson python3-lxml python3-aiomysql python3-astropy \
python3-metpy python3-h5netcdf python3-h5py python3-pynvim python3-neovim \
python3-ipython python3-pygame python3-scrapy python3-metpy python3-pyaudio \
python3-selenium python3-venv python3-virtualenv python3-virtualenvwrapper \
python3-nltk python3-numba python3-mypy python3-xmltodict python3-dask \
python3-sqlalchemy python3-soapysdr python3-folium"
for PKG in $PKGS; do sudo apt -y install $PKG; done

# use pip for packages not in the regular repos
# execute as a loop so broken packages don't break the whole process
PKGS="pandas-datareader \
polars duckdb flask sqlalchemy debconf sqlitebiter hq iq jq siphon sympad \
aria2p lastversion castero textblob vadersentiment jupyterlab jupyter-book \
jupyter-lsp jupytext cookiecutter bash_kernel ilua types-seaborn pandas-stubs \
sounddevice nomadnet rns lxmf chunkmuncher pyais libais lpais pillow pyModeS"
for PKG in $PKGS; do
    python3 -m pip install --upgrade --break-system-packages $PKG
done

# use pip for a beta version:
#python3 -m pip install --upgrade --break-system-packages --pre <packagename>

# Install Nodejs and associated packages:
# read latest info: https://github.com/nodesource/distributions
NODE_MAJOR=22
curl -fsSL https://deb.nodesource.com/setup_$NODE_MAJOR.x -o nodesource_setup.sh
chmod +x nodesource_setup.sh
./nodesource_setup.sh
apt install -y nodejs
# Test with: nodejs --version

# Use npm as the node package manager.
PKGS="prettier eslint_d jsonlint markdownlint readability-cli"
for PKG in $PKGS; do npm install -g $PKG; done

# Update node and prune cruft with:
npm update -g
npm prune

# Install yarn if desired
# npm install -g yarn

# install golang
# IMPORTANT:
# Updating golang will cause deletions of these:
#     gophernotes -- for Jupyterlab
#     gofmt  -- code formatter for Neovim
# See other notes for instructions to reinstall.
# The code below preserves current versions of gophernotes and gofmt
cp /usr/local/go/bin/{gofmt,gophernotes} /tmp/
wget -c "https://golang.org/dl/go1.21.1.linux-"$ARCH".tar.gz"
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.21.1.linux-"$ARCH".tar.gz
cp /tmp/{gofmt,gophernotes} /usr/local/go/bin/

# Add the following code to user's .profile:
# golang
# export GOROOT=/usr/local/go
# export GOPATH=$GOROOT
# export GOBIN=$GOPATH/bin
# export PATH=$PATH:$GOROOT

# Create symlink for gofmt
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Install Harper (English grammar checker)
(
    cd "$working_dir" || exit
    mkdir harper-ls
    cd harper-ls || exit
    wget -c https://github.com/Automattic/harper/releases/download/v"$HARP_VER"/harper-ls-"$ARCH2"-unknown-linux-gnu.tar.gz
    tar -xvzf --overwrite harper-ls-"$ARCH2"-unknown-linux-gnu.tar.gz
    chmod +x "$working_dir"/harper-ls/harper-ls
    ln -sf "$working_dir"/harper-ls/harper-ls /usr/local/bin/harper-ls
)

# Install the latest Neovim
(
    cd "$working_dir" || exit
    wget -c https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-"$ARCH2".tar.gz
    tar -xvzf --overwrite nvim-linux-"$ARCH2".tar.gz
    cd nvim-linux-"$ARCH2" || exit
    chown -R root:root ./*
    cp bin/* /usr/bin/
    cp -r share/{applications,icons,locale,man} /usr/share/
    rsync -avhc --delete --inplace --mkpath lib/nvim/ /usr/lib/nvim/
    rsync -avhc --delete --inplace --mkpath share/nvim/ /usr/share/nvim/

    # Install the Neovim configuration
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/nvim-configs
    cd nvim-configs || exit
    rsync -avhc --delete --inplace --mkpath nvim-minimal/ /root/.config/nvim/
    rsync -avhc --delete --inplace --mkpath nvim-minimal/ /etc/xdg/nvim/
    rsync -avhc --delete --inplace --mkpath nvim/ /home/"$USERNAME"/.config/nvim/
    chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.config/nvim/

    # get some npm and perl nvim assets
    npm install -g neovim
    curl -L https://cpanmin.us | perl - App::cpanminus
    cpanm Neovim::Ext
)

# Get dotfiles
printf "\nDownloading dot files"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/Dotfiles
    cd Dotfiles || exit
    DIRS=".bashrc.d .w3m"
    for DIR in $DIRS; do
        cp -r "$DIR" /home/"$USERNAME"/
    done

    FILES=".bashrc .fzf.bash .inputrc .nanorc .tmux.conf \
        .vimrc .wgetrc .Xresources"
    for FILE in $FILES; do
        cp "$FILE" /home/"$USERNAME"/
    done

    FOLDERS="alacritty dconf castero dunst networkmanager-dmenu newsboat \
        picom rofi wezterm sxhkd systemd zathura"
    for FOLDER in $FOLDERS; do
        cp -r "$FOLDER" /home/"$USERNAME"/.config/"$FOLDER"
    done

    XDGFOLDERS="alacritty wezterm dunst"
    for XDGFOLDER in $XDGFOLDERS; do
        cp -r "$XDGFOLDER" /etc/xdg/"$XDGFOLDER"
    done
)

# set up the menu / app launcher
printf "\n Setting up the menu / app launcher"
(
    echo '#!/bin/bash

rofi -i \
	-modi combi \
	-show combi \
    -combi-modi "window,drun" \
    -display-drun "" \
	-monitor -1 \
	-columns 2 \
	-show-icons \
	-drun-match-fields "exec" \
' >/usr/bin/run-rofi
    chmod +x /usr/bin/run-rofi
)

# install nerd fonts
(
    printf "\nInstalling Nerd Fonts"
    cd "$working_dir" || exit
    for FONTPKG in $FONTS; do
        aria2c -x5 -s5 \
            https://github.com/ryanoasis/nerd-fonts/releases/download/v"$FONT_VER"/"$FONTPKG"
        tar -xvJf "$FONTPKG" -C /usr/share/fonts/truetype
        rm "$FONTPKG"
    done
    fc-cache -fv
)

# install the git updater
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/Updater-for-Gits-Etc
    chmod +x Updater-for-Gits-Etc/getgits.sh
    ln -sf "$working_dir"/Updater-for-Gits-Etc/getgits.sh \
        "$working_dir"/getgits.sh
)

###############################################################################
# END OF GENERIC / SKYWAVE PACKAGE INSTALLS
###############################################################################

###############################################################################
# CONFIGURE JUPYTERLAB
###############################################################################
# NLTK needs extra data to work. Get it by using the Python REPL:
#  >>> import nltk
#  >>> nltk.download()
#  Navigate through the download settings:
#    d) Download --> c) Config -->
#    d) Set Data Dir ) and set the data download directory to
#      "/usr/share/nltk_data" then ( m) Main Menu --> q) Quit )
#  >>> nltk.download('popular')
#  >>> nltk.download('vader_lexicon')

# Textblob is also an NLP tool.

# For selenium, get the Firefox (gecko) webdriver from:
# https://github.com/mozilla/geckodriver
# The latest chromedriver can be downloaded from
# https://googlechromelabs.github.io/chrome-for-testing/
# Keep the actual executable at /usr/local/src/chromedriver-linux64/chromedriver
# and symlink to /usr/bin/chromedriver
# Check either driver by calling with the --version argument

# The path is FUBAR for each of {flake8,isort,yapf}:
# Fixed with wrappers (little bash scripts which execute the Python):
#  /usr/local/bin/flake8 containing "python -m flake8"
#  /usr/local/bin/isort containing "python -m isort"
#  /usr/local/bin/yapf containing "python -m yapf"

# The Bash kernel is in package bash_kernel
# Complete insallation with:
python3 -m bash_kernel.install

# The Lua kernel is in package ilua
# Just pip install; no further action needed

# Add go kernel to jupyterlab
# use gophernotes, placed binary in /usr/local/go/bin/
# kernel files in /usr/local/share/jupyter/kernels/gophernotes
# kernel.json has full path to the gophernotes binary
mkdir -p "$(go env GOPATH)"/src/github.com/gopherdata
(
    cd "$(go env GOPATH)"/src/github.com/gopherdata || exit
    git clone https://github.com/gopherdata/gophernotes
    cd gophernotes || exit
    git checkout -f v0.7.5
    go install
    mkdir -p ~/.local/share/jupyter/kernels/gophernotes
    cp kernel/* ~/.local/share/jupyter/kernels/gophernotes
    cd ~/.local/share/jupyter/kernels/gophernotes || exit
    chmod +w ./kernel.json # in case copied kernel.json has no write permission
    sed "s|gophernotes|$(go env GOPATH)/bin/gophernotes|" <kernel.json.in >kernel.json
)

# Add typescript and javascript kernels to Jupyterlab
npm install -g tslab
tslab install --python=python3

# As desired, verify that the kernels are installed
# jupyter kernelspec list

# Remove redundant ijavascript Kernel
npm uninstall -g --unsafe-perm ijavascript
npm uninstall ijavascript

# Add language server extension to Jupyterlab
python3 -m pip install jupyter-lsp
# old method (deprecated): jupyter labextension install @krassowski/jupyterlab-lsp
# old method (deprecated): jupyter labextension uninstall @krassowski/jupyterlab-lsp

# If installed, remove unified-language-server, vscode-html-languageserver-bin

# After finishing all other work on Jupyterlab, rebuild it.
jupyter-lab build

################################################################################
# WINDOW MANAGERS
###############################################################################

# Remove xfce, bloat, and some Wayland apps I had installed...
# Don't replace lightdm with sddm (draws in too much KDE)
PKGS="lightdm* liblightdm* lightdm-gtk-greeter light-locker sddm* gdm xfce* \
libxfce* xfburn xfconf xfdesktop4 parole sway swaybg waybar greybird-gtk-theme \
yelp timeshift dosbox grsync remmina wofi kwayland geoclue* \
gnome-accessibility-themes gnome-desktop3-data gnome-icon-theme gnome-menus \
gnome-settings-daemon gnome-settings-daemon-common gnome-system* systemsettings"
for PKG in $PKGS; do sudo apt -y autoremove --purge $PKG; done

# For Wayland / Sway
# Sway Components to install:
# sway swaybg sway-notification-center waybar xwayland nwg-look

# For screenshots in Sway:
# Get the grimshot script
# https://github.com/swaywm/sway/blob/master/contrib/grimshot
# apt install grim slurp

# Make the clipboard functional
# apt install wl-clipboard clipman

# Here is some sway config code:
# configure clipboard functions:
# exec wl-paste -t text --watch clipman store
# exec wl-paste -p -t text --watch clipman store -P --histpath="~/.local/share/clipman-primary.json"
# acces the history with a keybind:
# bindsym $mod+h exec clipman pick -t wofi
# clear the clipboard with:
# bindsym Sshift+$mod+h exec clipman clear --all

###############################################################################
# For Awesomewm:
# nala install -y awesome awesome-extra

###############################################################################
# For DWM:
# install dependencies DWM and the patches
# apt install libxft-dev libx11-dev libxinerama-dev libxcb-xkb-dev \
#    libx11-xcb-dev libxcb-res0-dev libxcb-xinerama0

# install DWM
# Download the latest release from suckless.org and extract it.
# Place the folder in /usr/local/src

# patch DWM
# example command: patch -p1 < dwm-my-new-patch.diff
# actual patches used:
#    alwayscenter
#    attachbottom
#    pertag
#    scratchpads
#    swallow
#    vanity gaps

### USE DWM-FLEXIPATCH ###
# After getting the patches to work well together, save a
# diff file for these:
#    config.def.h
#    config.mk
#    patches.def.h
#
#
# Here is a command to save the patch:
# (one file)    diff -u orig.config.def.h latest.config.def.h > config.patch
# (directories) diff -rubN original/ new/ > rockdove.patch

# Uncomment some lines in config.mk:
#     # uncomment near line 32:
#     XRENDER = -lXrender
#     # uncomment near line 49
#     XCBLIBS = -lX11-xcb -lxcb -lxcb-res

# Make the binary with:  rm config.h; make clean; make

# A complete DWM setup is available through git:
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/dwm-flexipatch
    git clone https://github.com/AB9IL/dwm-bar

    # Simlink the dwm binary to /usr/local/bin/dwm
    ln -sf "$working_dir"/dwm-flexipatch/dwm /usr/local/bin/dwm
)

# Install the .profile and .xinitrc files
(
    cd "$working_dir"/Dotfiles || exit
    FILES=".profile .xinitrc"
    for FILE in $FILES; do
        cp "$FILE" /home/"$USERNAME"/
    done
)

# Configure some systemd items as necessary
# Check the default target with:
systemctl get-default

# If it is "geaphical.target" then set it to "multiuser.target":
# systemctl set-default multi-user.target

# For X11 window managers, create a systemd unit file to reliably start X
echo '[Unit]
Description=Start X11 for the user
After=network.target

[Service]
Environment=DISPLAY=:0
ExecStart=/usr/bin/startx %h/.xinitrc
Restart=on-failure

[Install]
WantedBy=default.target
' >/etc/systemd/user/startx.service

# Create the enabling symlink for the normal user:
mkdir -p /home/"$USERNAME"/.config/systemd/user/default.target.wants
ln -sf /etc/systemd/user/startx.service \
    /home/"$USERNAME"/.config/systemd/user/default.target.wants/startx.service

# Alternatively, as the normal user (not root or sudo):
# reload the daemon, enable, and activate
# systemctl --user daemon-reload
# systemctl --user enable startx.service
# systemctl --user start startx.service

# make sure the user owns newly created items in the home folder
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"

###############################################################################
# END WINDOW MANAGERS
###############################################################################

#set the cpu governor
echo 'GOVERNOR="performance"' >/etc/default/cpufrequtils

# configure rng-tools
sed -i "11s/.*/HRNGDEVICE=/dev/urandom/" /etc/default/rng-tools

# configure rng-tools-debian
sed -i "s|^.*\#HRNGDEVICE=/dev/null|HRNGDEVICE=/dev/urandom/|" /etc/default/rng-tools-debian

# Create a script for items to set up during boot time:
echo '#!/bin/bash

# usbfs memory
echo 0 > /sys/module/usbcore/parameters/usbfs_memory_mb

# set clocksource
# Note: timer freqs in /etc/sysctl.conf
echo "tsc" > /sys/devices/system/clocksource/clocksource0/current_clocksource

#configure for realtime audio
echo '@audio - rtprio 95
@audio - memlock 512000
@audio - nice -19' > /etc/security/limits.d/10_audio.conf
' >/usr/sbin/startup-items

# make the script executable:
chmod +x /usr/sbin/startup-items

# Set up a a systemd unit for startup-items:
echo '[Unit]
Description=Startup Items and Debloat Services
After=getty.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/startup-items

[Install]
WantedBy=default.target
' >/etc/systemd/system/startup-items.service

# Enable by creating a symlink to the unit (accomplish manually or with systemctl enable <unit name>)
ln -sf /etc/systemd/user/startup-items.service \
    /etc/systemd/system/default.target.wants/startup-items.service

# Create a script to accomplish tasks immediately prior to
# starting the graphical environment.
echo '#!/bin/bash

# copy skel to home because live build stopped doing it
cp -r /etc/skel/. /home/user/
chown -R user:user /home/user

# fix a potential driver issue causing xserver to fail
setcap CAP_SYS_RAWIO+eip /usr/lib/xorg/Xorg
' >/usr/sbin/session-items

# Create a systemd service for session-itsms:
echo '[Unit]
Description=Session-items before window manager
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/session-items

[Install]
WantedBy=default.target
' >/etc/systemd/system/session-items.service

# Enable by creating a symlink to the unit (accomplish manually or with systemctl enable <unit name>)
ln -sf /etc/systemd/user/session-items.service \
    /etc/systemd/system/default.target.wants/session-items.service

# Move some environmental variables out of ~/.profile and into the realm
# of systemd:
mkdir -p /etc/systemd/user/environment.d
echo '[User]
Environment="BROWSER=x-www-browser"
Environment="BROWSERCLI=w3m"
Environment="PISTOL_CHROMA_FORMATTER=terminal256"
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="PIPEWIRE_LATENCY=256/48000"
' >/etc/systemd/user/environment.d/environment.conf

# Note that these are persistent, not reset on user login.

# The systemd units listed above are helpful, but the pivotal change was
# resetting the default target away from "graphical.target" and back to
# "multi-user.target" since we do not run a display manager.
#
# Check the default target with:
# systemctl get-default

# If it is "geaphical.target" then set it to "multiuser.target":
# systemctl set-default multi-user.target

###############################################################################
# INSTALL ACCESSORIES
###############################################################################
printf "\nInstalling some accessories"

# Do most of the work from /usr/local/src
cd "$working_dir" || exit

# install obsidian
printf "\nInstalling Obsidian"
(
    aria2c -x5 -s5 \
        https://github.com/obsidianmd/obsidian-releases/releases/download/v"$OBSIDIAN_VER"/obsidian_"$OBSIDIAN_VER"_"$ARCH".deb
    dpkg -i obsidian*.deb
    rm obsidian*.deb
)

# apt install brightnessctl light

# install pipewire
# See the guide: https://trendoceans.com/install-pipewire-on-debian-11/
nala install -y pipewire pipewire-audio-client-libraries pipewire-jack

# Setting up Wezterm as the main terminal emulator:
# - create a new alternative for x-terminal-emulator
#   update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/wezterm 60
# - then:
#   update-alternatives --config editor
# - Select "wezterm" (not "open-wezterm-here"
# - use either syntax to launch apps in the terminal:
#   x-terminal-emulator -e <app-command>
#   x-terminal-emulator start -- <app-cammand>

# Install Rclone
printf "\nInstalling rclone"
(
    cd "$working_dir" || exit
    curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip rclone-current-linux-amd64.zip -d rclone-current-linux-amd64
    rm rclone-current-linux-amd64.zip
    cd rclone-current-linux-amd64 || exit
    cp rclone /usr/bin/
    chmod 755 /usr/bin/rclone
    mkdir -p /usr/local/share/man/man1
    cp rclone.1 /usr/local/share/man/man1/
    mandb
)

# Install rclone Browser
# AppImage: https://github.com/kapitainsky/RcloneBrowser
# ( https://github.com/kapitainsky/RcloneBrowser/releases/download/1.8.0/rclone-browser-1.8.0-a0b66c6-linux-"$ARCH2".AppImage )

###############################################################################
# FLATPAK - PACSTALL - MAKEDEB
###############################################################################
printf "\nInstalling alternative software installers: Flatpak / Pacstall / Makedeb"

# Install Flatpak
apt install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Pacstall
# bash -c "$(curl -fsSL https://pacstall.dev/q/install)"

# Optional: install makedeb and get software from makedeb.org
# Must install and make debs as normal user
# You may install the deb packages as root
# bash -ci "$(wget -qO - 'https://shlink.makedeb.org/install')"

# rsynced skywave nvim with debian nvim
# Install the Python support for Neovim:
# apt install python3-neovim python3-pynvim
# (use pip if the repos don't have them)
#
# Install Ruby support for Neovim:
# gem install neovim
#
# Set up Perl support for Neovim:
# curl -L https://cpanmin.us | perl - App::cpanminus
# cpanm Neovim::Ext;
#
# for Lua formatting, install Stylua binary from:
# https://github.com/JohnnyMorganz/Stylua/releases
#
# - get luacheck: apt install luarocks; luarocks install luacheck
# - get shellcheck and shfmt: apt install shellcheck shfmt
# - get black, python3-ruff, and ruff: apt install black python3-ruff ruff
# - get markdownlint: apt install ruby-mdl
# - get golangci_lint: https://github.com/golangci/golangci-lint/releases/

# Install Brave Browser
printf "\nInstalling Brave Browser"
# The deb package is available on GitHub: https://github.com/brave/brave-browser/releases
curl -fsSLo /usr/share/keyrings/brave-browser-beta-archive-keyring.gpg https://brave-browser-apt-beta.s3.brave.com/brave-browser-beta-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-beta-archive-keyring.gpg] https://brave-browser-apt-beta.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser-beta.list
apt update
apt install -y brave-browser-beta

# Plugins for GIMP
# Install GMIC and Elsamuko scripts and GIMP plugins!
# Note: may need a workaround because gimp-gmic cannot be installed
# Install LinuxBeaver's GEGL plugins for GIMP
# Download, extract, and copy to proper directory as per instructions.

# Install Cyan (converts CMYK color profiles better than GIMP)
(
    cd "$working_dir" || exit
    aria2c -x5 -s5 \
        https://github.com/rodlie/cyan/releases/download/"$CYAN_VER"/Cyan-"$CYAN_VER"-Linux-"$ARCH2".tgz
    tar -xvzf --overwrite Cyan*.tgz
    mv Cyan*/* cyan/
    rm -r Cyan*
    chmod +x cyan/Cyan
    ln -sf "$working_dir"/cyan/Cyan \
        /usr/local/bin/Cyan
)

# Install Lazygit
(
    cd "$working_dir" || exit
    mkdir lazygit
    aria2c -x5 -s5 \
        https://github.com/jesseduffield/lazygit/releases/download/v"$LAZYGIT_VER"/lazygit_"$LAZYGIT_VER"_Linux_"$ARCH2".tar.gz
    tar -xvzf --overwrite lazygit_* -C lazygit/
    rm lazygit_*.tar.gz
    chmod +x lazygit/lazygit
    ln -sf "$working_dir"/lazygit/lazygit \
        /usr/local/bin/lazygit
)

# Install Reticulum Meshchat
printf "\nInstalling Reticulum Meshchat"
# The meshchat appimage is large - over 150 MB !!
# Consider the CLI option for meshchat:
# https://github.com/liamcottle/reticulum-meshchat
mkdir /opt/reticulum
(
    cd /opt/reticulum || exit
    aria2c -x5 -s5 \
        https://github.com/liamcottle/reticulum-meshchat/releases/download/"$MeshChatVersion"/ReticulumMeshChat-"$MeshChatVersion"-linux.AppImage
    chmod +x ReticulumMeshChat*
)

# create a meshchat launcher:
echo '[Desktop Entry]
Type=Application
Name=Reticulum Meshchat
GenericName=Reticulum Mesh Chat
Comment=Mesh network communications powered by the Reticulum Network Stack.
Exec=/opt/reticulum/ReticulumMeshChat.AppImage
Icon=reticulum-meshchat.ico
Terminal=false
Categories=Network;
Keywords=network;chat;meshchat;meshnet;
' >/home/"$USERNAME"/.local/share/applications/reticulum-meshchat.desktop

# Install the radiostreamer and create a launcher
printf "\nInstalling the Internet Radio Streamer"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/radiostreamer
    chmod +x "$working_dir"/radiostreamer/radiostreamer
    chmod 664 "$working_dir"/radiostreamer/radiostreams
    ln -sf "$working_dir"/radiostreamer/radiostreamer /usr/local/bin/radiostreamer
    ln -sf "$working_dir"/radiostreamer/radiostreams /home/"$USERNAME"/.config/radiostreams

    # create a radiostreamer launcher:
    echo '[Desktop Entry]
Version=1.0
Name=Internet Radio Playlist
GenericName=Internet Radio Playlist
Comment=Open an internet radio stream
Exec=radiostreamer gui
Icon=radio-icon
Terminal=false
Type=Application
Categories=AudioVideo;Player;Recorder;Network
' >/home/"$USERNAME"/.local/share/applications/radiostreamer.desktop
)

# Install networkmanager-dmenu
(
    cd "$working_dir" || exit
    git clone https://github.com/firecat53/networkmanager-dmenu
    chmod +x networkmanager-dmenu/networkmanager_dmenu
    ln -sf "$working_dir"/networkmanager-dmenu/networkmanager_dmenu \
        /usr/local/bin/networkmanager_dmenu

    # create a launcher:
    echo '[Desktop Entry]
Version=1.0
Name=Network Manager with Dmenu
GenericName=Manage network connections.
Comment=Manage network connections.
Exec=networkmanager_dmenu
Icon=preferences-system-network
Terminal=false
Type=Application
Categories=System;NetworkSettings;
' >/home/"$USERNAME"/.local/share/applications/networkmanager-dmenu.desktop
)

# Install Dyatlov Mapmaker (SDR Map)
printf "\nInstalling Dyatlov Mapmaker (SDR Map)"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/dyatlov
    chown -R "$USERNAME":"$USERNAME"/dyatlov
    chmod +x dyatlov/kiwisdr_com-parse
    chmod +x dyatlov/kiwisdr_com-update

    # create a launcher:
    echo '[Desktop Entry]
Version=1.0
Name=SDR-Map
GenericName=Map of internet software defined radio
Comment=Map of internet software defined radios
Exec=supersdr-wrapper --map
Icon=globe-icon
Terminal=false
Type=Application
StartupNotify=true
Categories=AudioVideo;Player;Network;
' >/home/"$USERNAME"/.local/share/applications/sdr-map.desktop
)

# Install SuperSDR
printf "\nInstalling SuperSDR"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/supersdr
    chown -R "$USERNAME":"$USERNAME"/supersdr
    chmod +x supersdr/supersdr.py
    # create a launcher:
    echo '[Desktop Entry]
Name=SuperSDR-Bookmarks
GenericName=Stream favorite radio stations via software defined radio.
Comment=Stream favorites on internet software defined radio.
Exec=supersdr-wrapper --bookmarks --gui
Icon=radio-icon
Terminal=false
Type=Application
StartupNotify=true
Categories=AudioVideo;Player;Network;
' >/home/"$USERNAME"/.local/share/applications/supersdr-bookmarks.desktop

    # create a launcher:
    echo '[Desktop Entry]
Name=SuperSDR-Kill
GenericName=SuperSDR Kill Frozen App
Comment=Kill SuperSDR if frozen.
Exec=supersdr-wrapper --kill
Icon=/usr/local/src/supersdr/icon.jpg
Terminal=false
Type=Application
Categories=HamRadio;
StartupNotify=true
' >/home/"$USERNAME"/.local/share/applications/supersdr-kill.desktop

    # create a launcher:
    echo '[Desktop Entry]
Name=SuperSDR-Servers
GenericName=SuperSDR Client for KiwiSDR and Web-888 servers.
Comment=Select favorite KiwiSDR and Web-888 servers.
Exec=supersdr-wrapper --servers --gui
Icon=/usr/local/src/supersdr/icon.jpg
Terminal=false
Type=Application
Categories=HamRadio;
StartupNotify=true
' >/home/"$USERNAME"/.local/share/applications/supersdr-servers.desktop
)

# Install SuperSDR-Wrapper
printf "\nInstalling SuperSDR-Wrapper"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/supersdr-wrapper
    chown -R "$USERNAME":"$USERNAME" supersdr-wrapper/kiwidata
    chmod +x supersdr-wrapper/stripper
    chmod +x supersdr-wrapper/supersdr-wrapper
    ln -sf "$working_dir"/supersdr-wrapper/kiwidata \
        "$working_dir"/kiwidata
    ln -sf "$working_dir"/supersdr-wrapper/stripper \
        /usr/local/bin/stripper
    ln -sf "$working_dir"/supersdr-wrapper/supersdr-wrapper \
        /usr/local/bin/supersdr-wrapper
)

# Install Bluetabs
printf "\nInstalling Bluetabs"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/bluetabs
    chmod +x bluetabs/bluetabs
    ln -sf "$working_dir"/bluetabs/bluetabs \
        /usr/local/bin/bluetabs
    ln -sf "$working_dir"/bluetabs/tw_alltopics \
        /home/"$USERNAME"/.config/tw_alltopics

    # create a launcher:
    echo '[Desktop Entry]
Version=1.0
Name=Bluetabs
GenericName=Watch multiple Microblog feeds at once.
Comment=Watch multiple Microblog feeds at once.
Exec=bluetabs gui
Icon=twitgrid
Terminal=false
Type=Application
Categories=Networking;Internet;
' >/home/"$USERNAME"/.local/share/applications/bluetabs.desktop
)

# Install glow-wrapper
printf "\nInstalling glow-wrapper"
(
    echo '#!/bin/bash

x-terminal-emulator -e glow -p "$1"
read line' >/usr/local/bin/glow-wrapper
    chmod +x /usr/local/bin/glow-wrapper
)

# Install Linux-clone script
printf "Installing Linux-clone script"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/linux-clone
    chmod +x "$working_dir"/linux-clone/linux-clone
    ln -sf "$working_dir"/linux-clone/linux-clone \
        /usr/local/bin/linux-clone
)

# Install menu-surfraw
printf "Installing Menu-Surfraw"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/surfraw-more-elvis
    rsync -av --exclude='LICENCE' --exclude='README.md' \
        "$working_dir"/surfraw-more-elvis/ \
        /usr/lib/surfraw/
    chmod +x /usr/lib/surfraw/
    git clone https://github.com/AB9IL/menu-surfraw
    chmod +x menu-surfraw/menu-surfraw
    ln -sf "$working_dir"/menu-surfraw/menu-surfraw \
        /usr/local/bin/menu-surfraw

    # create a launcher:
    echo '[Desktop Entry]
Version=1.0
Name=Surfraw Web Search
GenericName=Surfraw Web Search
Name[en_US]=Surfraw Web Search
Comment=Find web content using Rofi and Surfraw.
Exec=menu-surfraw
Icon=edit-find
Terminal=false
Type=Application
Categories=Internet;Web;' >/home/"$USERNAME"/.local/share/applications/search.desktop
)

# Install circumventionist scripts
# Must do this before the proxy and vpn scripts
printf "Installing Circumventionist-scripts"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/circumventionist-scripts
)

# Install brave-with-proxy and firefox-with-proxy
printf "\nInstalling browser proxifier scripts"
(
    cd "$working_dir" || exit
    chmod +x circumventionist-scripts/brave-with-proxy
    ln -sf "$working_dir"/circumventionist-scripts/brave-with-proxy \
        /usr/local/bin/brave-with-proxy
    chmod +x circumventionist-scripts/firefox-with-proxy
    ln -sf "$working_dir"/circumventionist-scripts/firefox-with-proxy \
        /usr/local/bin/firefox-with-proxy
)

# Install lf file manager
printf "\nInstalling lf command line file manager"
(
    cd "$working_dir" || exit
    mkdir lf_linux_amd64
    cd lf_linux_"$ARCH" || exit
    aria2c -x5 -s5 \
        https://github.com/gokcehan/lf/releases/download/r"$LF_VER"/lf-linux-"$ARCH".tar.gz
    tar -xvzf --overwrite lf*.gz
    chmod +x lf
    rm lf*.gz
    cd "$working_dir" || exit
    ln -sf "$working_dir"/lf_linux_"$ARCH"/lf \
        /usr/local/bin/lf
    mkdir /etc/lf
    cp Dotfiles/lfrc /etc/lf/lfrc

    # create a launcher:
    echo '[Desktop Entry]
Type=Application
Name=lf
Name[en]=lf
GenericName=Terminal file manager.
Comment=Terminal file manager.
Icon=utilities-terminal
Exec=lf
Terminal=true
Categories=files;browser;manager;
' >/home/"$USERNAME"/.local/share/applications/lf.desktop
)

# Install pistol file previewer
(
    cd "$working_dir" || exit
    aria2c -x5 -s5 \
        https://github.com/doronbehar/pistol/releases/download/v0.5.2/pistol-static-linux-x86_64
    mkdir pistol
    mv pistol-* pistol/pistol
    chmod +x pistol/pistol
    ln -sf "$working_dir"/pistol/pistol \
        /usr/local/bin/pistol
)

# Install VPNGate client and scripts
printf "\nInstalling VPNGate client and scripts"
(
    cd "$working_dir" || exit
    mkdir vpngate
    cd vpngate || exit
    aria2c -x5 -s5 \
        https://github.com/davegallant/vpngate/releases/download/v"$VPNGateVersion"/vpngate_"$VPNGateVersion"_linux_"$ARCH".tar.gz
    tar -xvzf --overwrite vpn*.gz
    cd "$working_dir" || exit
    chmod +x vpngate/vpngate
    rm vpngate/vpn*.gz
    ln -sf "$working_dir"/vpngate/vpngate \
        /usr/local/bin/vpngate

    # make executable and symlink
    chmod +x circumventionist-scripts/dl_vpngate
    ln -sf "$working_dir"/circumventionist-scripts/dl_vpngate \
        /usr/local/bin/dl_vpngate

    # make executable and symlink
    chmod +x circumventionist-scripts/menu-vpngate
    ln -sf "$working_dir"/circumventionist-scripts/menu-vpngate \
        /usr/local/bin/menu-vpngate

    # create a launcher:
    echo '[Desktop Entry]
Name[en_US]=VPNGate Download
Name=VPNGate Download
GenericName=Download VPNGate OpenVPN configs.
Comment[en_US]=Download VPNGate OpenVPN configs.
Icon=vpngate
Exec=dl_vpngate 50
Type=Application
Terminal=false
' >/home/"$USERNAME"/.local/share/applications/dl_vpngate.desktop

    # create a launcher:
    echo '[Desktop Entry]
Name[en_US]=VPNGate Connect
Name=VPNGate Connect
GenericName=Manage VPNGate (OpenVPN) connections.
Comment[en_US]=Manage VPNGate (OpenVPN) connections.
Icon=vpngate
Exec=menu-vpngate
Type=Application
Terminal=false
' >/home/"$USERNAME"/.local/share/applications/vpngate.desktop
)

# Install proxy fetchers
printf "\nInstalling proxy fetchers"
(
    cd "$working_dir" || exit
    git clone https://github.com/stamparm/fetch-some-proxies
    chmod +x fetch-some-proxies/fetch.py
    git clone https://github.com/AB9IL/fzproxy
    chmod +x fzproxy/fzproxy
    ln -sf "$working_dir"/fzproxy/fzproxy \
        /usr/local/bin/fzproxy
    cp "$working_dir"/fzproxy/proxychains4.conf \
        /etc/
)

# Install Menu-Wireguard
printf "\nInstalling Menu-Wireguard"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/menu-wireguard
    chmod +x menu-wireguard/menu-wireguard
    ln -sf "$working_dir"/menu-wireguard/menu-wireguard \
        /usr/local/bin/menu-wireguard

    # create a launcher:
    echo '[Desktop Entry]
Name[en_US]=Wireguard
GenericName=Manage Wireguard VPN connections.
Name=wireguard
Comment[en_US]=Manage Wireguard VPN connections.
Icon=wireguard
Exec=sudo menu-wireguard gui
Type=Application
Terminal=false
' >/home/"$USERNAME"/.local/share/applications/wireguard.desktop
)

# Install OpenVPN-controller
printf "\nInstalling OpenVPN Connection Manager"
(
    cd "$working_dir" || exit
    chmod +x "$working_dir"/circumventionist-scripts/openvpn-controller.sh
    ln -sf "$working_dir"/circumventionist-scripts/openvpn-controller.sh \
        /usr/local/bin/openvpn-controller.sh
)

# Install Sshuttle controller
printf "\Installing Sshuttle controller"
(
    cd "$working_dir" || exit
    chmod +x "$working_dir"/circumventionist-scripts/sshuttle-controller
    ln -sf "$working_dir"/circumventionist-scripts/sshuttle-controller \
        /usr/local/bin/sshuttle-controller
)

# Install Tor-Remote
printf "\nInstalling Tor-Remote"
(
    cd "$working_dir" || exit
    chmod +x "$working_dir"/circumventionist-scripts/tor-remote
    ln -sf "$working_dir"/circumventionist-scripts/tor-remote \
        /usr/local/bin/tor-remote
)

# Install Starship prompt
printf "\nInstalling Starship prompt"
(
    cd "$working_dir" || exit
    mkdir starship
    aria2c -x5 -s5 \
        https://github.com/starship/starship/releases/download/v"$STARSH_VER"/starship-"$ARCH2"-unknown-linux-gnu.tar.gz
    tar -xvzf --overwrite starship-*.gz -C starship/
    chmod +x starship/starship
    ln -sf "$working_dir"/starship/starship \
        /usr/local/bin/starship
    cp Dotfiles/starship.toml /home/"$USERNAME"/.config/
    rm starship-*.gz
)

# Install system scripts (Catbird == Skywave)
printf "Installing system scripts"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/Catbird-Linux-Scripts

    # system exit or shutdown
    chmod +x Catbird-Linux-Scripts/system-exit
    ln -sf "$working_dir"/Catbird-Linux-Scripts/system-exit \
        /usr/local/bin/system-exit

    # usb reset utility
    chmod +x Catbird-Linux-Scripts/usbreset-helper
    ln -sf "$working_dir"/Catbird-Linux-Scripts/usbreset-helper \
        /usr/local/bin/usbreset-helper
    cp Catbird-Linux-Scripts/system.rasi \
        /usr/share/rofi/themes/system.rasi

    # create a launcher
    echo '[Desktop Entry]
Version=1.0
Name=System Shutdown
GenericName=Log out or shut down the computer.
Comment=Log out or shut down the computer.
Exec=system-exit
Icon=system-shutdown
Terminal=false
Type=Application
Categories=System;Shutdown;
' >/home/"$USERNAME"/.local/share/applications/shutdown.desktop

    # locale manager
    chmod +x Catbird-Linux-Scripts/locale-manager
    ln -sf "$working_dir"/Catbird-Linux-Scripts/locale-manager \
        /usr/local/bin/locale-manager

    # create a launcher
    echo '[Desktop Entry]
Type=Application
Name=Locale Manager
Name[en]=Locale Manager
GenericName=Change system languages and locales.
Comment=Change system languages and locales.
Icon=utilities-terminal
Exec=locale-manager
Terminal=false
Categories=Language;System
' >/home/"$USERNAME"/.local/share/applications/locale-manager.desktop

    # Install make-podcast script
    chmod +x Catbird-Linux-Scripts/make-podcast
    ln -sf "$working_dir"/Catbird-Linux-Scripts/make-podcast \
        /usr/local/bin/make-podcast

    # Install make-screencast script
    chmod +x Catbird-Linux-Scripts/make-screencast
    ln -sf "$working_dir"/Catbird-Linux-Scripts/make-screencast \
        /usr/local/bin/make-screencast

    # Install note-sorter script
    chmod +x Catbird-Linux-Scripts/note-sorter
    ln -sf "$working_dir"/Catbird-Linux-Scripts/note-sorter \
        /usr/local/bin/note-sorter
    ln -sf "$working_dir"/Catbird-Linux-Scripts/note-sorter \
        /usr/local/bin/vimwiki

    # create a launcher
    echo '[Desktop Entry]
Type=Application
Name=Note Sorter
Name[en]=Note Sorter
GenericName=Search and sort your notes.
Comment=Search and sort markdown notes.
Icon=utilities-terminal
Exec=note-sorter
Terminal=true
Categories=Text;Editor;Programming
MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
' >/home/"$USERNAME"/.local/share/applications/note-sorter.desktop

    # Set up Roficalc
    chmod +x Catbird-Linux-Scripts/roficalc
    ln -sf "$working_dir"/Catbird-Linux-Scripts/roficalc \
        /usr/local/bin/roficalc

    # create a launcher for roficalc
    echo '[Desktop Entry]
Type=Application
Name=Roficalc
Name[en]=Roficalc
GenericName=Rofi Calculator
Comment=Do mathematical calculations in Rofi.
Icon=utilities-terminal
Exec=roficalc
Terminal=false
Categories=Text;Calculator;Programming
' >/home/"$USERNAME"/.local/share/applications/roficalc.desktop

    # set the desktop wallpaper
    ln -sf "$working_dir"/Catbird-Linux-Scripts/wallpaper.png \
        /usr/share/backgrounds/wallpaper.png
)

# create a launcher for castero
echo '[Desktop Entry]
Type=Application
Name=Castero
Name[en]=Castero
GenericName=Podcast player
Comment=Terminal podcast player
Icon=utilities-terminal
Exec=castero
Terminal=true
Categories=Network;Internet;
' >/home/"$USERNAME"/.local/share/applications/castero.desktop

# create a launcher for irssi
echo '[Desktop Entry]
Type=Application
Name=irssi
Name[en]=irssi
GenericName=Terminal IRC client.
Comment=Terminal IRC client.
Icon=utilities-terminal
Exec=irssi
Terminal=true
Categories=Network;Internet;
' >/home/"$USERNAME"/.local/share/applications/irssi.desktop

# create a launcher for newsboat
echo '[Desktop Entry]
Type=Application
Name=Newsboat
Name[en]=Newsboat
GenericName=Terminal RSS reader
Comment=Terminal RSS / Atom reader.
Icon=utilities-terminal
Exec=newsboat
Terminal=true
Categories=Network;Internet;
' >/home/"$USERNAME"/.local/share/applications/newsboat.desktop

# Install Python-tgpt
printf "\nInstalling Python-tgpt"

# Reference https://pypi.org/project/python-tgpt/
# Manually delete the old tgpt symlink and binary.
# Use uv pip install and set a virtual environment in /opt.
mkdir /opt/python-tgpt
uv venv /opt/python-tgpt

# edit /opt/python-tgpt/pyenv.cfg to allow use of system site packages:
sed -i "s/include-system-site-packages = false/include-system-site-packages = true/" /opt/python-tgpt/pyenv.cfg

# install python-tgpt
source /opt/python-tgpt/bin/activate
uv pip install python-tgpt

# Start a session with:
# pytgpt interactive "<Kickoff prompt (though not mandatory)>"

# Terminate the session with:
# exit

# Deactivate the virtual environment with:
# deactivate

# Set up the wrapper script to accomplish activation,
# running, and deactivation of python-tgpt.
chmod +x "$working_dir"/Catbird-Linux-Scripts/pytgpt-wrapper
ln -sf "$working_dir"/Catbird-Linux-Scripts/pytgpt-wrapper \
    /usr/local/bin/pytgpt-wrapper
chmod +x /usr/local/bin/pytgpt-wrapper

# create a launcher for python-tgpt
echo '[Desktop Entry]
Type=Application
Name=Terminal GPT
Name[en]=pyTerminal GPT
GenericName=pyTerminal GPT Chatbots.
Comment=Access AI chatbots from the terminal.
Icon=utilities-terminal
Exec=pytgpt-wrapper
Terminal=true
Categories=ai;gpt;browser;chatbot;
' >/home/"$USERNAME"/.local/share/applications/pytgpt.desktop

# create the providers list
echo 'phind
auto
openai
koboldai
blackboxai
gpt4all
g4fauto
poe
groq
perplexity
novita
ai4chat
AI365VIP
AIChatFree
AIUncensored
ARTA
Acytoo
AiAsk
AiChatOnline
AiChats
AiService
Aibn
Aichat
Ails
Airforce
Aivvm
AllenAI
AmigoChat
Anthropic
AsyncGeneratorProvider
AsyncProvider
Aura
AutonomousAI
BackendApi
BaseProvider
Berlin
BingCreateImages
BlackForestLabsFlux1Dev
BlackForestLabsFlux1Schnell
Blackbox
CablyAI
Cerebras
ChatAnywhere
ChatGLM
ChatGpt
ChatGptEs
ChatGptt
Chatgpt4Online
Chatgpt4o
ChatgptDuo
ChatgptFree
Cloudflare
CodeLinkAva
CohereForAI
Copilot
CopilotAccount
CreateImagesProvider
Cromicle
Custom
DDG
DarkAI
DeepInfra
DeepInfraChat
DeepSeek
DeepSeekAPI
DfeHub
EasyChat
Equing
FakeGpt
FastGpt
Feature
FlowGpt
Forefront
Free2GPT
FreeGpt
FreeNetfly
G4F
GPROChat
GPTalk
GeekGpt
Gemini
GeminiPro
GetGpt
GigaChat
GithubCopilot
GizAI
GlhfChat
Glider
Grok
Groq
H2o
HailuoAI
Hashnode
HuggingChat
HuggingFace
HuggingFaceAPI
HuggingFaceInference
HuggingSpace
ImageLabs
IterListProvider
Janus_Pro_7B
Jmuz
Koala
Liaobots
Local
Lockchat
MagickPen
MetaAI
MetaAIAccount
MicrosoftDesigner
MiniMax
MyShell
Myshell
OIVSCode
Ollama
Opchatgpts
OpenAssistant
OpenaiAPI
OpenaiAccount
OpenaiChat
OpenaiTemplate
PerplexityApi
PerplexityLabs
Phi_4
Phind
Pi
Pizzagpt
Poe
PollinationsAI
PollinationsImage
Prodia
Qwen_QVQ_72B
Qwen_Qwen_2_5M_Demo
Qwen_Qwen_2_72B_Instruct
Raycast
Reka
Replicate
ReplicateHome
RetryProvider
RobocodersAPI
RubiksAI
StableDiffusion35Large
TeachAnything
Theb
ThebApi
Upstage
V50
Vitalentum
VoodoohopFlux1Schnell
Wewordle
WhiteRabbitNeo
Wuguokai
Ylokh
You
Yqcloud
G4F
xAI' > /opt/python-tgpt/providers

# install golang-based tgpt
printf "\nInstalling Golang-based tgpt"
(
    cd "$working_dir" || exit
    mkdir gotgpt
    cd gotgpt || exit
    aria2c -x5 -s5 \
        https://github.com/aandrew-me/tgpt/releases/download/v"$GOTGPT_VER"/tgpt-linux-"$ARCH"
    chmod +x tgpt-linux*
    git clone https://github.com/AB9IL/gotgpt-wrapper
    chmod +x /usr/local/bin/gotgpt-wrapper
    ln -sf "$working_dir"/gotgpt-wrapper/gotgpt-wrapper \
        /usr/local/bin/gotgpt-wrapper

# create a launcher for Golang-based-tgpt
echo '[Desktop Entry]
Type=Application
Name=goTerminal GPT
Name[en]=goTerminal GPT
GenericName=goTerminal GPT Chatbots.
Comment=Access AI chatbots from the terminal.
Icon=utilities-terminal
Exec=gotgpt-wrapper
Terminal=true
Categories=ai;gpt;browser;chatbot;
' >/home/"$USERNAME"/.local/share/applications/gotgpt.desktop
)

# set ownership of all items in the home folder
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"

# Set alternatives as below:
# Web browser:
update-alternatives --install /usr/bin/www-browser www-browser /usr/local/bin/brave-with-proxy 60 &&
    update-alternatives --config www-browser
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/brave-with-proxy 60 &&
    update-alternatives --config x-www-browser
update-alternatives --install /usr/bin/debian-sensible-browser debian-sensible-browser /usr/local/bin/brave-with-proxy 60 &&
    update-alternatives --config debian-sensible-browser
update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/local/bin/brave-with-proxy 60 &&
    update-alternatives --config gnome-www-browser

# Vi and Vim:
update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60 &&
    update-alternatives --config vi
update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60 &&
    update-alternatives --config vim
update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60 &&
    update-alternatives --config editor

# Terminal emulators:
update-alternatives --install /usr/bin/xterm xterm /usr/bin/wezterm 60 &&
    update-alternatives --config xterm
update-alternatives --install /usr/bin/xterm-256color xterm-256color /usr/bin/wezterm 60 &&
    update-alternatives --config xterm-256color
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/wezterm 60 &&
    update-alternatives --config x-terminal-emulator
update-alternatives --install /usr/bin/debian-x-terminal-emulator debian-x-terminal-emulator /usr/bin/weezterm 60 &&
    update-alternatives --config debian-x-terminal-emulator

###############################################################################
# SDR HARDWARE DRIVERS AND SIGNAL DECODERS
###############################################################################

# Install Skywave Linux scripts
printf "\nInstalling Skywave-Linux-scripts"
(
    cd "$working_dir" || exit
    git clone https://github.com/AB9IL/Skywave-Linux-scripts
    SCRIPTS="aeromodes.sh ais-file-decoder ais-fileto-sqlite ais-mapper \
        ais_monitor.sh audioprism-selector dump1090-controller.sh \
        dump1090-stream-parser glow-wrapper rtlsdr-airband.sh \
        sdrplusplus sdr-bookmarks sdr-params.sh"
    for SCRIPT in $SCRIPTS;do
        chmod +x Skywave-Linux-scripts/"$SCRIPT"
        ln -sf "$working_dir"/Skywave-Linux-scripts/"$SCRIPT" \
            /usr/local/bin/"$SCRIPT"
    done
    # copy some files into the home configs
    cp "$working_dir"/Skywave-Linux-scripts/sdrbookmarks \
        /home/"$USERNAME"/.config/
    chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.config/
    # copy some launchers into the home environment
    cp "$working_dir"/Skywave-Linux-scripts/launchers/* \
        /home/"$USERNAME"/.local/share/applications/
        chown "$USERNAME":"$USERNAME" \
            /home/"$USERNAME"/.local/share/applications/*
    # copy some icons to the pixmaps folder
    [[ -f "/usr/share/pixmaps" ]] || mkdir -p /usr/share/pixmaps
    cp "$working_dir"/Skywave-Linux-scripts/icons/* \
        /usr/share/pixmaps/
    # set permissions and copy some files to other directories
    chmod 664 "$working_dir"/Skywave-Linux-scripts/etc/*
    cp "$working_dir"/Skywave-Linux-scripts/etc/* \
        /usr/local/etc/
)

# Install acarsdec
printf "\n...acarsdec..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/szpajder/acarsdec" --depth 1 \
        && mkdir -p "$working_dir/acarsdec/build"
    cd "$working_dir/acarsdec/build" || exit
    cmake ../ -Drtl=ON
    make -j4
    # make install
    ln -sf "$working_dir"/acarsdec/build/acarsdec /usr/local/bin/acarsdec
)

# Install acarsserv
printf "\n...acarsserv..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/TLeconte/acarsserv" --depth 1
    cd "$working_dir/acarsserv" || exit
    make -j4 -f Makefile
    ln -sf "$working_dir/acarsserv/acarsserv" "/usr/local/bin/acarsserv"
)

# Install audioprism
printf "\n...audioprism..."
(
    cd "$working_dir" || exit
    apt -o DPkg::Lock::Timeout=-1 install -y libsdl2-dev libsdl2-ttf-dev \
        libsndfile1-dev libgraphicsmagick++1-dev
    git clone "https://github.com/vsergeev/audioprism" --depth 1
    cd "$working_dir/audioprism" || exit
    make -j4
    # make install
    ln -sf /usr/local/src/audioprism/audioprism /usr/local/bin/audioprism
)

# Install dump1090
printf "\n...dump1090..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/adsbxchange/dump1090-fa" --depth 1
    cd "$working_dir/dumpdump1090-fa" || exit
    make -j4 -f Makefile BLADERF=no
    # uncomment the symlinker below if needed
    ln -sf "$working_dir/dump1090-fa/dump1090" "/usr/local/bin/dump1090"
    ln -sf "$working_dir/dump1090-fa/view1090" "/usr/local/bin/view1090"
)

# Install dump1090_ol3map
printf "\n\n...dump1090_ol3map..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/alkissack/Dump1090-OpenLayers3-html" --depth 1
    chmod 4775 "$working_dir/Dump1090-OpenLayers3-html"
    chmod 4777 "$working_dir/Dump1090-OpenLayers3-html/public_html"
    cd "$working_dir/Dump1090-OpenLayers3-html/public_html" || exit
    cp config.js config.js.orig
    chmod 666 config.js
    # set up the directory used by Dump1090
    mkdir -p "/usr/local/share/dump1090"
    ln -sf "$working_dir/Dump1090-OpenLayers3-html/public_html" "/usr/local/share/dump1090/html"
)

# Install dumphfdl
printf "\n...dumphfdl..."
(
    cd "$working_dir" || exit
    [[ -d "$working_dir/dumphfdl" ]] \
        || git clone "https://github.com/szpajder/dumphfdl" --depth 1 \
        && mkdir -p "$working_dir/dumphfdl/build"
    cd "usr/local/src/dumphfdl/build" || exit
    cmake ../
    make -j4
    # make install
    ln -sf /usr/local/src/dumphfdl/build/src/dumphfdl /usr/local/bin/dumphfdl
)

# Install dumpvdl2
printf "\n...dumpvdl2..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/szpajder/dumpvdl2" --depth 1 \
        && mkdir -p "$working_dir/dumpvdl2/build"
    cd "usr/local/src/dumpvdl2/build" || exit
    cmake ../
    make -j4
    # make install
    ln -sf /usr/local/src/dumpvdl2/build/src/dumpvdl2 /usr/local/bin/dumpvdl2
)

# Install kalibrate-rtl
printf "\n...kalibrate-rtl..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/steve-m/kalibrate-rtl" --depth 1
    cd "$working_dir/kalibrate-rtl" || exit
    ./bootstrap && CXXFLAGS='-W Wall -03'
    ./configure
    make -j4
    # make install
    ln -sf /usr/local/src/kalibrate-rtl/src/kal /usr/local/bin/kal
)

# Install libacars
printf "\n...libacars..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/szpajder/libacars" --depth 1 \
        && mkdir -p "$working_dir/libacars/build"
    cd "$working_dir/libacars/build" || exit
    cmake ../
    make -j4
    make install
)

# Install RTLSDR-Airband
printf "\n...RTLSDR-Airband..."
(
    cd "$working_dir" || exit
    [[ -d "$working_dir/RTLSDR-Airband" ]] \
        || git clone "https://github.com/szpajder/RTLSDR-Airband" --depth 1 \
        && mkdir -p "$working_dir/RTLSDR-Airband/build"
    cd "$working_dir/RTLSDR-Airband/build" || exit
    cmake -NFM=ON -DMIRISDR=OFF ../
    make -j4
    # make install
    ln -sf /usr/local/src/RTLSDR-Airband/build/src/rtl_airband /usr/local/bin/rtl_airband
)

# Install rtl-ais
printf "\n...rtl-ais..."
(
    cd "$working_dir" || exit
    [[ -d "$working_dir/rtl-ais" ]] \
        || git clone "https://github.com/dgiardini/rtl-ais" --depth 1
    cd "$working_dir/rtl-ais" || exit
    make -j4
    # make install
    ln -sf /usr/local/src/rtl-ais/rtl_ais /usr/local/bin/rtl_ais
)

# Install SDRTrunk
printf "\n...SDRTrunk..."
(
    cd "$working_dir" || exit
    wget -c https://github.com/DSheirer/sdrtrunk/releases/download/v"$TRUNK_VER"/sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER".zip
    if [[ -f  sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER".zip ]]; then
        unzip sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER".zip
        if [[ -f sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER"/bin/sdr-trunk ]]; then
            chmod +x sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER"/bin/sdrt-runk
            ln -sf sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER"/bin/sdr-trunk /usr/local/bin/sdrtrunk
        fi
        # clean up
        rm sdr-trunk-linux-"$ARCH2"-v"$TRUNK_VER".zip
    fi
)

# Install vdlm2dec
    printf "\n...vdlm2dec..."
    (
    cd "$working_dir" || exit
    git clone "https://github.com/TLeconte/vdlm2dec" --depth 1 \
        && mkdir -p "$working_dir/vdlm2dec/build"
    cd "$working_dir/vdlm2dec/build" || exit
    cmake .. -Drtl=ON
    make -j4
    # make install
    ln -sf /usr/local/src/vdlm2dec/build/vdlm2dec /usr/local/bin/vdlm2dec
)

# Install rx_tools
printf "\n...rx_tools..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/rxseger/rx_tools" --depth 1 \
        && mkdir -p "$working_dir/rx_tools/build"
    cd "$working_dir/rx_tools/build" || exit
    cmake ../
    make clean
    make -j4
    make install
)

# Install soapy rtl_tcp
printf "\n...SoapyRTLTCP..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/pothosware/SoapyRTLTCP" --depth 1 \
        && mkdir -p "$working_dir/SoapyRTLTCP/build"
    cd "$working_dir/SoapyRTLTCP/build" || exit
    cmake ..
    make clean
    make -j4
    make install
)

# Install SoapyPlutoSDR
printf "\n...SoapyPlutoSDR"
(
    cd "$working_dir" || exit
    git clone "https://github.com/pothosware/SoapyPlutoSDR" --depth 1 \
        && mkdir -p "$working_dir/SoapyPlutoSDR/build"
    cd "$working_dir/SoapyPlutoSDR/build" || exit
    cmake ..
    make clean
    make -j4
    make install
)

# Install SoapySDRPlay3
printf "\n...SoapySDRPlay3..."
(
    cd "$working_dir" || exit
    git clone "https://github.com/pothosware/SoapySDRPlay3" --depth 1 \
        && mkdir -p "$working_dir/SoapySDRPlay3/build"
    cd "$working_dir/SoapySDRPlay3/build" || exit
    cmake ..
    make clean
    make -j4
    make install
)

# Install the TCP server for Airspy HF+
printf "\n...hfp_tcp (TCP server for Airspy HF+)"
(
    cd "$working_dir" || exit
    git clone "https://github.com/hotpaw2/hfp_tcp" --depth 1
    cd "$working_dir/hfp_tcp" || exit
    make clean
    make -j4
    make install
)

# Install Soapy FCDPP
printf "\n...SoapyFCDPP"
(
    cd "$working_dir" || exit
    [[ -d "$working_dir/SoapyFCDPP" ]] \
        || git clone "https://github.com/pothosware/SoapyFCDPP" --depth 1 \
        && mkdir -p "$working_dir/SoapyFCDPP/build"
    cd "$working_dir/SoapyFCDPP/build" || exit
    cmake ../
    make clean
    make -j4
    make install
)

# Install SoapySpyServer
printf "\n...SoapySpyServer"
(
    cd "$working_dir" || exit
    git clone "https://github.com/pothosware/SoapySpyServer" --depth 1 \
        && mkdir -p "$working_dir/SoapySpyServer/build"
    cd "$working_dir/SoapySpyServer/build" || exit
    cmake ..
    make clean
    make -j4
    make install
)

# Install SDRplusplus
printf "\n...SDRplusplus"
(
    cd "$working_dir" || exit
    mkdir -p "$working_dir/SDRPlusPlus"
    # download from github
    # Note: Manually install the version of libvolk (libvolk1-dev or libvolk2-dev)
    # as needed for the current version of SDR++
    printf "Note: Manually install the version of libvolk
    (libvolk1-dev or libvolk2-dev) as needed for SDR++."
    wget -c https://github.com/AlexandreRouma/SDRPlusPlus/releases/download/nightly/sdrpp_debian_sid_amd64.deb
    if [[ -f "sdrpp_debian_sid_amd64.deb" ]]; then
        dpkg -i sdrpp_debian_sid_amd64.deb
        # clean up
        rm sdrpp_debian_sid_amd64.deb
    fi
)

# update the library cache
ldconfig

echo "Skywave Linux Setup is complete!"
