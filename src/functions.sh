#!/bin/bash

###########################################################
### Default global configuration definitions
###########################################################

declare -r systemrescue_version="0.0.1"
systemrescue_cd_version="11.02"
systemrescue_data_dir="/var/backups/systemrescue-backup"
systemrescue_cache_dir="/var/cache/systemrescue-backup"
systemrescue_temp_dir="/tmp/systemrescue-backup"
backup_engine="resticprofile"

scriptPath="$(dirname "$(readlink -f "$0")")"
configPath="$(readlink -f "${scriptPath}/../config")"
debug=false


###########################################################
### Utility & Common Functions
###########################################################

is_bin_in_path() {
    builtin type -P "$1" &>/dev/null
}

# Check if argument is number.
is_num() {
    [[ -n "$1" && "$1" -eq "$1" ]] 2>/dev/null
}

# Convert signal name to signal number.
to_sig_num() {
    if is_num "$1"; then
      # Signal is already number.
      kill -l "$1" >/dev/null # Check that signal number is valid.
      echo    "$1"            # Return result.
    else
      # Convert to signal number.
      kill -l "$1"
    fi
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

load_config() {
    if [[ -f "${configPath}/srb.cfg" ]]; then
        # Fail on any issues loading configuration
        trap "echo \"ERROR: Configuration failed to load without error\"" ERR
        set -e
        source "${configPath}/srb.cfg"
        set +e
        trap - ERR
        echoreg -d "Loaded configuration file: ${configPath}/srb.cfg"
    fi
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
                    echoreg -d "+ Executing Script: $script"
                    if ! "$script"; then
                        echoerr "! Failed Script: $script ($?)"
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
                    echoreg -d "+ Loading Module: $script"
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

    echoreg -d "Loading Modules in: ${scriptPath}/${module}/${submod}/"
    load-parts "${scriptPath}/${module}/${submod}"
    echoreg -d "Loaded Modules in: ${scriptPath}/${module}/${submod}/"
}

run_modules() {
    local module="$1"
    local submodules=("init" "prepare" "execute" "finalize")
    local order mod

    for load in "${submodules[@]}"; do
        if [[ "$load" == "finalize" ]]; then
            order=("$backup_engine" "$module")
        else
            order=("$module" "$backup_engine")
        fi

        for mod in "${order[@]}"; do
            if ! load_module "$mod" "$load"; then
                exit_fail 200 "FATAL: Failed to load $module $load module. ($?)"
            fi
        done

        if [[ "$load" == "init" ]]; then
            load_config
        fi
    done
}

init_squashfs() {
    truncate -s0 "${systemrescue_data_dir}/sysrescue/build_into_srm/.squashfs-pseudo"
}

add_to_squashfs() {
    local input="$1"

    if $debug; then
        echo "Adding to SquashFS: $1"
    fi
    echo "$1" >> "${systemrescue_data_dir}/sysrescue/build_into_srm/.squashfs-pseudo"
}

add_path_to_squashfs() {
    local path="$1"
    local dir_perm="$2"
    local file_perm="$3"
    local file_owner="$4"
    local file_group="$5"
    local perm

    [[ -z "$dir_perm" ]]   && dir_perm="755"
    [[ -z "$file_perm" ]]  && file_perm="644"
    [[ -z "$file_owner" ]] && file_owner="root"
    [[ -z "$file_group" ]] && file_group="root"

    while read -r file; do
        if [[ -d "$file" ]]; then
            [[ "$dir_perm" == "match" ]] && perm="$(stat -c "%a" "$file")" || perm="$dir_perm"
            #add_to_squashfs "${file/${systemrescue_data_dir}\/sysrescue\/build_into_srm\///} m $dir_perm root root"
        elif [[ -f "$file" ]]; then
            [[ "$file_perm" == "match" ]] && perm="$(stat -c "%a" "$file")" || perm="$file_perm"
            #add_to_squashfs "${file/${systemrescue_data_dir}\/sysrescue\/build_into_srm\///} m $file_perm root root"
        fi
        add_to_squashfs "${file/${systemrescue_data_dir}\/sysrescue\/build_into_srm\///} m $perm root root"
    done < <(find "$path")
}

trap_add() {
    local handler="${1:?Handler required}"
    #local signal="${2:?Signal required}"
    local signals=("${@:2}")
    local hdls
    local signal

    if [[ "${#signals[@]}" -lt 1 ]]; then
        echo_fail 1 "Signal required"
    fi

    if $debug; then
        echo "====================================================="
    fi

    for signal in "${signals[@]}"; do
        hdls="$( trap -p "${signal}" | cut -f2 -d \' )"
        trap "${hdls}${hdls:+;}${handler}" "${signal}"
        if $debug; then
            echo "Adding Trap: $handler (${signal})"
            echo "Old Traps: $hdls"
        fi
    done

    if $debug; then
        echo "Current Traps:"
        trap -p "${signals[@]}"
    fi

    if $debug; then
        echo "====================================================="
    fi
}


###########################################################
### BACKUP and RESTORE FUNCTIONS
###########################################################

backup_partitions() {
    local rootPart rootDisk

    rootPart="$(findmnt -no SOURCE / | sed -E 's/\[.*\]$//')"
    rootDisk="/dev/$(lsblk -no pkname "$rootPart" | head -n1)"

    sfdisk --dump "$rootDisk" > "${restoreDir}/sfdisk.dump"
    blkid -o export "$rootPart" > "${restoreDir}/blkid.dump"
    btrfs subvolume list -p / > "${restoreDir}/btrfs.dump"
    mount | grep "$rootPart" > "${restoreDir}/mounts.dump"
}

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

restore_btrfs_mounts() {
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


###########################################################
### Initialization
###########################################################

if [[ ! -r "${configPath}/srb.cfg" ]]; then
    # Start searching for common configuration paths
    if [[ -r "$HOME/.config/systemrescue-backup/srb.cfg" ]]; then
        configPath="$HOME/.config/systemrescue-backup"
    elif [[ -r "/etc/systemrescue-backup/srb.cfg" ]]; then
        configPath="/etc/systemrescue-backup"
    else
        echoerr "Warning: No configuration file path found. Defaults will be used."
    fi
fi
