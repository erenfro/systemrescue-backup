#!/bin/bash

###########################################################
### Default global configuration definitions
###########################################################

declare -r systemrescue_version="0.0.1"
systemrescue_cd_version="11.02"
backup_engine="resticprofile"
restic_version="0.17.0"
resticprofile_version="0.28.0"

scriptPath="$(dirname "$(readlink -f "$0")")"
configPath="$(readlink -f "${scriptPath}/../config")"
debug=false

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

echoreg() {
    if [[ "$1" == "-d" ]]; then
        shift
        if $debug; then
            echo "$*" 1>&2
        fi
    else
        echo "$*" 1>&2
    fi
}

echoerr() {
    if [[ "$1" == "-d" ]]; then
        shift
        if $debug; then
            echo "$*" 1>&2
        fi
    else
        echo "$*" 1>&2
    fi
}

echodebug() {
    echo "$*" 1>&2
}

exit_fail() {
    local rc=$1
    shift

    echoerr "$*"
    exit "$rc"
}

run-parts() {
    if [[ $# -lt 1 ]]; then
        return 1
    elif [[ ! -d "$1" ]]; then
        return 2
    fi

    local script

    for script in "${1%/}"/*; do
        case $script in
            *~ | *.bak | */#*# | *.swp)
                : ;; # Ignore backup/editor files
            *.new | *.rpmsave | *.rpmorig | *.rpmnew)
                : ;; # Ignore package management files
            *)
                if [[ -x "$script" ]]; then
                    if ! "$script"; then
                        echoerr "$script failed"
                        return $?
                    fi
                fi
                ;;
        esac
    done
}

load-parts() {
    if [[ $# -lt 1 ]]; then
        echoerr -d "load-parts parameters are invalid"
        return 1
    elif [[ ! -d "$1" ]]; then
        echoerr -d "load-parts missing directory '$1'"
        return 2
    fi

    local script

    for script in "${1%/}"/*; do
        case $script in
            *~ | *.bak | */#*# | *.swp)
                : ;; # Ignore backup/editor files
            *.new | *.rpmsave | *.rpmorig | *.rpmnew)
                : ;; # Ignore package management files
            *)
                if [[ -r "$script" ]]; then
                    set -e
                    echoreg -d "Loading script: $script"
                    source "$script"
                    set +e
                fi
                ;;
        esac
    done
}

load_module() {
    local module="$1"
    local submod="$2"

    if [[ -z "$module" ]]; then
        echoerr -d "load_module missing module"
        return 1
    elif [[ -z "$submod" ]]; then
        echoerr -d "load_module missing submodule"
        return 2
    else
        if [[ ! -d "${scriptPath}/${module}" ]]; then
            echoerr -d "load_module missing module directory '${scriptPath}/${module}'"
            return 3
        elif [[ ! -d "${scriptPath}/${module}/${submod}" ]]; then
            echoerr -d "load_module missing submodule directory '${scriptPath}/${submod}'"
            return 4
        fi
    fi

    load-parts "${scriptPath}/${module}/${submod}"
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
