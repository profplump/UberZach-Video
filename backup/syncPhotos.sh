#!/bin/bash

# User config
export BASE_LOCAL="/Volumes/iPhoto"
SOURCE_LOCAL="/mnt/media/Pictures/iPhoto.sparsebundle"
SOURCE_REMOTE="https://webdav.opendrive.com"
TARGET="Shared.photolibrary"

# App config
SYNC_BIN="${HOME}/bin/video/backup/sync.sh"

# Ensure the remote drive is available
"${VIDEO_DIR}/backup/checkMount.sh"

# Mount the local drive if needed
MOUNTED_LOCAL=0
if [ ! -d "${BASE_LOCAL}" ]; then
	MOUNTED_LOCAL=1
	hdiutil attach -readonly "${SOURCE_LOCAL}" >/dev/null 2>&1
fi

# Backup if all went well
if [ -d "${BASE_LOCAL}" ]; then
	"${SYNC_BIN}" "${TARGET}" 1000
fi

# Detach the local drive if we mounted it
if [ -d "${BASE_LOCAL}" ] && [ $MOUNTED_LOCAL -gt 0 ]; then
	hdiutil detach "${BASE_LOCAL}" >/dev/null 2>&1
fi

# Always exit cleanly
exit 0
