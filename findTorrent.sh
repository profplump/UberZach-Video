#!/bin/bash

# Parameters
DEBUG=$(( $DEBUG + 1 ))
if [ -z "${TIMEOUT}" ]; then
	TIMEOUT=600
fi
VIDEO_DIR="${HOME}/bin/video"
EXCLUDES_FILE="${HOME}/.findTorrent.exclude"

# Find with timeout, pass URLs to downloader
"${VIDEO_DIR}/timeout" -t "${TIMEOUT}" \
	"${VIDEO_DIR}/findTorrent.pl" "${1}" | \
	"${VIDEO_DIR}/download.sh"

# Check for errors
RET=$?
if [ $RET -ne 0 ]; then
	if [ $RET -eq 143 ]; then
		echo "Timeout (${TIMEOUT}) searching: ${1}" 1>&2
	else
		echo "Error (${RET}) searching: ${1}" 1>&2
	fi
fi

# Pass status up the chain
exit $RET
