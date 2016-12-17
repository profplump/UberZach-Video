#!/bin/bash

URI="${1}"
FILE="${2}"
if [ -z "${URI}" ] || [ -z "${FILE}" ] || [ -e "${FILE}" ]; then
	echo "Usage: ${0} URI output_file" 1>&2
	exit 1
fi

ffmpeg -i "${URI}" -bsf:a aac_adtstoasc -vcodec copy -c copy "${FILE}"
