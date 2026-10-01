# linux-bootstrap

A bootstrap script for turning a temporary Ubuntu/Debian Linux environment into a practical rescue and troubleshooting workstation.

The main use case is a **live Linux instance**, for example Ubuntu started from a USB drive when a PC, server or storage device needs to be diagnosed or repaired. Rather than manually installing the same tools every time, `bootstrap.sh` prepares the environment with a familiar shell, remote access, networking utilities and storage/recovery tools.

> **Important:** this script installs diagnostic and recovery tooling, but it deliberately does not perform any automatic disk repair, mounting, partitioning or filesystem modification.

## What it sets up

### Working environment

The bootstrap installs and configures:

- **Zsh**
- **Oh My Zsh**
- **Git**
- **curl** and **wget**
- **tmux**
- **OpenSSH Server**
- **Tailscale**
- common command-line utilities such as `jq`, `ripgrep`, `rsync`, `tree`, `htop` and `ncdu`

Zsh is configured as the target user's default shell.

A small tmux configuration is created when `~/.tmux.conf` does not already exist, enabling:

- `Ctrl-A` as the tmux prefix instead of the default `Ctrl-B`
- mouse support
- 100,000-line scrollback
- portable 256-colour terminal support
- ACS line drawing to avoid broken or dashed pane separators on some live-console, terminal and font combinations

Press `Ctrl-A Ctrl-A` to send a literal `Ctrl-A` through to the application running inside the active pane.

Existing tmux configuration is left untouched.

### Remote access

The script installs OpenSSH Server, creates missing SSH host keys and starts the SSH service.

It deliberately does **not**:

- enable SSH root login
- enable password authentication
- modify `sshd_config`

SSH authentication therefore remains governed by the Linux distribution's existing configuration.

### tmux

The generated tmux configuration uses `Ctrl-A` as its command prefix:

```text
Ctrl-A c       create a new window
Ctrl-A %       split vertically
Ctrl-A "       split horizontally
Ctrl-A d       detach
Ctrl-A [       enter copy/scrollback mode
Ctrl-A ?       show key bindings
Ctrl-A Ctrl-A  send Ctrl-A to the active application
```

The configuration uses:

```tmux
set -g default-terminal "screen-256color"
set -as terminal-overrides ",*:U8=0"
```

The second setting makes tmux use terminal ACS characters for pane borders instead of relying on UTF-8 line-drawing glyphs. This improves border rendering on temporary/live Linux environments where terminal capabilities or fonts may differ.

If tmux is already running after changing the file, reload it with:

```bash
tmux source-file ~/.tmux.conf
```

### Tailscale

Tailscale is installed and can be used to reach the temporary machine without exposing SSH directly to the local network or Internet.

The script supports an **ephemeral Tailscale auth key**, which is the recommended approach for temporary rescue machines.

If no auth key is supplied, the script falls back to interactive Tailscale login.

The temporary node hostname defaults to:

```text
rescue-<hostname>-<month><day>-<hour><minute>
```

For example:

```text
rescue-ubuntu-1001-0815
```

### Rescue and diagnostic tools

The normal installation includes a broader rescue toolkit.

#### Storage health

- `smartmontools`
- `nvme-cli`
- `hdparm`

#### Disk and partition recovery

- `parted`
- `gdisk`
- `gddrescue`
- `testdisk`

#### Filesystems

- ext filesystem tools
- FAT tools
- NTFS support
- exFAT tools
- Btrfs tools
- XFS tools

#### Storage layers

- `cryptsetup`
- LVM
- Linux software RAID / `mdadm`

#### Virtual disk and VM image tools

- `qemu-utils`
  - `qemu-img` for inspecting, converting and working with virtual disk images
  - `qemu-nbd` for exposing supported virtual disk images as Linux block devices

This is particularly useful when recovering files or configuration from VM images such as QCOW2, VMDK and other QEMU-supported formats.

#### Boot and EFI

- `efibootmgr`
- `mokutil`

#### Network and system diagnostics

- `tcpdump`
- `mtr`
- `traceroute`
- `ethtool`
- `lsof`
- `strace`
- `sysstat`
- `lshw`
- PCI and USB utilities

## Requirements

The script currently targets systems that use **APT**, principally:

- Ubuntu
- Debian
- Ubuntu-based live/rescue environments

You need:

- Internet connectivity
- a user with `sudo` access, or a root shell
- working DNS and package repositories

## Quick start

Clone the repository from the temporary Linux environment:

```bash
git clone https://github.com/lightflicker/linux-bootstrap.git
cd linux-bootstrap
chmod +x bootstrap.sh
./bootstrap.sh
```

The script will request sudo privileges where required.

At the end it displays:

- target user
- configured login shell
- OpenSSH status
- local IP addresses
- Tailscale hostname and IP, when connected
- a few useful recovery commands

Start the newly configured shell with:

```bash
exec zsh -l
```

## Installation modes

### Full rescue environment

This is the default:

```bash
./bootstrap.sh
```

It installs both the everyday CLI tools and the storage/recovery toolkit.

### Minimal environment

To install the shell, networking, remote-access and general CLI tools without the larger rescue toolkit:

```bash
./bootstrap.sh --minimal
```

### Without Tailscale

If Tailscale is not wanted:

```bash
./bootstrap.sh --no-tailscale
```

The switches can be combined:

```bash
./bootstrap.sh --minimal --no-tailscale
```

## Tailscale configuration

### Recommended: ephemeral auth key

Create an **ephemeral auth key** in Tailscale before starting the rescue session.

When `bootstrap.sh` is run from an interactive terminal it asks:

```text
Paste ephemeral Tailscale auth key (Enter for browser login):
```

The input is hidden and the key is removed from the script environment after Tailscale has authenticated.

Avoid placing an auth key directly in shell history.

### Browser login

Press **Enter** at the auth-key prompt to use normal interactive Tailscale authentication.

### Custom hostname

Override the automatically generated hostname:

```bash
TS_HOSTNAME=rescue-dell ./bootstrap.sh
```

### Tailscale SSH

Tailscale SSH is disabled by default.

Enable it with:

```bash
ENABLE_TAILSCALE_SSH=true ./bootstrap.sh
```

This is separate from the conventional OpenSSH service installed by the bootstrap.

## Target user

Normally the script detects the user that invoked `sudo` and installs Oh My Zsh and the tmux configuration for that account.

The target can be overridden:

```bash
TARGET_USER=ubuntu ./bootstrap.sh
```

This is useful in live environments where the automatically detected account is not the one you intend to use.

## Typical rescue workflow

A simple live-USB workflow might look like this:

```bash
# 1. Boot Ubuntu from USB and connect it to the network.

# 2. Get the bootstrap environment.
git clone https://github.com/lightflicker/linux-bootstrap.git
cd linux-bootstrap

# 3. Prime the rescue workstation.
./bootstrap.sh

# 4. Start the configured shell.
exec zsh -l

# 5. Inspect storage before changing anything.
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
sudo fdisk -l
sudo smartctl --scan
sudo nvme list

# 6. Start tmux if the repair may take a while.
tmux
```

For a failing drive, **inspect first and write later**. For example, imaging a suspect disk with `ddrescue` is normally safer than attempting filesystem repair directly against the original device.

## Useful commands after bootstrap

### Storage overview

```bash
lsblk -f
sudo fdisk -l
sudo blkid
```

### SMART disks

```bash
sudo smartctl --scan
sudo smartctl -a /dev/sdX
```

### NVMe

```bash
sudo nvme list
sudo nvme smart-log /dev/nvme0
```

### Virtual disk images

Inspect an image:

```bash
qemu-img info disk.qcow2
```

Attach a virtual disk image read-only through NBD:

```bash
sudo modprobe nbd max_part=16
sudo qemu-nbd --read-only --connect=/dev/nbd0 disk.qcow2
lsblk /dev/nbd0
```

When finished:

```bash
sudo qemu-nbd --disconnect /dev/nbd0
```

Using `--read-only` is recommended when examining recovery images to avoid accidental modification.

### Hardware

```bash
sudo lshw -short
lspci
lsusb
```

### Network

```bash
ip addr
ip route
ss -lntup
sudo ethtool <interface>
mtr <hostname>
```

### Tailscale

```bash
tailscale status
tailscale ip -4
```

### SSH

```bash
systemctl status ssh
ss -lntp | grep ':22'
```

## Safety philosophy

This bootstrap is intended to **prepare the toolbox, not perform the repair**.

It therefore avoids automatically:

- mounting unknown disks
- modifying partition tables
- running filesystem repair
- assembling RAID arrays
- activating LVM volumes
- unlocking encrypted volumes
- changing SSH security policy
- copying personal SSH private keys

That distinction matters on a recovery system: discovery should be low-risk and repeatable, while actions that can change evidence or storage state should remain explicit.

## Persistence

When run from a normal non-persistent live USB environment, most changes disappear when the machine is rebooted.

That is intentional.

The repository can therefore act as a reproducible way of turning a disposable Linux environment into a familiar troubleshooting workstation whenever it is needed.

## Repository contents

```text
linux-bootstrap/
├── bootstrap.sh
└── README.md
```

## Planned improvements

Potential future additions include:

- optional dotfiles installation
- SSH public-key provisioning
- VMFS tooling for VMware/ESXi recovery
- optional Samba/NFS utilities
- persistent logging of machine diagnostics
- a non-interactive mode for trusted environments
- distribution detection beyond Debian/Ubuntu
- modular profiles such as `storage`, `network`, `virtualisation` and `forensics`

## Licence

No licence has currently been specified.
