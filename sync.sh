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

# Allow usage with absolute local paths
if [ "`echo "${SUB_DIR}" | head -c 1`" == '/' ]; then
	BASE_LOCAL="`dirname "${SUB_DIR}"`"
	SUB_DIR="`basename "${SUB_DIR}"`"
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
WC="${BASE_REMOTE}/.write_check"
touch "${WC}" >/dev/null 2>&1
if [ ! -e "${WC}" ]; then
	echo "Remote drive not writable" 1>&2
	exit 1
fi
rm -f "${WC}" >/dev/null 2>&1
if [ -e "${WC}" ]; then
	echo "Remote drive not writable" 1>&2
	exit 1
fi

# Create the named subdirectory if it does not exist on the remote drive
if [ ! -d "${BASE_REMOTE}/${SUB_DIR}" ]; then
	mkdir -p "${BASE_REMOTE}/${SUB_DIR}"
fi

# Grab and sort the local file list
# Limit files by mtime, but include all directories
TMP_LOCAL="`mktemp -t sync.local.XXXXXXXX`"
TMP_LOCAL2="`mktemp -t sync.local2.XXXXXXXX`"
(cd "${BASE_LOCAL}" && find "${SUB_DIR}" -type f -mtime "+${DELAY_DAYS}d" > "${TMP_LOCAL2}")
(cd "${BASE_LOCAL}" && find "${SUB_DIR}" -type d >> "${TMP_LOCAL2}")
cat "${TMP_LOCAL2}" | sort > "${TMP_LOCAL}"

# Grab and sort the remote file list
TMP_REMOTE="`mktemp -t sync.remote.XXXXXXXX`"
(cd "${BASE_REMOTE}" && find "${SUB_DIR}" | sort > "${TMP_REMOTE}")

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
		if [ -d "${PATH_REMOTE}" ]; then
			echo "Removing directory: ${FILE}"
			rmdir "${PATH_REMOTE}"
		elif [ -f "${PATH_REMOTE}" ]; then
			echo "Deleting file: ${FILE}"
			rm "${PATH_REMOTE}"
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
		exit 2
	fi
done

# Cleanup
rm -f "${TMP_DIFF}"
exit 0
