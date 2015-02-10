#!/bin/bash

# Parameters
TARGET="Sync"
MEDIA_PATH="`~/bin/video/mediaPath`"
BASE_DIR="${MEDIA_PATH}/${TARGET}"

# Environmental parameters
if [ "${DEBUG}" ]; then
	DEBUG=1
else
	DEBUG=0
fi
if [ "${NO_SYNC}" ]; then
	NO_SYNC=1
else
	NO_SYNC=0
fi

# Command-line options
DIR="TV"
if echo "${1}" | grep -qi "Movie"; then
	DIR="Movies"
elif echo "${1}" | grep -qi "YouTube"; then
	DIR="YouTube"
fi

# Ensure we have a valid TMPDIR
if [ ! -d "${TMPDIR}" ]; then
	TMPDIR="`getconf DARWIN_USER_TEMP_DIR 2>/dev/null`"
	if [ ! -d "${TMPDIR}" ]; then
		TMPDIR="/var/tmp"
	fi
	if [ ! -d "${TMPDIR}" ]; then
		TMPDIR="/tmp"
	fi
fi

# Check and write the run file
if [ -z "${NO_PID}" ]; then
	PID_FILE="${TMPDIR}/syncUnwatched.pid"
	if [ -f "${PID_FILE}" ]; then
		PID=`cat "${PID_FILE}"`
		if ps auwx | grep -v grep | grep "`basename "${0}"`" | grep -q "${PID}"; then
			if [ $DEBUG -gt 0 ]; then
				echo "Already running: ${PID}" 1>&2
				exit -1
			else
				exit 0
			fi
		fi
	fi
	echo $$ > "${PID_FILE}"
fi

# Construct directories
DEST_DIR="${BASE_DIR}/${DIR}"

# Figure out what we want
FILES="`~/bin/video/sync/recentlyUnwatched.sh "${1}"`"

# Ensure the input is sane
if [ `echo "${FILES}" | wc -l` -lt 5 ]; then
	echo -e "Invalid sync file list:\n${FILE}" 1>&2
	exit -2
fi

# Figure out what we already have
OLD_FILES="`find "${DEST_DIR}" -type f | sed "s%^${BASE_DIR}/%%"`"

# Always include special files
IFS=$'\n'
for i in `cat ~/.sync_extras`; do
	~/bin/video/sync/sync.sh "${MEDIA_PATH}/${i}"*
	OLD_FILES="`echo "${OLD_FILES}" | grep -v "^${i}"`"
done

# Encode and allow any expected files
IFS=$'\n'
for i in $FILES; do
	if [ $DEBUG -gt 0 ]; then
		echo "Will encode: ${i}"
	fi
	if [ $NO_SYNC -eq 0 ]; then
		~/bin/video/sync/sync.sh "${i}"
	fi

	nobase="`echo "${i}" | sed 's%\....$%%'`"
	OLD_FILES="`echo "${OLD_FILES}" | grep -v "${nobase}"`"
done

# Delete anything leftover
IFS=$'\n'
MIN_AGE="`date -v -1H +%s`"
for i in $OLD_FILES; do
	# Skip files under 1H old to avoid churn and provide a no-delete signal for other conditions (e.g. filename encoding)
	STAT="`stat -f '%m' "${BASE_DIR}/${i}" 2>/dev/null`"
	if [ -z "${STAT}" ]; then
		STAT=1
	fi
	if [ $STAT -ge $MIN_AGE ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Will skip due to minimum age: ${BASE_DIR}/${i}"
		fi
		continue
	fi

	# Delete if set to sync
	if [ $DEBUG -gt 0 ]; then
		echo "Will delete: ${BASE_DIR}/${i}"
	fi
	if [ $NO_SYNC -eq 0 ]; then
		rm -f "${BASE_DIR}/${i}"
	fi
done
find "${DEST_DIR}" -type d -empty -delete

# Cleanup
if [ -n "${PID_FILE}" ]; then
	rm -f "${PID_FILE}"
fi
