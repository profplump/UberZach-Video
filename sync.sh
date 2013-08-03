#!/bin/bash

# Config
BASE_LOCAL="`~/bin/video/mediaPath`"
BASE_REMOTE="/Volumes/Bitcasa Infinite Drive"

# Command-line arguments
SUB_DIR="${1}"
declare -i NUM_FILES
NUM_FILES=1
if [ -n "${2}" ]; then
	NUM_FILES="${2}"
fi

# Usage checks
if [ -z "${SUB_DIR}" ] || [ $NUM_FILES -lt 1 ]; then
	echo "Usage: `basename "${0}"` sub_directory [num_files]" 1>&2
	exit 1
fi

# Allow usage with absolute local paths
if [ "`echo "${SUB_DIR}" | head -c 1`" == '/' ]; then
	SUB_DIR="`echo "${SUB_DIR}" | sed 's%^'"${BASE_LOCAL}"'/%%'`"
fi

# Sanity checks
if [ ! -d "${BASE_LOCAL}/${SUB_DIR}" ]; then
	echo "Invalid local directory: ${BASE_LOCAL}/${SUB_DIR}" 1>&2
	exit 1
fi
if [ ! -d "${BASE_REMOTE}" ]; then
	echo "Bitcasa drive not mounted" 1>&2
	exit 1
fi

# Ensure the subdirectory exists on the remote drive
if [ ! -d "${BASE_REMOTE}/${SUB_DIR}" ]; then
	mkdir -p "${BASE_REMOTE}/${SUB_DIR}"
fi

# Grab directory tree lists
TMP_LOCAL="`mktemp -t sync.local.XXXXXXXX`"
(cd "${BASE_LOCAL}" && find "${SUB_DIR}" | sort > "${TMP_LOCAL}")
TMP_REMOTE="`mktemp -t sync.remote.XXXXXXXX`"
(cd "${BASE_REMOTE}" && find "${SUB_DIR}" | sort > "${TMP_REMOTE}")

# Diff to find the first mis-matched file, then drop out temp files
DIFF="`diff -u "${TMP_LOCAL}" "${TMP_REMOTE}" | grep "^[\+\-]${SUB_DIR}"`"
rm -f "${TMP_LOCAL}" "${TMP_REMOTE}"

# Filter junk
DIFF="`echo "${DIFF}" | grep -v '\/\._' | grep -v '\/\.DS_Store$'`"

# Limit NUM_FILES to the number of files available
COUNT="`echo "${DIFF}" | wc -l`"
if [ $NUM_FILES -gt $COUNT ]; then
	NUM_FILES=$COUNT
fi

# Loop for NUM_FILES
for (( i=1; i<=${NUM_FILES}; i++ )); do

	# Choose the file/directory to sync
	FILE="`echo "${DIFF}" | head -n $i | tail -n 1`"
	ACTION="`echo "${FILE}" | head -c 1`"
	FILE="`echo "${FILE}" | cut -d "${ACTION}" -f 2-`"

	# Construct absolute paths
	PATH_LOCAL="${BASE_LOCAL}/${FILE}"
	PATH_REMOTE="${BASE_REMOTE}/${FILE}"

	# Determine the action (i.e. copy to or delete from remote)
	if [ "${ACTION}" == '+' ]; then
		echo "Will not delete from remote: ${FILE}" 1>&2
		exit 2
	elif [ "${ACTION}" == '-' ]; then

		# Handle files by type
		if [ -h "${PATH_LOCAL}" ]; then
			echo "Unable to create symlink: ${FILE}" 1>&2
			exit 2
		elif [ -d "${PATH_LOCAL}" ]; then
			echo "Creating directory: ${FILE}"
			mkdir "${PATH_REMOTE}"
		elif [ -f "${PATH_LOCAL}" ] && [ -r "${PATH_LOCAL}" ]; then
			echo "Copying: ${FILE}"
			cp "${BASE_LOCAL}/${FILE}" "${BASE_REMOTE}/${FILE}"
		else
			echo "Unable to copy file: ${FILE}" 1>&2
			exit 2
		fi
	else
		echo "Invalid action: ${ACTION}" 1>&2
		echo -n "\tDiff: "
		echo "${DIFF}" | head -n 1
		exit 2
	fi
done

# Cleanup
exit 0
