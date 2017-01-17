#!/bin/bash

# Command-line parameters
URI="${1}"
if [ -z "${URI}" ]; then
	echo "Usage: ${0} uri" 1>&2
	exit 1
fi

# Fetch the M3U8
M3U8="`mktemp -t 'M3U8'`"
curl -4 -s -o "${M3U8}" "${URI}"
PREFIX="`echo "${URI}" | sed 's%^\(.*\)\/.*$%\1%'`"

# Find the highest-resolution/highest-bandwidth stream
BANDWIDTH="`cat "${M3U8}" | grep '^#EXT-X-STREAM-INF:' | \
	sed 's%^.*[,:]BANDWIDTH=\([0-9]*\).*,RESOLUTION=\([0-9]*\)x\([0-9]*\).*$%\2 \1%' | \
		sort -n | tail -n 1 | cut -d ' ' -f 2`"

# Extract the URI from the line after that stream
URI="`cat "${M3U8}" | grep -A1 "BANDWIDTH=${BANDWIDTH}" | tail -n 1`"

# Output
echo "${PREFIX}/${URI}"

# Cleanup
rm -f "${M3U8}"
exit 0
