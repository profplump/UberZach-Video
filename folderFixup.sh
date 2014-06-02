#!/bin/bash

# Parameters
inFolder="`~/bin/video/mediaPath`/TV"

# Debug
if [ -n "${DEBUG}" ] && [ $DEBUG -gt 0 ]; then
	echo -n "Starting `basename "${0}"`: "
	date
fi

# Command line
if [ -n "${1}" ]; then
	inFolder="${1}"
fi
if [ ! -e "${inFolder}" ]; then
	echo "Usage: `basename "${0}"` input_folder" 1>&2
	exit 1
fi

# Bail if we're already running
me="`basename "${0}"`"
if [ `ps auwx | grep -v grep | grep "${me}" | wc -l` -gt 2 ]; then
	if [ -n "${DEBUG}" ] && [ $DEBUG -gt 0 ]; then
		echo 'Already running' 1>&2
	fi
	exit 0
fi

# Bail if the load is high
if ! ~/bin/video/checkLoad.sh; then
	if [ -n "${DEBUG}" ] && [ $DEBUG -gt 0 ]; then
		echo 'Load too high' 1>&2
	fi
	exit 0
fi

# Bail if the media share isn't available
if ! ~/bin/video/isMediaMounted; then
	echo 'Media not mounted' 1>&2
	exit 1
fi

# Cache output
tmp="`mktemp -t 'folderFixup.XXXXXXXX'`"

# Re-wrap or recode as needed
find "${inFolder}" -mindepth 1 -type d -exec ~/bin/video/folderToMKV.sh {} \; 1>>"${tmp}" 2>&1

# Filter the output
cat "${tmp}" | \
	grep -Ev "^cp: .*: could not copy extended attributes to .*: Operation not permitted$" | \
	grep -v "GetFileInfo: could not get info about file (-1401)" | \
	grep -v "ERROR: Unexpected Error. (-1401)  on file: " | \
	grep -v "ERROR: Unexpected Error. (-5000)  on file: " | \
	grep -v "^ *$"

# Cleanup
rm -rf "${tmp}"

# Debug
if [ -n "${DEBUG}" ] && [ $DEBUG -gt 0 ]; then
	echo -n 'Complete: '
	date
fi
