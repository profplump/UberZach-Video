#!/bin/bash

# Config
TIMEOUT=20
export BASE_LOCAL="/Volumes/iPhoto"
SOURCE_LOCAL="/mnt/media/Pictures/iPhoto.sparsebundle"
TARGET="Shared.photolibrary"
if [ -z "${VIDEO_DIR}" ]; then
	VIDEO_DIR="${HOME}/bin/video"
fi

# Ensure the remote drive is available
"${VIDEO_DIR}/backup/checkMount.sh" >/dev/null 2>&1

# Mount the local drive if needed
MOUNTED_LOCAL=0
if [ ! -d "${BASE_LOCAL}" ]; then
	MOUNTED_LOCAL=1
	hdiutil attach -readonly "${SOURCE_LOCAL}" >/dev/null 2>&1
fi

# Backup if all went well
if [ -d "${BASE_LOCAL}" ]; then
	"${VIDEO_DIR}/backup/sync.sh" "${TARGET}" 1000
fi

# Detach the local drive if we mounted it
if [ -d "${BASE_LOCAL}" ] && [ $MOUNTED_LOCAL -gt 0 ]; then
	hdiutil detach "${BASE_LOCAL}" >/dev/null 2>&1
fi

# Always ask the remote drive to detach. There is no other use.
timeout "${TIMEOUT}" osascript -e 'tell application "OpenDrive" to quit'

# Always exit cleanly
exit 0
