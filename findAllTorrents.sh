#!/bin/bash

# Parameters
if [ -z "${TIMEOUT}" ]; then
	TIMEOUT=600
fi
VIDEO_DIR="${HOME}/bin/video"

# Bail if the media share isn't available
if ! "${VIDEO_DIR}/isMediaMounted"; then
        exit 0
fi

# Allow easy cancelation
control_c() {
	echo "Canceled" 1>&2
	exit 1
}
trap control_c SIGINT
trap control_c SIGTERM

# Provide a method to skip ahead in the alphabetical list of series
REGEX=""
if [ -n "${1}" ]; then
	if ! echo "${1}" | grep -qi '^[a-z]$'; then
		echo "Usage: `basename "${0}"` [skip_to_char]" 1>&2
		exit 1
	fi
	REGEX="`echo "${1}" | tr 'A-Z' 'a-z'`"
	REGEX='^[0-9a-'"${REGEX}"']'
fi

# Run a search for each monitored series
while read -d $'\0' SERIES ; do

	# Skip matching series
	if [ -n "${REGEX}" ]; then
		TITLE="`dirname "${SERIES}"`"
		TITLE="`basename "${TITLE}"`"
		if echo "${TITLE}" | grep -qi "${REGEX}"; then
			continue
		fi
	fi

	# Search and download
	DEBUG=-1 "${VIDEO_DIR}/findTorrent.sh" "${SERIES}"
	if [ $? -ne 0 ]; then
		echo "Skipping: ${SERIES}" 1>&2
		continue
	fi

# Loop on the null-delimited list of monitored series/seasons
done < <("${VIDEO_DIR}/torrentMonitored.pl" null)

# Cleanup
exit 0
