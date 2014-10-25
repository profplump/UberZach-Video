#!/bin/bash

# User config
export BASE_LOCAL="/Volumes/iPhoto"
export BASE_REMOTE="/Volumes/webdav.opendrive.com"
SOURCE_LOCAL="/mnt/media/Pictures/iPhoto.sparsebundle"
SOURCE_REMOTE="https://webdav.opendrive.com"
TARGET="Shared.photolibrary"

# App config
RETRIES=10
SYNC_BIN="${HOME}/bin/video/backup/sync.sh"

# Mount the remote drive if needed
MOUNTED_REMOTE=0
if [ ! -d "${BASE_REMOTE}" ]; then
	# Mount may be timed out, which will fail the -d test
	if mount | grep -q "${BASE_REMOTE}"; then
		umount "${BASE_REMOTE}"
	fi
	mkdir "${BASE_REMOTE}"
fi
if [ ! -d "${BASE_REMOTE}/${TARGET}" ]; then
	MOUNTED_REMOTE=1
	FAIL_COUNT=0
	while ! mount_webdav -s "${SOURCE_REMOTE}" "${BASE_REMOTE}"; do
		if [ $FAIL_COUNT -gt $RETRIES ]; then
			echo "Unable to mount remote drive" 1>&2
			exit 1
		fi
		FAIL_COUNT=$(( $FAIL_COUNT + 1 ))
		sleep 5
	done
fi

# Mount th local drive if needed
MOUNTED_LOCAL=0
if [ ! -d "${BASE_LOCAL}" ]; then
	MOUNTED_LOCAL=1
	hdiutil attach -readonly "${SOURCE_LOCAL}" >/dev/null 2>&1
fi

# Backup if all went well
if [ -d "${BASE_REMOTE}" ] && [ -d "${BASE_LOCAL}" ]; then
	"${SYNC_BIN}" "${TARGET}" 1000
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
