#!/bin/bash

# Config
SYNC_BIN="${HOME}/bin/video/backup/sync.sh"

# Bail silently if ~/.archive_disable exists
if [ -e ~/.archive_disable ]; then
	exit 0
fi

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

# Slower updates for recently added paths
"${SYNC_BIN}" Backups 5
"${SYNC_BIN}" DMX 10
"${SYNC_BIN}" iTunes/iTunes\ Music 10
"${SYNC_BIN}" School 10
"${SYNC_BIN}" Movies 5
"${SYNC_BIN}" TV 5
"${SYNC_BIN}" YouTube 50

# Always exit cleanly
rm -f "${PID_FILE}"
exit 0
