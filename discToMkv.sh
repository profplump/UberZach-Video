#!/bin/bash

# Config
if [ -z "${DRIVE_NAME}" ]; then
	DRIVE_NAME="BD-RE  WH16NS40"
fi
if [ -z "${OUT_DIR}" ]; then
	OUT_DIR="/Users/Shared/EncodeQueue/in"
fi
APP_PATH="/Applications/Zach/Media/MakeMKV.app"

# Tracks are extracted with the default profile (as set in the GUI)
# Recommended selection string:
#	-sel:all,+sel:(favlang|nolang),-sel:(core),+sel:special,-sel:mvcvideo,=100:all,-10:favlang
# This preserves all audio and subtitles in your prefered language, all audio and subtitles with no language, and all special tracks, but excludes the core audio from DTS-HD tracks
# Or if you capture films with no soundtrack in your favorite language:
#	-sel:all,+sel:(audio),-sel:(havemulti),+sel:(favlang|nolang),-sel:(core),+sel:special,-sel:mvcvideo,=100:all,-10:favlang

# Globals
BIN_PATH="${APP_PATH}/Contents/MacOS/makemkvcon"
TMP="`mktemp -t discToMkv`"

# Sanity check
if [ ! -d "${OUT_DIR}" ]; then
	echo "Invalid output directory: ${OUT_DIR}"
	exit 1
fi

# Find the DR drive number based on the device name
i=1
declare -i DRIVE_NUM_DR
while [ $i -lt 100 ]; do
	STATUS="`drutil -drive $i status 2>&1`"
	if echo "${STATUS}" | grep -q "${DRIVE_NAME}"; then
		DRIVE_NUM_DR=$i
		break
	elif echo "${STATUS}" | grep -q 'Could not find a valid device.'; then
		break
	fi
	i=$(( $i + 1 ))
done

# Ensure a disk is inserted
if drutil -drive "${DRIVE_NUM_DR}" status | grep -q 'Type: No Media Inserted'; then
	echo "No disk available" 1>&2
	drutil -drive "${DRIVE_NUM_DR}" tray open
	exit 1
fi

# Find the MKV drive number and OS device path based on the device name
declare -i DRIVE_NUM_MKV
DEV_PATH=""
DRIVE="`"${BIN_PATH}" --robot info dev | grep '^DRV:' | cut -d ':' -f 2- | grep "${DRIVE_NAME}"`"
DRIVE_NUM_MKV="`echo "${DRIVE}" | awk -F ',' '{print $1}'`"
DEV_PATH="`echo "${DRIVE}" | awk -F ',' '{print $7}' | cut -d '"' -f 2`"

# Sanity check
if [ -z "${DRIVE_NUM_MKV}" ] || [ $DRIVE_NUM_DR -lt 1 ] || [ -z "${DEV_PATH}" ] || [ ! -c "${DEV_PATH}" ]; then
	echo "Unable to find drive: ${DRIVE_NAME}" 1>&2
	exit 1
fi

# Parse the disc
"${BIN_PATH}" --noscan --robot "--messages=${TMP}" info "disc:${DRIVE_NUM_MKV}"

# Find the disk title -- long if available, short if not
CINFO="`grep '^CINFO\:' "${TMP}"`"
LONG="`echo "${CINFO}" | awk -F ',' '$1 == "CINFO:2" && $2 == "0" {print $3}' | sed 's%^"\(.*\)"$%\1%'`"
SHORT="`echo "${CINFO}" | awk -F ',' '$1 == "CINFO:32" && $2 == "0" {print $3}' | sed 's%^"\(.*\)"$%\1%'`"
NAME="${LONG}"
if [ -z "${NAME}" ]; then
	NAME="${SHORT}"
fi

# Find the main feature, if available
# Fall back to "all" if it's not
MAIN="all"
TINFO="`grep '^TINFO\:' "${TMP}" | grep ',"FPL_MainFeature"$'`"
if [ -n "${TINFO}" ]; then
	TRACK="`echo "${TINFO}" | cut -d ':' -f 2 | cut -d ',' -f 1 | sed 's%[^0-9]%%g'`"
	if [ -n "${TRACK}" ]; then
		MAIN="${TRACK}"
	fi
fi

# Cleanup the parse data
rm -f "${TMP}"

# Sanity check
if [ -z "${NAME}" ]; then
	echo "Unable to determine disc name" 1>&2
	exit 1
fi

# Ensure the name is filesystem-safe
NAME="`echo "${NAME}" | sed 's%[^a-zA-Z0-9_\-\ ,;\.!@#$\%\^&\*()=\+]%_%'`"

# Create the output directory
if [ ! -d "${OUT_DIR}/${NAME}" ]; then
	mkdir "${OUT_DIR}/${NAME}"
fi

# Execute
"${BIN_PATH}" --noscan --robot mkv "disc:${DRIVE_NUM_MKV}" "${MAIN}" "${OUT_DIR}/${NAME}"

# Bail on error
if [ $? -ne 0 ]; then
	exit $?
fi

# Eject when complete
diskutil eject "${DEV_PATH}"
