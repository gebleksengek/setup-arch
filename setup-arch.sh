#!/usr/bin/env bash

# This script sets up a minimal Arch Linux installation in a chroot environment.
# It is meant to be run on a Debian-based system (e.g. Ubuntu) with root privileges via sudo.
#
# Following environment variables are required:
#   - INPUT_ARCH_MIRROR: Mirror to download the bootstrap tarball from (e.g. https://mirror.archlinuxarm.org)
#   - INPUT_ARCH_PACKAGES: List of additional packages to install, separated by spaces (e.g. git vim)
#
# Bash 4 and higher is required.
# shellcheck shell=bash
#
set -euo pipefail

## Constants
####################################################################################################
# readonly WHAT_I_AM="$(readlink -f "$0")"
WHERE_I_AM="$(cd "$(dirname "$0")" && pwd)"
readonly WHERE_I_AM

readonly RUNNER_HOME="/home/$SUDO_USER"
readonly ARCH_ROOTFS_DIR="$RUNNER_HOME/root.aarch64"

## Logging functions
####################################################################################################

_CURRENT_GROUP=""

debug() {
    printf "::debug::%s\n" "$*"
}

notice() {
    printf "::notice::%s\n" "$*"
}

warning() {
    printf "::warning::%s\n" "$*"
}

error() {
    printf "::error::%s\n" "$*"
}

group() {
    [ -n "$_CURRENT_GROUP" ] && endgroup

    printf "::group::%s\n" "$*"
    _CURRENT_GROUP="$*"
}

endgroup() {
    [ -n "$_CURRENT_GROUP" ] && printf "::endgroup::\n"
    _CURRENT_GROUP=""
}

output() {
    local variable="$1"
    shift

    printf "%s=%s\n" "$variable" "$*" >> "$GITHUB_OUTPUT"
}

path() {
    printf "%s\n" "$*" >> "$GITHUB_PATH"
}


## Helper functions
####################################################################################################

## Download a file from a URL.
##
## $1: URL to download
## $2: Path to save the file to
download() {
    local url="$1"
    local path="$2"

    group "Downloading $url..."
    curl -sSL -o "$path" "$url" 2>&1
    endgroup
}

## Extract a tarball while preserving permissions.
##
## $1: Path to the tarball to extract
## $2: Path to extract the tarball to
extract() {
    local tarball="$1"
    local path="$2"

    group "Extracting $tarball..."
    mkdir -p "$path"
    tar --gzip -xf "$tarball" -C "$path" --numeric-owner 2>&1
    endgroup
}

## Write to a file as root.
##
## $1: Path to the file to write to
## $2: Content to write to the file
write() {
    local path="$1"
    local content="$2"

    group "Writing to $path..."
    echo "$content" > "$path"
    endgroup
}

## Bind mount a directory.
##
## $1: Path to the directory to bind mount
## $2: Path to bind mount the directory to
bind_mount() {
    local source="$1"
    local target="$2"

    group "Bind mounting $source to $target..."
    mkdir -p "$target"
    mount -v --rbind "$source" "$target" 2>&1
    endgroup
}

## Run a command in the chroot environment.
##
## $1: Command to run
run() {
    local cmd="$1"

    group "Running $cmd..."
    "$ARCH_ROOTFS_DIR/bin/arch-chroot" "$ARCH_ROOTFS_DIR" /bin/bash -c "$cmd" 2>&1
    endgroup
}

## Entrypoint
####################################################################################################

# Download the latest bootstrap tarball from the mirror and signature from the official server
download "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz" "ArchLinuxARM-aarch64-latest.tar.gz"

# Extract the tarball
extract "ArchLinuxARM-aarch64-latest.tar.gz" "$ARCH_ROOTFS_DIR"

# Bind mount rootfs to itself
bind_mount "$ARCH_ROOTFS_DIR" "$ARCH_ROOTFS_DIR"

# Copy the action script
install -Dvm755 "$WHERE_I_AM/arch.sh" "$ARCH_ROOTFS_DIR/bounce/arch.sh"
install -Dvm755 "$WHERE_I_AM/arch-chroot" "$ARCH_ROOTFS_DIR/bin/arch-chroot"

# Populate the mirror list
write "$ARCH_ROOTFS_DIR/etc/pacman.d/mirrorlist" "Server = $INPUT_ARCH_MIRROR/\$arch/\$repo"

# Install essential packages (base-devel)
run "pacman-key --init"
run "pacman-key --populate archlinuxarm"
run "sed -i 's/CheckSpace/#CheckSpace/' /etc/pacman.conf"
run "pacman -Syu --noconfirm --needed base-devel"

# Install additional packages if specified
if [ -n "$INPUT_ARCH_PACKAGES" ]; then
    run "pacman -Syu --noconfirm --needed $INPUT_ARCH_PACKAGES"
fi

# Set up the user
_UID="$(id -u "$SUDO_USER")"
run "useradd -u $_UID -G wheel -s /bin/bash $SUDO_USER"

# Set up the working directory
bind_mount "$RUNNER_HOME" "$ARCH_ROOTFS_DIR/$RUNNER_HOME"

# Set up sudo
run "echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"

# Clean up
rm -rf "ArchLinuxARM-aarch64-latest.tar.gz"

# Output the path to the rootfs directory
output root-path "$ARCH_ROOTFS_DIR"
path "$ARCH_ROOTFS_DIR/bounce"
