#!/bin/bash

# Config
DRIVE_NUM=1
DR_DRIVE_NUM=$(( $DRIVE_NUM + 1 ))
OUT_DIR="${HOME}/Desktop/Docs/Downloads"
APP_PATH="/Applications/Zach/Media/MakeMKV.app"

# Globals
BIN_PATH="${APP_PATH}/Contents/MacOS/makemkvcon"
TMP="`mktemp -t discToMkv`"

# Sanity check
if [ ! -d "${OUT_DIR}" ]; then
	echo "Invalid output directory: ${OUT_DIR}"
	exit 1
fi

# Ensure a disk is inserted
if drutil -drive "${DR_DRIVE_NUM}" status | grep -q 'Type: No Media Inserted'; then
	echo "No disk available" 1>&2
	drutil -drive "${DR_DRIVE_NUM}" tray open
	exit 1
fi

# Parse the disc
"${BIN_PATH}" --noscan --robot "--messages=${TMP}" info "disc:${DRIVE_NUM}"

# Find the disk title -- long if available, short if not
CINFO="`grep '^CINFO\:' "${TMP}"`"
LONG="`echo "${CINFO}" | awk -F ',' '$1 == "CINFO:2" && $2 == "0" {print $3}' | sed 's%^"\(.*\)"$%\1%'`"
SHORT="`echo "${CINFO}" | awk -F ',' '$1 == "CINFO:32" && $2 == "0" {print $3}' | sed 's%^"\(.*\)"$%\1%'`"
NAME="${LONG}"
if [ -z "${NAME}" ]; then
	NAME="${SHORT}"
fi

# Cleanup the parse data
rm -f "${TMP}"

# Sanity check
if [ -z "${NAME}" ]; then
	echo "Unable to determine disc name" 1>&2
	exit 1
fi

# Create the output directory
if [ ! -d "${OUT_DIR}/${NAME}" ]; then
	mkdir "${OUT_DIR}/${NAME}"
fi

# Extract all tracks to MKVs
# Tracks are selected with the default profile (as set in the GUI)
# Recommended selection string: -sel:all,+sel:(favlang|nolang),-sel:(core),+sel:special,-sel:mvcvideo,=100:all,-10:favlang
# This preserves all audio and subtitles in your prefered language, all audio and subtitles with no language, and all special tracks, but excludes the core audio from DTS-HD tracks
"${BIN_PATH}" --noscan --robot mkv "disc:${DRIVE_NUM}" all "${OUT_DIR}/${NAME}"

# Bail on error
if [ $? -ne 0 ]; then
	exit $?
fi

# Eject when complete
DISK="`drutil -drive "${DR_DRIVE_NUM}" status | awk '$3 == "Name:" {print $4}'`"
if [ -n "${DISK}" ]; then
	diskutil eject "${DISK}"
fi
