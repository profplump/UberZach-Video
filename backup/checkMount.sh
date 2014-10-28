#!/bin/bash

# Config
TIMEOUT=20
DARWIN_APP="/Applications/Zach/Internet/OpenDrive.app"
if [ -z "${VIDEO_DIR}" ]; then
	VIDEO_DIR="${HOME}/bin/video"
fi
if [ -z "${BASE_REMOTE}" ]; then
	BASE_REMOTE="`"${VIDEO_DIR}/backup/remoteDir.sh"`"
fi

# State
FAILED=0

# Command-line options
WC="${BASE_REMOTE}/.live_check"
if [ -n "${1}" ]; then
	WC="${BASE_REMOTE}/${1}/.write_check"
fi

# Stat check
if [ $FAILED -lt 1 ]; then
	if ! timeout "${TIMEOUT}" ls "${BASE_REMOTE}" >/dev/null 2>&1; then
		FAILED=1
	fi
fi

# Write check
if [ $FAILED -lt 1 ]; then
	timeout "${TIMEOUT}" touch "${WC}" >/dev/null 2>&1
	if [ ! -e "${WC}" ]; then
		FAILED=1
	fi

	timeout "${TIMEOUT}" rm -f "${WC}" >/dev/null 2>&1
	if [ $FAILED -lt 1 ] && [ -e "${WC}" ]; then
		FAILED=1
	fi
fi

# Reset if needed
if [ $FAILED -gt 0 ]; then
	echo 'Resetting OpenDrive mount' 1>&2

	if uname | grep -qi Darwin; then
		PID=`ps ax -o pid=,command= | grep -v grep | grep '/Contents/MacOS/OpenDrive' | awk '{print $1}'`
		if [ -n "${PID}" ]; then
			${SUDO} kill -9 $PID
		fi

		open "${DARWIN_APP}"

		# WebDAV mount
		#SOURCE_REMOTE="https://webdav.opendrive.com"
		#mount_webdav -s "${SOURCE_REMOTE}" "${BASE_REMOTE}"

	else
		SUOD=""
		if [ $UID -gt 0 ]; then
			SUDO="sudo"
		fi

		PID=`ps ax -o pid=,command= | grep -v grep | grep 'mount.davfs' | grep "${BASE_REMOTE}" | awk '{print $1}'`
		if [ -n "${PID}" ]; then
			${SUDO} kill -9 $PID
		fi

		if [ "`mount | awk '$3 == "'"${BASE_REMOTE}"'" { print $3 }'`" == "${BASE_REMOTE}" ]; then
			${SUDO} umount "${BASE_REMOTE}"
		fi

		DASH_NAME="`echo "${BASE_REMOTE}" | cut -d '/' -f 2- | sed 's%/%-%g'`"
		${SUDO} rm -f "/var/run/mount.davfs/${DASH_NAME}.pid"

		${SUDO} mount "${BASE_REMOTE}"
	fi

	exit 1
fi

# Exit cleanly
exit 0