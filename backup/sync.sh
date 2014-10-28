#!/bin/bash

# Config
TIMEOUT=20
if [ -z "${VIDEO_DIR}" ]; then
	VIDEO_DIR="${HOME}/bin/video"
fi
if [ -z "${BASE_LOCAL}" ]; then
	BASE_LOCAL="`${VIDEO_DIR}/mediaPath`"
fi
if [ -z "${BASE_REMOTE}" ]; then
	BASE_REMOTE="`"${VIDEO_DIR}/backup/remoteDir.sh"`"
fi

# Command-line arguments
SUB_DIR="${1}"
declare -i NUM_FILES
NUM_FILES=1
if [ -n "${2}" ]; then
	NUM_FILES="${2}"
fi
declare -i DELAY_DAYS
DELAY_DAYS=30
if [ -n "${3}" ]; then
	DELAY_DAYS="${3}"
fi

# Usage checks
if [ -z "${SUB_DIR}" ] || [ $NUM_FILES -lt 1 ] || [ $DELAY_DAYS -lt 1 ]; then
	echo "Usage: `basename "${0}"` sub_directory [num_files] [delay_days]" 1>&2
	exit 1
fi

# Bail if the load is high
if ! "${VIDEO_DIR}/checkLoad.sh"; then
	exit 0
fi

# Allow usage with absolute local paths
if [ "`echo "${SUB_DIR}" | head -c 1`" == '/' ]; then
	SUB_DIR="`echo "${SUB_DIR}" | sed "s%${BASE_LOCAL}/%%"`"
fi

# Sanity checks
if [ ! -d "${BASE_LOCAL}/${SUB_DIR}" ]; then
	echo "Invalid local directory: ${BASE_LOCAL}/${SUB_DIR}" 1>&2
	exit 1
fi
if [ ! -d "${BASE_REMOTE}" ]; then
	echo "Remote drive not mounted" 1>&2
	exit 1
fi

# Ensure we can actually write to the remote drive
if ! "${VIDEO_DIR}/backup/checkMount.sh"; then
	exit 1
fi

# Create the named subdirectory if it does not exist on the remote drive
if [ ! -d "${BASE_REMOTE}/${SUB_DIR}" ]; then
	timeout "${TIMEOUT}" mkdir -p "${BASE_REMOTE}/${SUB_DIR}" >/dev/null 2>&1
	"${VIDEO_DIR}/backup/checkMount.sh" "${SUB_DIR}" > /dev/null 2>&1 &
	echo "Remote drive not in-sync" 1>&2
	exit 1
fi

# Grab and sort the local file list
# Limit files by mtime, but include all directories
TMP_LOCAL="`mktemp -t sync.local.XXXXXXXX`"
TMP_LOCAL2="`mktemp -t sync.local2.XXXXXXXX`"
(cd "${BASE_LOCAL}" && find "${SUB_DIR}" -type f -mtime "+${DELAY_DAYS}" > "${TMP_LOCAL2}")
(cd "${BASE_LOCAL}" && find "${SUB_DIR}" -type d >> "${TMP_LOCAL2}")
cat "${TMP_LOCAL2}" | sort > "${TMP_LOCAL}"

# Grab and sort the remote file list
TMP_REMOTE="`mktemp -t sync.remote.XXXXXXXX`"
timeout $(( $TIMEOUT * 10 )) bash -c "
	cd \"${BASE_REMOTE}\" && \
	find \"${SUB_DIR}\" | \
	sort > \"${TMP_REMOTE}\" \
" 2>/dev/null
if [ ! -s "${TMP_REMOTE}" ]; then
	"${VIDEO_DIR}/backup/checkMount.sh" "${SUB_DIR}" > /dev/null 2>&1 &
	echo "Remote drive not readable" 1>&2
	exit 1
fi

# Diff to find the first mis-matched file, then drop out temp files
TMP_DIFF="`mktemp -t sync.diff.XXXXXXXX`"
TMP_DIFF2="`mktemp -t sync.diff2.XXXXXXXX`"
diff -u "${TMP_LOCAL}" "${TMP_REMOTE}" | grep "^[\+\-]${SUB_DIR}" > "${TMP_DIFF2}"
rm -f "${TMP_LOCAL}" "${TMP_LOCAL2}" "${TMP_REMOTE}"

# Filter junk
grep -v '\/\._' "${TMP_DIFF2}" | grep -v '\/\.DS_Store$' | grep -v '\/\.git\/' > "${TMP_DIFF}"
rm -f "${TMP_DIFF2}"

# Limit NUM_FILES to the number of files available
COUNT="`cat "${TMP_DIFF}" | wc -l`"
if [ $NUM_FILES -gt $COUNT ]; then
	NUM_FILES=$COUNT
fi

# Loop for NUM_FILES
for (( i=1; i<=${NUM_FILES}; i++ )); do

	# Choose the file/directory to sync
	FILE="`head -n $i "${TMP_DIFF}" | tail -n 1`"
	ACTION="`echo "${FILE}" | head -c 1`"
	FILE="`echo "${FILE}" | cut -d "${ACTION}" -f 2-`"

	# Construct absolute paths
	PATH_LOCAL="${BASE_LOCAL}/${FILE}"
	PATH_REMOTE="${BASE_REMOTE}/${FILE}"

	# Determine the action (i.e. copy to or delete from remote)
	if [ "${ACTION}" == '+' ]; then
		if [ -n "${NO_DELETE}" ]; then
			# Do nothing
			true
		elif [ -d "${PATH_REMOTE}" ]; then
			echo "Removing directory: ${FILE}"
			timeout "${TIMEOUT}" rmdir "${PATH_REMOTE}" >/dev/null 2>&1
		elif [ -f "${PATH_REMOTE}" ]; then
			echo "Deleting file: ${FILE}"
			timeout "${TIMEOUT}" rm "${PATH_REMOTE}" >/dev/null 2>&1
		else
			echo "Unable to delete file: ${FILE}" 1>&2
			exit 2
		fi
	elif [ "${ACTION}" == '-' ]; then

		# Handle files by type
		if [ -h "${PATH_LOCAL}" ]; then
			echo "Unable to create symlink: ${FILE}" 1>&2
			exit 2
		elif [ -d "${PATH_LOCAL}" ]; then
			echo "Creating directory: ${FILE}"
			timeout "${TIMEOUT}" mkdir "${PATH_REMOTE}" >/dev/null 2>&1
		elif [ -f "${PATH_LOCAL}" ] && [ -r "${PATH_LOCAL}" ]; then
			echo "Copying: ${FILE}"
			if ! cp "${BASE_LOCAL}/${FILE}" "${BASE_REMOTE}/${FILE}"; then
				echo "Copy failed" 1>&2
				timeout "${TIMEOUT}" rm -f "${BASE_REMOTE}/${FILE}" >/dev/null 2>&1
				exit 2
			fi
		else
			echo "Unable to copy file: ${FILE}" 1>&2
			exit 2
		fi
	else
		echo "Invalid action: ${ACTION}" 1>&2
		exit 2
	fi
done

# Cleanup
rm -f "${TMP_DIFF}"
exit 0
