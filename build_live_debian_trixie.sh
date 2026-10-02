#!/bin/bash
set -e

# --- CONFIGURATION ---
DISTRO="trixie"
IMAGE_NAME="custom-debian-live-${DISTRO}.iso"
EXTRA_PACKAGES="
  adb arduino btrfs-progs btop byobu chromium cifs-utils clonezilla curl
  dctrl-tools debian-installer-launcher dmidecode dosfstools e2fsprogs
  efibootmgr efivar exfatprogs ext4magic extundelete f2fs-tools fastboot
  fatresize firmware-linux firmware-linux-free firmware-linux-nonfree
  firmware-misc-nonfree fwupd gedit gparted gnome-disk-utility
  gnome-firmware gnome-tweaks gsmartcontrol gvfs-backends htop
  libarchive-tools libsmbclient lm-sensors locate lshw lvm2 man mdadm
  mtools nano ncdu net-tools nfs-common nmap ntfs-3g rsync smbclient
  task-gnome-desktop testdisk vlc wget zfsutils-linux
"
SIZE="20G"

# --- BUILD ENVIRONMENT SETUP ---
export BUILD_DIR="$(pwd)/ramdisk"
export CACHE_DIR="$(pwd)/cache"
export CACHE_BIND_DIR="${BUILD_DIR}/cache"
export OUTPUT_DIR="$(pwd)"

mkdir -p "$BUILD_DIR"
mkdir -p "$CACHE_DIR"

if mountpoint -q "$BUILD_DIR"; then
    echo "$BUILD_DIR is already mounted."
else
    echo "Mounting tmpfs at $BUILD_DIR..."
    sudo mount -t tmpfs -o size=$SIZE tmpfs "$BUILD_DIR"
fi

mkdir -p "$CACHE_BIND_DIR"

if mountpoint -q "$CACHE_BIND_DIR"; then
    echo "$CACHE_BIND_DIR is already mounted."
else
    echo "Mounting the persistent cache at $BUILD_DIR/cache..."
    sudo mount --bind "$CACHE_DIR" "$CACHE_BIND_DIR"
fi

cd "$BUILD_DIR"

# --- RUN LIVE-BUILD ---
lb clean

lb config noauto \
  --apt-recommends true \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-images iso-hybrid \
  --bootappend-live "boot=live components autologin username=user hostname=debian locales=en_US.UTF-8,it_IT.UTF-8 keyboard-layouts=us,it" \
  --bootloaders "grub-efi,syslinux" \
  --debian-installer live \
  --distribution "$DISTRO" \
  --iso-application "Custom Debian Live (${DISTRO})" \
  --iso-publisher "Me Stesso" \
  --updates true \
  --uefi-secure-boot auto

# --- PACKAGE LISTS ---
mkdir -p config/package-lists
echo "live-boot systemd-sysv live-config live-config-systemd sudo" > config/package-lists/live.list.chroot
# Convert the package string to the format used by the package list file.
echo "$EXTRA_PACKAGES" | tr ' ' '\n' > config/package-lists/custom.list.chroot


# --- HOOK TO PREVENT DPKG ERRORS (IMPORTANT!) ---
# This section creates a script that prevents services from starting
# during installation in the chroot, resolving the dpkg error.
mkdir -p config/hooks/chroot
cat > config/hooks/chroot/disable-services.hook.chroot << 'EOF'
#!/bin/sh
set -e

# Create a policy that prevents daemons from starting.
cat << 'POLICY' > /usr/sbin/policy-rc.d
#!/bin/sh
echo "All runlevel changes denied by policy"
exit 101
POLICY

chmod +x /usr/sbin/policy-rc.d
EOF


# Start the build.
lb build


# --- FINALIZATION ---
# Remove the policy script after the build, before creating the ISO.
# This is important so services can start normally
# when the live system boots.
rm -f chroot/usr/sbin/policy-rc.d

# Move and rename the ISO.
if [ -f live-image-amd64.hybrid.iso ]; then
  mv -f live-image-amd64.hybrid.iso "${OUTPUT_DIR}/${IMAGE_NAME}"
  sudo chmod 777 "${OUTPUT_DIR}/${IMAGE_NAME}"
  echo "✅ ISO ready: ${OUTPUT_DIR}/${IMAGE_NAME}"
else
  echo "❌ Error: ISO not found!"
  exit 1
fi

cd "$OUTPUT_DIR"
echo "Unmounting filesystems..."
sudo umount "$CACHE_BIND_DIR"
sudo umount "$BUILD_DIR"
echo "Cleanup complete."
