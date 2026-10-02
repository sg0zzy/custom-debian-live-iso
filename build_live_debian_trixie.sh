#!/bin/bash
set -e

# --- CONFIGURAZIONE ---
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

# --- IMPOSTAZIONE AMBIENTE DI BUILD ---
export BUILD_DIR="$(pwd)/ramdisk"
export CACHE_DIR="$(pwd)/cache"
export CACHE_BIND_DIR="${BUILD_DIR}/cache"
export OUTPUT_DIR="$(pwd)"

mkdir -p "$BUILD_DIR"
mkdir -p "$CACHE_DIR"

if mountpoint -q "$BUILD_DIR"; then
    echo "$BUILD_DIR è già montato."
else
    echo "Monto tmpfs in $BUILD_DIR..."
    sudo mount -t tmpfs -o size=$SIZE tmpfs "$BUILD_DIR"
fi

mkdir -p "$CACHE_BIND_DIR"

if mountpoint -q "$CACHE_BIND_DIR"; then
    echo "$CACHE_BIND_DIR è già montato."
else
    echo "Monto la cache persistente in $BUILD_DIR/cache..."
    sudo mount --bind "$CACHE_DIR" "$CACHE_BIND_DIR"
fi

cd "$BUILD_DIR"

# --- ESECUZIONE LIVE-BUILD ---
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

# --- LISTE PACCHETTI ---
mkdir -p config/package-lists
echo "live-boot systemd-sysv live-config live-config-systemd sudo" > config/package-lists/live.list.chroot
# Converti la stringa di pacchetti in un formato per il file di lista
echo "$EXTRA_PACKAGES" | tr ' ' '\n' > config/package-lists/custom.list.chroot


# --- HOOK PER EVITARE ERRORI DPKG (LA PARTE IMPORTANTE!) ---
# Questa sezione crea uno script che impedisce ai servizi di avviarsi
# durante la fase di installazione nel chroot, risolvendo l'errore dpkg.
mkdir -p config/hooks/chroot
cat > config/hooks/chroot/disable-services.hook.chroot << 'EOF'
#!/bin/sh
set -e

# Crea una policy che impedisce l'avvio dei daemon
cat << 'POLICY' > /usr/sbin/policy-rc.d
#!/bin/sh
echo "All runlevel changes denied by policy"
exit 101
POLICY

chmod +x /usr/sbin/policy-rc.d
EOF


# Avvia la build
lb build


# --- FINALIZZAZIONE ---
# Rimuovi lo script della policy alla fine della build, prima di creare l'ISO
# Questo è importante affinché i servizi possano avviarsi normalmente
# quando si avvia il sistema live.
rm -f chroot/usr/sbin/policy-rc.d

# Sposta e rinomina l'ISO
if [ -f live-image-amd64.hybrid.iso ]; then
  mv -f live-image-amd64.hybrid.iso "${OUTPUT_DIR}/${IMAGE_NAME}"
  sudo chmod 777 "${OUTPUT_DIR}/${IMAGE_NAME}"
  echo "✅ ISO pronta: ${OUTPUT_DIR}/${IMAGE_NAME}"
else
  echo "❌ Errore: ISO non trovata!"
  exit 1
fi

cd "$OUTPUT_DIR"
echo "Smontaggio dei filesystem..."
sudo umount "$CACHE_BIND_DIR"
sudo umount "$BUILD_DIR"
echo "Pulizia completata."