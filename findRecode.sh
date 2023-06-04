#!/bin/bash

# Parameters
FOLDER="`~/bin/video/mediaPath`"
if [ -z "${MIN_RATE}" ]; then
	MIN_RATE=20000
fi
if [ -z "${MIN_SIZE}" ]; then
	MIN_SIZE="100M"
fi
if [ -z "${NAME_REGEX}" ]; then
	NAME_REGEX="\.(mov|avi|mkv|mp4|ts|mpg|mpeg|m4v)$"
fi
if [ -z "${CODEC_REGEX}" ]; then
	CODEC_REGEX='^(x264|Nx265)'
fi
if [ -z "${CODEC_BUILD_REGEX}" ]; then
	CODEC_BUILD_REGEX='^(x264 - core (79|112|120|125|129|130|142|148)|Nx265 \(build (95|206)\))'
fi
SCAN_DEPTH_FAST=10
SCAN_DEPTH_SLOW=100
STRINGS_MINLEN=100

# Standard overrides for the current official archive format
if [ -n "${FULL_ARCHIVE}" ]; then
	MIN_SIZE=50M
	MIN_RATE=100
	CODEC_BUILD_REGEX='Nx265 \(build (95|206)\)'
	# Don't limit the codec regex so we get faster scans against
	# things that we did encode but aren't in the archive format
	#CODEC_REGEX='^Nx265' 
fi

# Command-line overrides
if [ -n "${1}" ]; then
	FOLDER="${1}"
fi

# Name-based paramters
ZERO=0
if basename "${0}" | grep -q '0'; then
	ZERO=1
fi

# Sanity check
if [ ! -d "${FOLDER}" ]; then
	echo "Usage: `basename "${0}"` [folder]" 1>&2
	exit 1
fi

# Derived parameters
LAST_RECODE_FILE="`(cd "${FOLDER}" && pwd)`/.lastFindRecode"

# Environmental parameters
if [ -n "${NO_LAST_RECODE_FILE}" ]; then
	LAST_RECODE_FILE=""
fi

# Find large video files that match the regex filter
FILES="`find "${FOLDER}" -maxdepth 1 -type f -size "+${MIN_SIZE}" | grep -iE "${NAME_REGEX}"`"

# Record the last scan start time, in a temp file
LAST_RECODE_TMP=""
if [ -n "${LAST_RECODE_FILE}" ]; then
	LAST_RECODE_TMP="`mktemp "${LAST_RECODE_FILE}.XXXXXX" 2>/dev/null`"
fi

# We need a strings scratch file, apparently, since strings doesn't handle STDIN correctly
STRINGS_TMP="`mktemp -t findRecode`"

# Loop with newline-as-IFS
OLDIFS="${IFS}"
IFS=$'\n'
for i in ${FILES}; do

	# Skip invalid files
	if [ -z "${i}" ] || [ ! -r "${i}" ] || basename "${i}" | grep -q '^\._'; then
		continue
	fi

	# Skip files older than the LAST_RECODE_FILE mtime
	if [ -n "${LAST_RECODE_FILE}" ] && [ -f "${LAST_RECODE_FILE}" ] && [ "${i}" -ot "${LAST_RECODE_FILE}" ]; then
		continue
	fi

	# Find the x264/Nx265 header, if present. Scan deeper if the fast scan fails.
	head -c $(( $SCAN_DEPTH_FAST * 1024 * 1024 )) "${i}" | strings -n "${STRINGS_MINLEN}" > "${STRINGS_TMP}"
	if ! strings -n 1 "${STRINGS_TMP}" | grep -Eq "${CODEC_REGEX}"; then
		head -c $(( $SCAN_DEPTH_SLOW * 1024 * 1024 )) "${i}" | strings -n "${STRINGS_MINLEN}" > "${STRINGS_TMP}"
	fi

	# Check for binary junk that makes grep angry
	while ! head -c 1 "${STRINGS_TMP}" | grep -q '\w'; do
		STR_CLEAN="`mktemp -t findRecode.clean`"
		cat "${STRINGS_TMP}" | cut -b 3- > "${STR_CLEAN}"
		mv "${STR_CLEAN}" "${STRINGS_TMP}"
	done

	# Check for our particular HandBrake parameters
	HANDBRAKE=0
	if strings -n 1 "${STRINGS_TMP}" | grep -Eq "${CODEC_BUILD_REGEX}"; then
		HANDBRAKE=1
	elif strings -n 1 "${STRINGS_TMP}" | grep -q HandBrake; then
		echo "Matched literal 'HandBrake': ${i}" 1>&2
		HANDBRAKE=1
	fi

	# We do not want to recode videos that we already encoded
	if [ $HANDBRAKE -eq 1 ]; then
		continue
	fi

	# Skip files with low bitrates
	SIZE="`stat -f %z "${i}" 2>/dev/null`"
	if [ -z "${SIZE}" ]; then
		SIZE=1
	fi
	LENGTH="`~/bin/video/movInfo.pl "${i}" LENGTH 2>/dev/null | sed 's%\..*$%%'`"
	if [ -z "${LENGTH}" ] || [ $LENGTH -eq 0 ]; then
		LENGTH=1
	fi
	RATE=$(( $SIZE / $LENGTH ))
	if [ $RATE -le $MIN_RATE ]; then
		continue
	fi


	# If we're still around, the file matched all criteria
	if [ $ZERO -gt 0 ]; then
		echo -en "${i}\0"
	else
		echo "${i}"
	fi
done
IFS="${OLDIFS}"

# Remove the strings temp file
rm -f "${STRINGS_TMP}"

# Move the temporary timestamp file into place
if [ -n "${LAST_RECODE_TMP}" ]; then
	mv "${LAST_RECODE_TMP}" "${LAST_RECODE_FILE}"
fi
