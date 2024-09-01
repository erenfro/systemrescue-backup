#!/bin/bash 

###########################################################
### Utility & Common Functions
###########################################################

function is_bin_in_path {
    builtin type -P "$1" &>/dev/null
}

###########################################################
### BACKUP and RESTORE FUNCTIONS
###########################################################

#dumpPartitions() {
backup_partitions() {
    local rootPart rootDisk

    rootPart="$(findmnt -no SOURCE / | sed -E 's/\[.*\]$//')"
    rootDisk="/dev/$(lsblk -no pkname "$rootPart" | head -n1)"

    sfdisk --dump "$rootDisk" > "${restoreDir}/sfdisk.dump"
    blkid -o export "$rootPart" > "${restoreDir}/blkid.dump"
    btrfs subvolume list -p / > "${restoreDir}/btrfs.dump"
    mount | grep "$rootPart" > "${restoreDir}/mounts.dump"
}

#restorePartitions() {
restore_partitions() {
    local rootPart rootDisk

    rootPart="$1"
    rootDisk="$2"

    if [[ -z "$rootDisk" || -z "$rootPart" ]]; then
        echo "ERROR, restorePartitions not supplied with rootDisk and/or rootPartition"
        exit 200
    fi

    # Restore Partition Table (without modification)
    sfdisk "$rootDisk" < "${restoreDir}/sfdisk.dump"

    # Restore UUIDs
    while read -r line; do
        if [[ $line == UUID=* ]]; then
            eval "$line"
            tune2fs "$rootPart" -U "$UUID"
        fi
    done < "${restoreDir}/blkid.dump"

    echo "Partition table and UUID information have been restored."
}

#restoreBtrFSSubvolumes() {
restore_btrfs_subvolumes() {
    local rootBase subvolID subvolPath

    rootBase="$1"

    while read -r line; do
        # Extract the subvolume ID and Path
        subvolID="$(echo "$line" | awk '{print $2}')"
        subvolPath="$(echo "$line" | awk '{print $NF}')"

        # Restore the subvolume
        btrfs subvolume create "${rootBase}/${subvolPath}"
    done < "${restoreDir}/btrfs.dump"
}

#restoreBtrFSMounts() {
restore_btfs_mounts() {
    local rootBase mountSource mountDest

    rootBase="$1"

    while read -r line; do
        # Extract mount source and destination
        mountSource="$(echo "$line" | awk '{print $1}')"
        mountDest="$(echo "$line" | awk '{print $3}')"

        # Mount the subvolume
        mount "$mountSource" "${rootBase}/${mountDest}"
    done < "$restoreDir/mounts.dump"
}
