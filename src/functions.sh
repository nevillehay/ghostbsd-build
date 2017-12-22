#!/usr/bin/env sh

# Only run as superuser
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Source our config
. build.cfg

# Set the current working directory
cwd="`realpath | sed 's|/scripts||g'`" ; export cwd

create_workspace()
{
  if [ ! -d "${livecd}" ] ; then
    mkdir ${livecd} ${base} ${packages}
  fi
}

clean_workspace()
{
  chflags -R noschg ${livecd} >/dev/null 2>/dev/null
  rm -rf ${livecd} >/dev/null 2>/dev/null
}

fetch_base()
{
  if [ ! -f "${base}/fbsd-distrib.txz" ] ; then
    cd ${base}
    fetch http://pkg.cdn.trueos.org/packages/master/amd64-base/fbsd-distrib.txz
    pkg fetch -r trueos-base -a -y -o ${base}
  fi
}

install_base()
{
ABI="FreeBSD:`uname -r | cut -d '.' -f 1`:`uname -m`"
  export ABI
  for mpnt in dev compat mnt proc root var/run
  do
    if [ ! -d "${release}/$mpnt" ] ; then
      mkdir -p ${release}/$mpnt
    fi
  done
  mkdir -p ${release}/packages
  mount_nullfs ${base} ${release}/packages
  tar -zxvf ${base}/fbsd-distrib.txz -C ${release} etc
  for pkg in `ls ${release}/packages/FreeBSD-*`
  do
    inspkg=$(basename $pkg)
    pkg -c ${release} add -f /packages/$inspkg
  done
  umount -f ${release}/packages
}

install_overlay()
{
  cp -R ${cwd}/overlay/ ${release}
}

uzip () {
	install -o root -g wheel -m 755 -d "${cdroot}"
	mkdir "${cdroot}/data"
	makefs "${cdroot}/data/system.ufs" "${release}"
	mkuzip -o "${cdroot}/data/system.uzip" "${cdroot}/data/system.ufs"
	rm -f "${cdroot}/data/system.ufs"
}

ramdisk () {
	ramdisk_root="${cdroot}/data/ramdisk"
	mkdir -p "${ramdisk_root}"
	cd "${release}"
	tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
	cd "${cwd}"
	install -o root -g wheel -m 755 "init.sh.in" "${ramdisk_root}/init.sh"
	sed "s/@VOLUME@/${vol}/" "init.sh.in" > "${ramdisk_root}/init.sh"
	mkdir "${ramdisk_root}/dev"
	mkdir "${ramdisk_root}/etc"
	touch "${ramdisk_root}/etc/fstab"
	makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
	gzip "${cdroot}/data/ramdisk.ufs"
	rm -rf "${ramdisk_root}"
}

boot () {
	cd "${release}"
	tar -cf - --exclude boot/kernel boot | tar -xf - -C "${cdroot}"
	for kfile in kernel geom_uzip.ko nullfs.ko tmpfs.ko unionfs.ko; do
		tar -cf - boot/kernel/${kfile} | tar -xf - -C "${cdroot}"
	done
	cd "${cwd}"
	install -o root -g wheel -m 644 "loader.conf" "${cdroot}/boot/"
}

image() 
{
  cd "${cdroot}"
  mkisofs -iso-level 4 -R -l -ldots -allow-lowercase -allow-multidot -V "GhostBSD" -o "/tmp/livecd/ghostbsd.iso" -no-emul-boot -b boot/cdboot .
}

		

make_iso()
{
  # Use GRUB to create the hybrid DVD/USB image
  echo "Creating ISO..."
  cat << EOF >/tmp/xorriso
ARGS=\`echo \$@ | sed 's|-hfsplus ||g'\`
xorriso \$ARGS
EOF
  chmod 755 /tmp/xorriso
  grub-mkrescue --xorriso=/tmp/xorriso -o ${livecd}/ghostbsd.iso ${cdroot} -- -volid ${vol}
  if [ $? -ne 0 ] ; then
    echo "Failed running grub-mkrescue"
    exit 1
  fi
echo "### ISO created ###"
}