#!/bin/bash

# Parameters
FOLDER="`~/bin/video/mediaPath`"
MIN_RATE=275000
MIN_SIZE="425M"
MIN_HEIGHT=500
NAME_REGEX="\.(mov|avi|mkv|mp4|ts|mpg|mpeg|m4v)$"

# Command-line overrides
if [ -n "${1}" ]; then
	FOLDER="${1}"
fi
if [ -n "${2}" ]; then
	MIN_SIZE="${2}"
fi
if [ -n "${3}" ]; then
	MIN_RATE="${3}"
fi
if [ -n "${4}" ]; then
	MIN_HEIGHT="${4}"
fi
if [ -n "${5}" ]; then
	NAME_REGEX="${5}"
fi

# Name-based paramters
ZERO=0
if basename "${0}" | grep -q '0'; then
	ZERO=1
fi

# Sanity check
if [ ! -d "${FOLDER}" ]; then
	echo "Usage: `basename "${0}"` [folder] [min_size] [min_rate] [min_height] [name_regex]" 1>&2
	exit 1
fi

# Derived parameters
LAST_RECODE_FILE="`(cd "${FOLDER}" && pwd)`/.lastFindRecode"

# Environmental parameters
if [ -n "${NO_LAST_RECODE_FILE}" ]; then
	LAST_RECODE_FILE=""
fi

# Find large video files that match the regex filter
FILES="`find "${FOLDER}" -type f -maxdepth 1 -size "+${MIN_SIZE}" | grep -iE "${NAME_REGEX}"`"

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

	# Bail if the load is high
	if ! ~/bin/video/checkLoad.sh; then
		continue
	fi

	# We do not want to recode videos that we already encoded
	HANDBRAKE=0
	STRINGS="`head -c $(( 125 * 1024 * 1024 )) "${i}" | strings -n 100`"
	if echo "${STRINGS}" | grep -q HandBrake; then
		HANDBRAKE=1
	elif echo "${STRINGS}" | grep -E '^x264 - core (79|112|120|125|129|130|142)' | grep -Eq 'crf=2[0-5]\.[0-9]'; then
		HANDBRAKE=1
	fi
	if [ $HANDBRAKE -eq 1 ]; then
		continue
	fi

	# We only care about "big" videos
	# Movies with no known height should be left alone
	# Movies with a "0" height can be assumed to be tall enough
	HEIGHT="`~/bin/video/movInfo.pl "${i}" VIDEO_HEIGHT 2>/dev/null`"
	if [ -z "${HEIGHT}" ]; then
		HEIGHT=1
	fi
	if [ $HEIGHT -eq 0 ]; then
		HEIGHT=$MIN_HEIGHT
	fi
	if [ $HEIGHT -lt $MIN_HEIGHT ]; then
		continue
	fi

	# Skip files is low bitrates
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

# Record the last scan time
if [ -n "${LAST_RECODE_FILE}" ]; then
	touch "${LAST_RECODE_FILE}" >/dev/null 2>&1
fi
