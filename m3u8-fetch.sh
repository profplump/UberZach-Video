#!/bin/bash

URI="${1}"
FILE="${2}"
if [ -z "${URI}" ] || [ -z "${FILE}" ] || [ -e "${FILE}" ]; then
	echo "Usage: ${0} URI output_file" 1>&2
	exit 1
fi

# Parse the playlist if needed
if ! echo "${URI}" | grep -q -i '\.m3u8$'; then
	URI="`~/bin/video/m3u8-uri.sh "${URI}"`"
fi

# Fetch
ffmpeg -i "${URI}" -bsf:a aac_adtstoasc -vcodec copy -c copy "${FILE}"
