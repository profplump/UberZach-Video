#!/bin/bash

# Config
VIDEO_DIR="${HOME}/bin/video"

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
read SCAN_PID < "${PID_FILE}"
if [ -n "${SCAN_PID}" ] && ps -A -o pid | grep -q "${SCAN_PID}"; then
	exit 0
else
	echo $$ > "${PID_FILE}"
fi

# Scan all our local directories
"${VIDEO_DIR}/backup/scanLocal.sh" Backups
"${VIDEO_DIR}/backup/scanLocal.sh" DMX
"${VIDEO_DIR}/backup/scanLocal.sh" iTunes
"${VIDEO_DIR}/backup/scanLocal.sh" Movies
"${VIDEO_DIR}/backup/scanLocal.sh" School
"${VIDEO_DIR}/backup/scanLocal.sh" TV
"${VIDEO_DIR}/backup/scanLocal.sh" YouTube

# Always exit cleanly
rm -f "${PID_FILE}"
exit 0

