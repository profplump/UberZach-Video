#!/bin/bash

# Parameters
MEDIA_PATH="`~/bin/video/mediaPath`"
BASE_DIR="${MEDIA_PATH}/Sync"

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

# Ensure we have a valid MEDIA_PATH
if ! ~/bin/video/isMediaMounted && [ -z "${MEDIA_PATH}" ]; then
	if [ $DEBUG -gt 0 ]; then
		echo "Media path not available" 1>&2
	fi
	exit 0
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
if [ `echo "${FILES}" | wc -l` -lt 1 ]; then
	echo -e "Invalid sync file list:\n${FILE}" 1>&2
	exit -2
fi

# Figure out what we already have
OLD_FILES="`find "${DEST_DIR}" -type f | sed "s%^${BASE_DIR}/%%"`"

# Always include special files
IFS=$'\n'
for i in `cat ~/.sync_extras`; do
	# Skip comments and empty lines
	if [[ "${i}" =~ ^# ]] || [[ "${i}" =~ ^$ ]]; then
		continue
	fi

	# Skip files not inside $DIR
	if ! [[ "${i}" =~ ^${DIR} ]]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Skipping sync_extra from alternate path: ${i}" 1>&2
		fi
		continue
	fi

	# Sync anything else that matches
	~/bin/video/sync/sync.sh "${MEDIA_PATH}/${i}"*
	OLD_FILES="`echo "${OLD_FILES}" | grep -v "^${i}"`"
done

# Encode and allow any expected files
IFS=$'\n'
for i in $FILES; do
	FILE="${MEDIA_PATH}/${i}"

	# Give up if the media path goes away
	if ! ~/bin/video/isMediaMounted; then
		exit
	fi

	# Skip if the input file does not exist
	if [ ! -r "${FILE}" ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Missing input path: ${FILE}" 1>&2
		fi
		continue
	fi

	# Recode
	if [ $DEBUG -gt 0 ]; then
		echo "Will encode: ${i}" 1>&2
	fi
	if [ $NO_SYNC -eq 0 ]; then
		~/bin/video/sync/sync.sh "${i}"
	fi

	# Drop from our delete files list
	nobase="`echo "${i}" | sed 's%\....$%%'`"
	OLD_FILES="`echo "${OLD_FILES}" | grep -v "${nobase}"`"
done

# Delete anything leftover
IFS=$'\n'
MIN_AGE="`date -v -1H +%s`"
for i in $OLD_FILES; do
	FILE="${BASE_DIR}/${i}"

	# Skip if the input file does not exist
	if [ ! -r "${FILE}" ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Missing delete path: ${i}" 1>&2
		fi
		continue
	fi

	# Skip tvshow.nfo and poster.* if other files exist in the directory
	NOEXT="`basename "${FILE}" | sed 's%\....$%%'`"
	if [ "${NOEXT}" == "tvshow" ] || [ "${NOEXT}" == "poster" ]; then
		DIRNAME="`dirname "${FILE}"`"
		if ls "${DIRNAME}" | grep -v 'tvshow\.nfo$' | grep -qv 'poster\....$'; then
			if [ $DEBUG -gt 0 ]; then
				echo "Skipping active metadata file: ${FILE}" 1>&2
			fi
			continue
		else
			if [ $DEBUG -gt 0 ]; then
				echo "Inactive metadata file: ${FILE}" 1>&2
			fi
		fi
	fi

	# Skip files under 1H old to avoid churn and provide a no-delete signal for other conditions (e.g. filename encoding)
	STAT="`stat -f '%m' "${FILE}" 2>/dev/null`"
	if [ -z "${STAT}" ]; then
		STAT=1
	fi
	if [ $STAT -ge $MIN_AGE ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Will skip due to minimum age: ${FILE}" 1>&2
		fi
		continue
	fi

	# Delete, unless set NOT to sync
	if [ $DEBUG -gt 0 ]; then
		echo "Will delete: ${BASE_DIR}/${i}" 1>&2
	fi
	if [ $NO_SYNC -eq 0 ]; then
		rm -f "${FILE}"
	fi
done
find "${DEST_DIR}" -type d -empty -delete

# Cleanup
if [ -n "${PID_FILE}" ]; then
	rm -f "${PID_FILE}"
fi
