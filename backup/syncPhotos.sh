#!/bin/bash

export BASE_LOCAL="/Volumes/iPhoto"
export BASE_REMOTE="/Volumes/webdav.opendrive.com"
TARGET="Shared.photolibrary"

# Mount the remote drive if needed
MOUNTED_REMOTE=0
if [ ! -d "${BASE_REMOTE}" ]; then
	mkdir "${BASE_REMOTE}"
fi
if [ ! -d "${BASE_REMOTE}/${TARGET}" ]; then
	MOUNTED_REMOTE=1
	if ! mount_webdav -s https://webdav.opendrive.com "${BASE_REMOTE}"; then
		echo "Unable to mount remote drive" 1>&2
		exit 1
	fi
fi

# Mount th local drive if needed
MOUNTED_LOCAL=0
if [ ! -d "${BASE_LOCAL}" ]; then
	MOUNTED_LOCAL=1
	hdiutil attach -readonly /mnt/media/Pictures/iPhoto.sparsebundle >/dev/null 2>&1
fi

# Backup if all went well
if [ -d "${BASE_REMOTE}" ] && [ -d "${BASE_LOCAL}" ]; then
	~/bin/video/backup/sync.sh "${TARGET}" 1000
fi

# Detach the local drive if we mounted it
if [ -d "${BASE_LOCAL}" ] && [ $MOUNTED_LOCAL -gt 0 ]; then
	hdiutil detach "${BASE_LOCAL}" >/dev/null 2>&1
fi

# Detach the remote drive if we mounted it
if [ -d "${BASE_REMOTE}" ] &&[ $MOUNTED_REMOTE -gt 0 ]; then
	umount "${BASE_REMOTE}"
fi

# Always exit cleanly
exit 0
