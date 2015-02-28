#!/bin/bash

# Bail if the media share isn't available
if ! ~/bin/video/isMediaMounted; then
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

	# Actual search, with timeout to ensure we don't get stuck
	URLS="`~/bin/video/timeout -t 300 ~/bin/video/findTorrent.pl "${SERIES}"`"
	if [ $? -ne 0 ]; then
		echo "Error searching: ${SERIES}"
		continue
	fi

	# Download, if we found anything
	if [ -n "${URLS}" ]; then
		echo "${URLS}" | ~/bin/download
		if [ $? -ne 0 ]; then
			echo "Error downloading: ${SERIES}"
			continue
		fi
	fi

# Loop on the null-delimited list of monitored series/seasons
done < <(~/bin/video/torrentMonitored.pl null)

# Cleanup
exit 0
