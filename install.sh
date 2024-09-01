#!/bin/bash

resticVersion="0.16.4"
resticprofileVersion="0.27.0"

mkdir /tmp/restic-install || exit 1
pushd /tmp/restic-install &>/dev/null || exit 1
wget "https://github.com/restic/restic/releases/download/v${resticVersion}/restic_${resticVersion}_linux_amd64.bz2"
bunzip2 "restic_${resticVersion}_linux_amd64.bz2"
wget "https://github.com/creativeprojects/resticprofile/releases/download/v${resticprofileVersion}/resticprofile_${resticprofileVersion}_linux_amd64.tar.gz"
tar xvfz "resticprofile_${resticprofileVersion}_linux_amd64.tar.gz"
rm LICENSE README.md "resticprofile_${resticprofileVersion}.tar.gz"
chown root:root restic*
chmod 755 restic*
mv "restic_${resticVersion}_linux_amd64" /usr/local/bin/restic
mv resticprofile /usr/local/bin/resticprofile
popd &>/dev/null
rm -rf /tmp/restic-install
