#!/usr/bin/env bash
#
# prime-rescue.sh
#
# Bootstrap a temporary Ubuntu/Debian rescue environment.
#
# Usage:
#   ./prime-rescue.sh
#   ./prime-rescue.sh --minimal
#   ./prime-rescue.sh --no-tailscale
#
# Optional environment variables:
#   TARGET_USER=marek
#   TS_AUTHKEY=tskey-auth-...
#   TS_HOSTNAME=rescue-pc
#   ENABLE_TAILSCALE_SSH=true
#
# Recommended:
#   Use an EPHEMERAL Tailscale auth key.
#
# Tested conceptually for Ubuntu/Debian systems.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

INSTALL_RESCUE_TOOLS=true
INSTALL_TAILSCALE=true

for arg in "$@"; do
    case "$arg" in
        --minimal)
            INSTALL_RESCUE_TOOLS=false
            ;;
        --no-tailscale)
            INSTALL_TAILSCALE=false
            ;;
        -h|--help)
            sed -n '2,22p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

# Determine the real interactive user, even when invoked using sudo.
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(logname 2>/dev/null || id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

TS_HOSTNAME="${TS_HOSTNAME:-rescue-$(hostname)-$(date +%m%d-%H%M)}"
ENABLE_TAILSCALE_SSH="${ENABLE_TAILSCALE_SSH:-false}"

if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    SUDO=(sudo)
fi

as_user() {
    if [[ "$TARGET_USER" == "root" ]]; then
        "$@"
    else
        "${SUDO[@]}" -u "$TARGET_USER" -H "$@"
    fi
}

section() {
    printf '\n\033[1;34m==> %s\033[0m\n' "$1"
}

# ---------------------------------------------------------------------------
# Basic checks
# ---------------------------------------------------------------------------

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This script currently supports Ubuntu/Debian (apt) systems."
    exit 1
fi

section "Target user: $TARGET_USER"

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

section "Updating package index"

"${SUDO[@]}" apt-get update

CORE_PACKAGES=(
    zsh
    git
    curl
    wget
    tmux
    openssh-server
    ca-certificates

    # General CLI utilities
    jq
    vim
    nano
    less
    tree
    htop
    ncdu
    ripgrep
    rsync
    unzip
    zip

    # Network diagnostics
    lsof
    dnsutils
    iproute2
    iputils-ping
    traceroute
    mtr-tiny
    ethtool
    tcpdump

    # Hardware visibility
    pciutils
    usbutils
    lshw
)

RESCUE_PACKAGES=(
    # Disk health
    smartmontools
    nvme-cli
    hdparm

    # Disk layout / partition recovery
    parted
    gdisk
    gddrescue
    testdisk

    # Filesystems
    e2fsprogs
    dosfstools
    ntfs-3g
    exfatprogs
    btrfs-progs
    xfsprogs

    # Storage layers
    cryptsetup
    lvm2
    mdadm

    # Virtual disk / VM image tools
    qemu-utils

    # Boot / EFI
    efibootmgr
    mokutil

    # Diagnostics
    strace
    sysstat
)

section "Installing core tools"

"${SUDO[@]}" apt-get install -y "${CORE_PACKAGES[@]}"

if [[ "$INSTALL_RESCUE_TOOLS" == true ]]; then
    section "Installing rescue and diagnostic tools"
    "${SUDO[@]}" apt-get install -y "${RESCUE_PACKAGES[@]}"
fi

# ---------------------------------------------------------------------------
# OpenSSH
# ---------------------------------------------------------------------------

section "Configuring OpenSSH"

# Make sure host keys exist. Particularly useful on live systems.
"${SUDO[@]}" ssh-keygen -A

if command -v systemctl >/dev/null 2>&1; then
    "${SUDO[@]}" systemctl enable ssh >/dev/null 2>&1 || true
    "${SUDO[@]}" systemctl restart ssh
else
    "${SUDO[@]}" service ssh restart
fi

# Deliberately DO NOT:
# - enable root SSH
# - enable password authentication
# - modify sshd_config
#
# Authentication remains governed by the distribution defaults.

# ---------------------------------------------------------------------------
# Oh My Zsh
# ---------------------------------------------------------------------------

section "Installing Oh My Zsh"

if [[ ! -d "$TARGET_HOME/.oh-my-zsh" ]]; then

    OMZ_INSTALLER="$(mktemp)"

    curl -fsSL \
        https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
        -o "$OMZ_INSTALLER"

    chmod +x "$OMZ_INSTALLER"

    as_user env \
        RUNZSH=no \
        CHSH=no \
        sh "$OMZ_INSTALLER" --unattended

    rm -f "$OMZ_INSTALLER"

else
    echo "Oh My Zsh already installed."
fi

# Set zsh as login shell.
ZSH_PATH="$(command -v zsh)"

CURRENT_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7)"

if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
    section "Setting zsh as default shell"
    "${SUDO[@]}" chsh -s "$ZSH_PATH" "$TARGET_USER"
fi

# ---------------------------------------------------------------------------
# tmux
# ---------------------------------------------------------------------------

section "Configuring tmux"

TMUX_CONF="$TARGET_HOME/.tmux.conf"

if [[ ! -e "$TMUX_CONF" ]]; then
    cat <<'EOF' | "${SUDO[@]}" tee "$TMUX_CONF" >/dev/null
# Rescue workstation defaults

# Use Ctrl-A as the tmux prefix instead of Ctrl-B.
# Press Ctrl-A twice to send Ctrl-A to the application inside the pane.
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Large scrollback
set -g history-limit 100000

# Mouse scrolling / pane selection
set -g mouse on

# Portable 256-colour TERM for live/rescue environments.
set -g default-terminal "screen-256color"

# Force ACS line drawing rather than UTF-8 line characters.
# This avoids broken/dashed pane borders with some terminal/font combinations.
set -as terminal-overrides ",*:U8=0"
EOF

    "${SUDO[@]}" chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$TMUX_CONF"
else
    echo "Existing .tmux.conf retained."
fi

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------

if [[ "$INSTALL_TAILSCALE" == true ]]; then

    section "Installing Tailscale"

    if ! command -v tailscale >/dev/null 2>&1; then

        TS_INSTALLER="$(mktemp)"

        curl -fsSL https://tailscale.com/install.sh -o "$TS_INSTALLER"

        "${SUDO[@]}" sh "$TS_INSTALLER"

        rm -f "$TS_INSTALLER"
    else
        echo "Tailscale already installed."
    fi

    if command -v systemctl >/dev/null 2>&1; then
        "${SUDO[@]}" systemctl enable --now tailscaled
    fi

    # -----------------------------------------------------------------------
    # Authentication
    # -----------------------------------------------------------------------

    if [[ -z "${TS_AUTHKEY:-}" ]] && [[ -t 0 ]]; then

        echo
        echo "For a truly temporary node, use an EPHEMERAL Tailscale auth key."
        echo
        read -rsp \
            "Paste ephemeral Tailscale auth key (Enter for browser login): " \
            TS_AUTHKEY
        echo
    fi

    TS_OPTIONS=(
        "--hostname=$TS_HOSTNAME"
    )

    if [[ "$ENABLE_TAILSCALE_SSH" == true ]]; then
        TS_OPTIONS+=("--ssh")
    fi

    if [[ -n "${TS_AUTHKEY:-}" ]]; then

        section "Connecting ephemeral Tailscale node"

        "${SUDO[@]}" tailscale up \
            --auth-key="$TS_AUTHKEY" \
            "${TS_OPTIONS[@]}"

        # Remove credential from this process environment.
        unset TS_AUTHKEY

    else

        section "Connecting Tailscale interactively"

        "${SUDO[@]}" tailscale up "${TS_OPTIONS[@]}"
    fi
fi

# ---------------------------------------------------------------------------
# Final status
# ---------------------------------------------------------------------------

section "Bootstrap complete"

echo
printf "User:             %s\n" "$TARGET_USER"
printf "Default shell:    %s\n" "$(getent passwd "$TARGET_USER" | cut -d: -f7)"

if command -v systemctl >/dev/null 2>&1; then
    printf "OpenSSH:          %s\n" \
        "$(systemctl is-active ssh 2>/dev/null || echo unknown)"
fi

echo
echo "Network addresses:"
hostname -I 2>/dev/null || true

if command -v tailscale >/dev/null 2>&1; then
    TS_IP="$(tailscale ip -4 2>/dev/null || true)"

    if [[ -n "$TS_IP" ]]; then
        echo
        echo "Tailscale:"
        printf "  Hostname:       %s\n" "$TS_HOSTNAME"
        printf "  IPv4:           %s\n" "$TS_IP"
    fi
fi

echo
echo "Useful commands:"
echo "  tmux"
echo "  lsblk -f"
echo "  sudo fdisk -l"
echo "  sudo smartctl --scan"
echo "  sudo nvme list"
echo "  sudo lshw -short"
echo "  tailscale status"
echo

if [[ "$INSTALL_RESCUE_TOOLS" == true ]]; then
    echo "Recovery tools installed:"
    echo "  ddrescue, testdisk, smartctl, nvme, gdisk, parted,"
    echo "  qemu-utils (qemu-img/qemu-nbd), cryptsetup, LVM, mdadm"
    echo "  and common filesystem tools."
    echo
fi

echo "Start a fresh zsh session with:"
echo "  exec zsh -l"
echo