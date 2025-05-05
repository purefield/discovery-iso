#!/bin/bash
set -euo pipefail
cd build

# --- Download CoreOS ISO ---
if [ ! -e coreos.live.x86_64.iso ]; then
    curl -o coreos.live.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/latest/rhcos-live.x86_64.iso
fi

# --- Create Ignition config ---
mkdir -p iso-overlay/opt/images
cp $HOME/coreos-diagnostic.oci iso-overlay/opt/images/

volid=$(isoinfo -d -i coreos.live.x86_64.iso | grep "Volume id" | awk -F ': ' '{print $2}')
sed -i "s/VOLID/${volid}/g" $HOME/diagnostic.bu
butane $HOME/diagnostic.bu -p -o config.ign

# --- Embed Ignition config into ISO ---
cp coreos.live.x86_64.iso coreos-diagnostic.iso
coreos-installer iso ignition embed -i config.ign coreos-diagnostic.iso

# --- Inject overlay files ---
mkdir -p iso-root
xorriso -osirrox on -indev coreos-diagnostic.iso -extract / iso-root
mkdir -p iso-root/opt/images
cp iso-overlay/opt/images/coreos-diagnostic.oci iso-root/opt/images/

# Timestamp the built
ISO_TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
# Inject the timestamp into the GRUB menu
chmod +w iso-root/EFI/redhat/grub.cfg iso-root/isolinux/isolinux.cfg
chmod +wx iso-root/EFI/redhat/ iso-root/isolinux/
sed -i "s/CoreOS (Live)/CoreOS (Live) Diagnostics (Built: $ISO_TIMESTAMP)/g" iso-root/EFI/redhat/grub.cfg iso-root/isolinux/isolinux.cfg
chmod -w iso-root/EFI/redhat/grub.cfg iso-root/isolinux/isolinux.cfg

# Ensure Required Files Exist and Are Writable
[[ -f iso-root/isolinux/isolinux.bin ]] || echo "Missing isolinux.bin!"
[[ -f iso-root/images/efiboot.img ]] || echo "Missing efiboot.img!"
chmod +w iso-root/isolinux/isolinux.bin
chmod +w iso-root/EFI/redhat/grub.cfg
echo "Contents of iso-root/isolinux:"
ls -l iso-root/isolinux
echo "Contents of iso-root/images:"
ls -l iso-root/images

pwd

# --- Rebuild ISO with overlay ---
volid=$(isoinfo -d -i coreos-diagnostic.iso | grep "Volume id" | awk -F ': ' '{print $2}')
xorriso -as mkisofs \
  -o coreos-diagnostic-final.iso \
  -V "$volid" \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  -J -R -f -input-charset utf-8 \
  iso-root

# Sanity Checks
echo "Check Rebuilt ISO contains .oci image"
xorriso -indev coreos-diagnostic-final.iso -find /opt/images -exec lsdl
