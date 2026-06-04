#!/bin/bash

set -e

#--------------------------------------------------

# Root Check

#--------------------------------------------------
if [[ $EUID -ne 0 ]]; then
echo "ERROR: Please run as root."
exit 1
fi

echo "========================================="
echo "       CREATE NEW LVM STORAGE"
echo "========================================="

#--------------------------------------------------

# STEP 1 - Rescan SCSI Devices

#--------------------------------------------------
echo
echo "[STEP 1] Rescanning SCSI devices..."

for device in /sys/class/scsi_device/*; do
echo 1 > "$device/device/rescan"
done

sleep 2

#--------------------------------------------------

# STEP 2 - Display Current Disk Layout

#--------------------------------------------------
echo
echo "[STEP 2] Available Disks"
echo "========================================="
lsblk
echo "========================================="

#--------------------------------------------------

# STEP 3 - Create New Partition

#--------------------------------------------------
echo
read -p "Enter Disk (example: /dev/sda): " DISK

if [[ ! -b "$DISK" ]]; then
echo "ERROR: Disk $DISK not found."
exit 1
fi

echo
fdisk -l "$DISK"

echo
read -p "Enter New Partition Number (example: 3): " PARTNUM

echo
echo "Creating partition ${DISK}${PARTNUM} ..."

(
echo n
echo p
echo $PARTNUM
echo
echo
echo w
) | fdisk "$DISK"

echo
echo "Reloading partition table..."
partprobe "$DISK"

sleep 3

PARTITION="${DISK}${PARTNUM}"

if [[ ! -b "$PARTITION" ]]; then
echo "ERROR: Partition $PARTITION not detected."
exit 1
fi

echo
echo "Partition Created Successfully : $PARTITION"

echo
lsblk

#--------------------------------------------------

# STEP 4 - User Input

#--------------------------------------------------
echo
read -p "Enter VG Name (example: vgdata): " VGNAME

if vgdisplay "$VGNAME" &>/dev/null; then
echo "ERROR: VG $VGNAME already exists."
exit 1
fi

read -p "Enter LV Name (example: mysql): " LVNAME

read -p "Filesystem [xfs/ext4] (default:xfs): " FSTYPE
FSTYPE=${FSTYPE:-xfs}

read -p "Enter Mount Folder Name (example: mysqldata): " FOLDER

# Remove leading slash if user enters /mysqldata

FOLDER=$(echo "$FOLDER" | sed 's#^/##')

MOUNTPOINT="/${FOLDER}"

#--------------------------------------------------

# Summary

#--------------------------------------------------
echo
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo "Disk        : $DISK"
echo "Partition   : $PARTITION"
echo "VG Name     : $VGNAME"
echo "LV Name     : $LVNAME"
echo "Filesystem  : $FSTYPE"
echo "Mount Point : $MOUNTPOINT"
echo "========================================="

read -p "Proceed? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" ]]; then
echo "Cancelled."
exit 0
fi

#--------------------------------------------------

# STEP 5 - Create Physical Volume

#--------------------------------------------------
echo
echo "[STEP 5] Creating Physical Volume..."
pvcreate "$PARTITION"

#--------------------------------------------------

# STEP 6 - Create Volume Group

#--------------------------------------------------
echo
echo "[STEP 6] Creating Volume Group..."
vgcreate "$VGNAME" "$PARTITION"

#--------------------------------------------------

# STEP 7 - Create Logical Volume

#--------------------------------------------------
echo
echo "[STEP 7] Creating Logical Volume..."
lvcreate -n "$LVNAME" -l 100%FREE "$VGNAME"

#--------------------------------------------------

# STEP 8 - Create Filesystem

#--------------------------------------------------
echo
echo "[STEP 8] Creating Filesystem..."

if [[ "$FSTYPE" == "xfs" ]]; then
mkfs.xfs -f "/dev/${VGNAME}/${LVNAME}"
else
mkfs.ext4 "/dev/${VGNAME}/${LVNAME}"
fi

#--------------------------------------------------

# STEP 9 - Create Mount Point

#--------------------------------------------------
echo
echo "[STEP 9] Creating Mount Point..."
mkdir -p "$MOUNTPOINT"

#--------------------------------------------------

# STEP 10 - Mount Filesystem

#--------------------------------------------------
echo
echo "[STEP 10] Mounting Filesystem..."
mount "/dev/${VGNAME}/${LVNAME}" "$MOUNTPOINT"

#--------------------------------------------------

# STEP 11 - Update fstab

#--------------------------------------------------
echo
echo "[STEP 11] Updating /etc/fstab..."

UUID=$(blkid -s UUID -o value "/dev/${VGNAME}/${LVNAME}")

echo "UUID=${UUID} ${MOUNTPOINT} ${FSTYPE} defaults 0 0" >> /etc/fstab

#--------------------------------------------------

# STEP 12 - Verify

#--------------------------------------------------
echo
echo "[STEP 12] Verifying..."

mount -a

echo
echo "========== VGS =========="
vgs

echo
echo "========== LVS =========="
lvs

echo
echo "========== FILESYSTEM =========="
df -h "$MOUNTPOINT"

echo
echo "========================================="
echo "SUCCESS : New LVM Storage Created"
echo "Mount Point : $MOUNTPOINT"
echo "========================================="
