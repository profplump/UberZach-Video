#!/bin/bash

# Command-line parameters
M3U8="${1}"
PREFIX="${2}"
if [ ! -r "${M3U8}" ]; then
	echo "Usage: ${0} input_m3u8 [uri_prefix]" 1>&2
	exit 1
fi

# Find the highest-resolution/highest-bandwidth stream
BANDWIDTH="`cat "${M3U8}" | grep '^#EXT-X-STREAM-INF:' | \
	sed 's%^.*[,:]BANDWIDTH=\([0-9]*\).*,RESOLUTION=\([0-9]*\)x\([0-9]*\).*$%\2 \1%' | \
		sort -n | tail -n 1 | cut -d ' ' -f 2`"

# Extract the URI from the line after that stream
URI="`cat "${M3U8}" | grep -A1 "BANDWIDTH=${BANDWIDTH}" | tail -n 1`"

# Output
echo "${PREFIX}${URI}"

# Cleanup
exit 0