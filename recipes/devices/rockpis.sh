#!/usr/bin/env bash
# shellcheck disable=SC2034
## Setup for Radxa Rock Pi S
DEVICE_SUPPORT_TYPE="C" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="P"       # First letter (Planned|Test|Maintenance)

# Base system
BASE="Debian"
ARCH="arm64"
BUILD="armv8"
# ARCH="armhf"
# BUILD="armv7"
UINITRD_ARCH="arm64"

### Device information
DEVICENAME="ROCK Pi S"
# This is useful for multiple devices sharing the same/similar kernel
DEVICEFAMILY="rockpis"
# tarball from DEVICEFAMILY repo to use
#DEVICEBASE=${DEVICE} # Defaults to ${DEVICE} if unset
DEVICEREPO="https://github.com/ashthespy/platform-${DEVICEFAMILY}.git"

### What features do we want to target
# TODO: Not fully implement
VOLVARIANT=no # Custom Volumio (Motivo/Primo etc)
MYVOLUMIO=no
VOLINITUPDATER=yes

## Partition info
BOOT_START=20
BOOT_END=84
BOOT_TYPE=msdos      # msdos or gpt
BOOT_USE_UUID=yes    # Add UUID to fstab
INIT_TYPE="init.vol" # init.{x86/nextarm/nextarm_tvbox}

# Modules that will be added to intramsfs
MODULES=("overlay" "squashfs" "nls_cp437" "nls_iso8859-1")
# Packages that will be installed
PACKAGES=("tree")

### Device customisation
# Copy the device specific files (Image/DTS/etc..)
write_device_files() {
  log "Running write_device_files" "ext"

  cp -dR "${PLTDIR}/${DEVICE}/boot" "${ROOTFSMNT}"
  cp -pdR "${PLTDIR}/${DEVICE}/lib/modules" "${ROOTFSMNT}/lib"
  cp -pdR "${PLTDIR}/${DEVICE}/lib/firmware" "${ROOTFSMNT}/lib"
}

write_device_bootloader() {
  log "Running write_device_bootloader" "ext"

  dd if="${PLTDIR}/${DEVICE}/u-boot/idbloader.bin" of="${LOOP_DEV}" seek=64 conv=notrunc status=none
  dd if="${PLTDIR}/${DEVICE}/u-boot/uboot.img" of="${LOOP_DEV}" seek=16384 conv=notrunc status=none
  dd if="${PLTDIR}/${DEVICE}/u-boot/trust.bin" of="${LOOP_DEV}" seek=24576 conv=notrunc status=none
}

# Will be called by the image builder for any customisation
device_image_tweaks() {
  :
}

### Chroot tweaks
# Will be run in chroot (before other things)
device_chroot_tweaks() {
  :
}

# Will be run in chroot - Pre initramfs
device_chroot_tweaks_pre() {
  log "Performing device_chroot_tweaks_pre" "ext"
  if [[ ${BUILD} == "armv7" ]]; then
    log "Fixing armv8 deprecated instruction emulation with ${BUILD} rootfs"
    cat <<-EOF >>/etc/sysctl.conf
		# Fix armv8 deprecated instructions on armv7 rootfs
		abi.cp15_barrier=2
		EOF
  elif [[ ${BUILD} == "armv8" ]]; then
    # Enable plugins
    log "Enabling plugins on ${BUILD}" "dbg"
    sed -i 's/var archraw.*/var archraw = "armhf";/' /volumio/app/pluginmanager.js
  fi

  log "Adding gpio group and udev rules"
  groupadd -f --system gpio
  usermod -aG gpio volumio
  cat <<-"EOF" >/etc/udev/rules.d/99-gpio.rules
	SUBSYSTEM=="gpio", ACTION=="add", RUN="/bin/sh -c '
	chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio;\
	chown -R root:gpio /sys$DEVPATH && chmod -R 770 /sys$DEVPATH
	'"
	EOF

  log "Preparing boot information for Kernel"
  cat <<-EOF >/boot/armbianEnv.txt
	verbosity=7
	extraargs=swiotlb=1024
	overlay_prefix=rk3308
	fdtfile=rockchip/rk3308-rock-pi-s.dtb
	rootdev=UUID=${UUID_BOOT}
	rootfstype=ext4
	console=both
	usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
	extraargs=imgpart=UUID=${UUID_IMG} bootpart=UUID=${UUID_BOOT} datapart=UUID=${UUID_DATA} imgfile=/volumio_current.sqsh bootconfig=armbianEnv.txt  
	user_overlays=rockchip-i2s0_master
	EOF

  if [[ ${DISTRO_NAME} == "buster" ]]; then
    # Workaround: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=866306
    log "[${DISTRO_NAME}] Running tweaks for haveged"
    sed -i 's|^ExecStart=/usr/sbin/haveged|ExecStart=/usr/sbin/haveged --data=16|' /lib/systemd/system/haveged.service
  fi

}

# Will be run in chroot - Post initramfs
device_chroot_tweaks_post() {
  # log "Running device_chroot_tweaks_post" "ext"
  :
}

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
  log "Running device_image_tweaks_post" "ext"
  log "Creating uInitrd from 'volumio.initrd'" "info"
  if [[ -f "${ROOTFSMNT}"/boot/volumio.initrd ]]; then
    mv "${ROOTFSMNT}"/boot/volumio.initrd "${BUILDTMPDIR}"/volumio.initrd
    mkimage -v -A "${UINITRD_ARCH}" -O linux -T ramdisk -C gzip -n uInitrd -d "${BUILDTMPDIR}"/volumio.initrd "${ROOTFSMNT}"/boot/uInitrd || {
      log "Not enough space on BOOT_PART" "err" "$(check_size "${ROOTFSMNT}/boot")"
    }
    rm "${BUILDTMPDIR}"/volumio.initrd
  fi
  if [[ -f "${ROOTFSMNT}"/boot/boot.cmd ]]; then
    log "Creating boot.scr"
    mkimage -A arm -T script -C none -d "${ROOTFSMNT}"/boot/boot.cmd "${ROOTFSMNT}"/boot/boot.scr
  fi
}
