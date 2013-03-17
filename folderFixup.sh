#!/bin/bash

# Parameters
inFolder="/mnt/media/TV"

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
	exit 0
fi

# Bail if the load average is high
LOAD="`uptime | awk -F ': ' '{print $2}' | cut -d '.' -f 1`"
CPU_COUNT="`sysctl -n hw.ncpu`"
if [ $LOAD -gt $(( 2 * $CPU_COUNT )) ]; then
	exit 0
fi

# Bail if WoW is running
if ps auwx | grep -v grep | grep -q "World of Warcraft/World of Warcraft-64.app/Contents/MacOS/World of Warcraft-64"; then
	exit 0
fi

# Bail if the media share isn't available
if ! ~/bin/video/isMediaMounted; then
	exit 0
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
	grep -v "ERROR: Unexpected Error. (-5000)  on file: "
