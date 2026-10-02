# Custom Debian Live

Create a custom Debian Trixie live ISO with GNOME, firmware, and system tools.

Edit the package list in `build_live_debian_trixie.sh`, then run the script
with root privileges on a Debian system with `live-build` installed.
The build uses a 20 GiB RAM filesystem and a persistent package cache,
and produces `custom-debian-live-trixie.iso` in the current directory.


# some tricks 

For example: check firmware files inside the ISO (`bsdtar` requires `libarchive-tools`):

```sh
bsdtar -tf custom-debian-live-trixie.iso | grep firmware
```

Write the ISO to a USB drive. Replace `/dev/sdX` with the target device;
this erases its contents.

```sh
sudo dd if=custom-debian-live-trixie.iso of=/dev/sdX bs=32M status=progress conv=fsync
```
