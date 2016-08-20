#!/bin/bash

# Move into place if a directory is provided
if [ -n "${1}" ]; then
	if [ -d "${1}" ]; then
		cd "${1}"
	else
		echo "Usage: ${0} [path]" 1>&2
		exit 1
	fi
fi

# Scan for media files
for i in *.mp4 *.mkv *.m4v; do
	YTID="`echo "${i}" | sed 's%^S20[0-9][0-9]E[0-9]* - \(.*\)\.m[pk4][4v]%\1%'`"
	if [ -z "${YTID}" ] || [ "${YTID}" == "${i}" ]; then
		continue
	fi

	# Find related meta files
	META="${YTID}.meta"
	if [ -s "${META}" ]; then
		continue
	fi

	# Find the media file mtime
	DATE="`stat -c '%Y' "${i}"`"
	if [ -z "${DATE}" ]; then
		echo "Could not determine date for: ${i}" 1>&2
		continue
	fi

	# Add missing meta files
	echo "# Autogenerated" > "${META}"
	echo "date = ${DATE}" >> "${META}"
	touch -r "${i}" "${META}"
done

# Cleanup
exit 0