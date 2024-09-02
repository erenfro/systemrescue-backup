#!/bin/bash

###########################################################
### Default global configuration definitions
###########################################################

restic_version="0.17.0"
resticprofile_version="0.28.0"
systemrescuecd_version="11.02"
backup_engine="resticprofile"

scriptPath="$(dirname "$(readlink -f "$0")")"
configPath="$(readlink -f "${scriptPath}/../config")"

if [[ ! -d "${configPath}" ]]; then
    # Start searching for common configuration paths
    if [[ -r "$HOME/.config/systemrescue-backup/srb.cfg" ]]; then
        configPath="$HOME/.config/systemrescue-backup"
    elif [[ -r "/etc/systemrescue-backup/srb.cfg" ]]; then
        configPath="/etc/systemrescue-backup"
    else
        echoerr "No configuration file path found. Defaults will be used." 1>&2
    fi
fi

if [[ -f "${configPath}/srb.cfg" ]]; then
    # Fail on any issues loading configuration
    trap "echo \"ERROR: Configuration failed to load without error\"" ERR
    set -e
    source "${configPath}/srb.cfg"
    set +e
    trap - ERR
fi


###########################################################
### Utility & Common Functions
###########################################################

is_bin_in_path() {
    builtin type -P "$1" &>/dev/null
}

echoerr() {
    echo "$*" 1>&2
}

exit_fail() {
    local rc=$1
    shift

    echoerr "$*"
    exit "$rc"
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
