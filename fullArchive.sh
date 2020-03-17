#!/bin/bash

if [ ! -d "${1}" ]; then
	echo "Usage: ${0} path" 1>&2
	exit 1
fi

# Clear last recode files every 15 days
if [ $(( `date '+%-d'` % 15 )) -eq 0 ]; then
	find "${1}" -type f -name .lastFindRecode -size 0 -delete
fi

# Force archive encoding
find "${1}" -maxdepth 2 -mindepth 2 -type d -print0 | \
	FULL_ARCHIVE=1 xargs -n 1 -0 ~/bin/video/folderToMKV.sh
