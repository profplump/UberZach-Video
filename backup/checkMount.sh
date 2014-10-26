#!/bin/bash

# Config
if [ -z "${BASE_REMOTE}" ]; then
	BASE_REMOTE="/mnt/remote/opendrive"
fi
WC="${BASE_REMOTE}/.live_check"
TIMEOUT=20

# State
FAILED=0

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
	SUOD=""
	if [ $UID -gt 0 ]; then
		SUDO="sudo"
	fi

	DASH_NAME="`echo "${BASE_REMOTE}" | cut -d '/' -f 2- | sed 's%/%-%g'`"
	PID=`ps ax -o pid=,command= | grep 'mount.davfs' | grep "${BASE_REMOTE}" | awk '{print $1}'`

	echo 'Resetting WebDAV mount' 1>&2

	if [ -n "${PID}" ] && [ $PID -gt 1 ]; then
		${SUDO} kill -9 $PID
	fi

	${SUDO} umount "${BASE_REMOTE}"
	${SUDO} rm -f "/var/run/mount.davfs/${DASH_NAME}.pid"
	${SUDO} mount "${BASE_REMOTE}"

	exit 1
fi

# Always exit cleanly
exit 0
