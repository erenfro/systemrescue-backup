#!/bin/bash

scriptPath="$(dirname "$(readlink -f "$0")")"

if [[ ! -f "${scriptPath}/profiles.toml" ]]; then
    cp "${scriptPath}/templates/profiles.toml" "${scriptPath}/profiles.toml"
fi
if [[ ! -f "${scriptPath}/excludes" ]]; then
    cp "${scriptPath}/templates/excludes" "${scriptPath}/excludes"
fi
if [[ ! -f "${scriptPath}/key" ]]; then
    resticprofile generate --random-key > "${scriptPath}/key"
fi
chmod go-rwx "${scriptPath}/key" "${scriptPath}/profiles.toml" "${scriptPath}/excludes"
