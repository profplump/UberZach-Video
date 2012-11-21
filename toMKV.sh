#!/bin/bash

# Command line
inFile="${1}"
outFile="${2}"
if [ -z "${inFile}" ] || [ ! -e "${inFile}" ]; then
	echo "Usage: `basename "${0}"` input_file [output_file]" 1>&2
	exit 1
fi

# Construct the output file name
if [ -z "${outFile}" ]; then
	# Use the input file name with a .mov extension
	outFile="`basename "${inFile}"`"
	outFile="`echo "${outFile}" | sed 's%\.[A-Za-z0-9]*$%%'`"
	outFile="`dirname "${inFile}"`/${outFile}"
fi

# Merge external subtitles, if they exist
srtFile="`echo "${inFile}" | sed 's%\.[^\.]*$%%'`.srt"
if [ ! -e "${srtFile}" ]; then
	srtFile=""
fi

# Convert to MKV
tmpFile="`mktemp -t toMKV`"
outFile="${outFile}.mkv"
mkvmerge --quiet -o "${tmpFile}" "${inFile}" ${srtFile}

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
rm -f "${tmpFile}" "${srtFile}"

# Exit cleanly
exit 0
