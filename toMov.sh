#!/bin/bash

# Command line
inFile="${1}"
outFile="${2}"
movLength="${3}"
if [ -z "${inFile}" ] || [ ! -e "${inFile}" ]; then
	echo "Usage: `basename "${0}"` input_file [output_file] [mov_length]" 1>&2
	exit 1
fi

# Grab some codec info
INFO="`~/bin/video/movInfo.pl "${inFile}"`"
ACODECS="`echo "${INFO}" | grep AUDIO_CODEC`"
if [ -z "${ACODECS}" ]; then
	echo "`basename "${0}"`: Could not determine audio codec" 1>&2
	exit 2
fi
VCODECS="`echo "${INFO}" | grep VIDEO_CODEC`"
if [ -z "${VCODECS}" ]; then
	echo "`basename "${0}"`: Could not determine video codec" 1>&2
	exit 2
fi

# Exclude files with DTS soundtracks or MPEG-1/2 streams
if echo "${ACODECS}" | grep -q ffdca; then
	exit 1
elif echo "${VCODECS}" | grep -q ffmpeg[12]; then
	exit 1
fi

# Construct the output file name
if [ -z "${outFile}" ]; then
	# Use the input file name with a .mov extension
	outFile="`basename "${inFile}"`"
	outFile="`echo "${outFile}" | sed 's%\.[A-Za-z0-9]*$%%'`"
	outFile="`dirname "${inFile}"`/${outFile}"
fi

# Convert to MKV
tmpFile="`mktemp -t toMov`"
outFile="${outFile}.mkv"
mkvmerge -o "${tmpFile}" "${inFile}"

# Check for errors
if [ ! -e "${tmpFile}" ] || [ `stat -f '%z' "${tmpFile}"` -lt 1000 ]; then
	echo "`basename "${0}"`: Error creating output file for input: ${inFile}" 1>&2

	# Try to recode (with Handbrake/ffmpeg) if mkvmerge fails
	echo "`basename "${0}"`: Attempting recode instead..." 1>&2
	~/bin/video/recode "${inFile}"
	exit "${?}"
fi

# Move into place, dropping the original
tmpOut="`mktemp "${outFile}.XXXXXXXX"`"
cp -X "${tmpFile}" "${tmpOut}" && rm "${inFile}" && mv "${tmpOut}" "${outFile}"
rm -f "${tmpFile}"

# Exit cleanly
exit 0
