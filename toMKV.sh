#!/bin/bash

# Defaults
if [ -z "${MIN_AVI_SIZE}" ]; then
	MIN_AVI_SIZE=$(( 350 * 1024 * 1024 ))
fi

function tryRecode() {
	file="${1}"

	# Try to recode with Handbrake/ffmpeg
	if ~/bin/video/canRecode.sh; then
		echo "`basename "${0}"`: Attempting recode instead..." 1>&2
		~/bin/video/recode "${file}"
		exit "${?}"
	else
		echo "`basename "${0}"`: Unable to recode." 1>&2
		exit 1
	fi
}

# Command line
inFile="${1}"
outFile="${2}"
if [ -z "${inFile}" ] || [ ! -e "${inFile}" ]; then
	echo "Usage: `basename "${0}"` input_file [output_file]" 1>&2
	exit 1
fi

# AVIs are always unlikely
if echo "${inFile}" | grep -qi '\.avi$' && [ `wc -c < "${inFile}"` -lt $MIN_AVI_SIZE ]; then
	echo "Deleting unlikely AVI: ${inFile}" 1>&2
	rm -f "${inFile}"
	exit 3
fi

# Grab some codec info
INFO="`~/bin/video/movInfo.pl "${inFile}" 2>/dev/null`"
VCODECS="`echo "${INFO}" | grep VIDEO_CODEC`"
if [ -z "${VCODECS}" ]; then
	echo "`basename "${0}"`: Could not determine video codec: ${inFile}" 1>&2

	# Try to recode -- this does not return
	tryRecode "${inFile}"
fi

# Exclude files with MPEG-1/2 streams
if echo "${VCODECS}" | grep -q ffmpeg[12]; then
	echo "Usage: `basename "${0}"` input_file [output_file]" 1>&2
	exit 1
fi

# Construct the output file name
if [ -z "${outFile}" ]; then
	outFile="`basename "${inFile}"`"
	outFile="`echo "${outFile}" | sed 's%\.[A-Za-z0-9]*$%%'`"
	outFile="`dirname "${inFile}"`/${outFile}"
fi

# Merge external subtitles, if they exist
srtFile="`echo "${inFile}" | sed 's%\.[^\.]*$%%'`.srt"
if [ ! -e "${srtFile}" ]; then
	srtFile="`echo "${inFile}" | sed 's%\.[^\.]*$%%'`.ssa"
fi
if [ ! -e "${srtFile}" ]; then
	srtFile=""
fi

# Convert to MKV
# Hide some common AVI conversion warnings
tmpFile="`mktemp -t toMKV`"
outFile="${outFile}.mkv"
if [ -n "${srtFile}" ]; then
	OUT="`mkvmerge --quiet --default-language eng -o "${tmpFile}" "${inFile}" "${srtFile}" 2>&1`"
else
	OUT="`mkvmerge --quiet --default-language eng -o "${tmpFile}" "${inFile}" 2>&1`"
fi
echo "${OUT}" | grep -v "The AVC video track is missing the 'CTTS' atom for frame timecode offsets."

# Check for errors
if [ ! -e "${tmpFile}" ] || [ `stat -f '%z' "${tmpFile}"` -lt 1000 ]; then
	echo "`basename "${0}"`: Error creating output file for input: ${inFile}" 1>&2

	# Try to recode -- this does not return
	tryRecode "${inFile}"
fi

# Move into place, dropping the original
tmpOut="`mktemp "${outFile}.XXXXXXXX"`"
cp -X "${tmpFile}" "${tmpOut}" && rm "${inFile}" && mv "${tmpOut}" "${outFile}"
rm -f "${tmpFile}" "${srtFile}"

# Re-label undefined audio tracks in files with no English tracks
~/bin/video/undToEng.pl "${outFile}"

# Exit cleanly
exit 0
