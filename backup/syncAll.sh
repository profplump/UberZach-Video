#!/bin/bash

# Config
VIDEO_DIR="${HOME}/bin/video"

# Bail silently if ~/.archive_disable exists
if [ -e ~/.archive_disable ]; then
	exit 0
fi

# Ensure the remote drive is available
"${VIDEO_DIR}/backup/checkMount.sh"

# Ensure we have a valid TMPDIR
if [ ! -d "${TMPDIR}" ]; then
        TMPDIR="`getconf DARWIN_USER_TEMP_DIR 2>/dev/null`"
        if [ ! -d "${TMPDIR}" ]; then
                TMPDIR="/var/tmp"
        fi
        if [ ! -d "${TMPDIR}" ]; then
                TMPDIR="/tmp"
        fi
fi

# Bail if we're already running
PID_FILE="${TMPDIR}/`basename "${0}"`.pid"
touch "${PID_FILE}"
read SYNC_PID < "${PID_FILE}"
if [ -n "${SYNC_PID}" ] && ps -A -o pid | grep -q "${SYNC_PID}"; then
	exit 0
else
	echo $$ > "${PID_FILE}"
fi

# Fast updates for previously-synced paths
"${VIDEO_DIR}/backup/sync.sh" DMX 100

# Slower updates for recently added paths
"${VIDEO_DIR}/backup/sync.sh" iTunes/iTunes\ Music 10
"${VIDEO_DIR}/backup/sync.sh" Backups 1
"${VIDEO_DIR}/backup/sync.sh" Movies 1
"${VIDEO_DIR}/backup/sync.sh" School 2
"${VIDEO_DIR}/backup/sync.sh" YouTube 6
"${VIDEO_DIR}/backup/sync.sh" TV 2

# Always exit cleanly
rm -f "${PID_FILE}"
exit 0
