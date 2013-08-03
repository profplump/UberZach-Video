#!/bin/bash

# Config
BASE_LOCAL="`~/bin/video/mediaPath`"
BASE_REMOTE="/Volumes/Bitcasa Infinite Drive"

# Command-line arguments
SUB_DIR="${1}"
if [ -z "${SUB_DIR}" ]; then
	echo "Usage: `basename "${0}"` sub_directory" 1>&2
	exit 1
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

# Diff to find the first mis-matched file
DIFF="`diff -u "${TMP_LOCAL}" "${TMP_REMOTE}" | grep "^[\+\-]${SUB_DIR}"`"

# Filter junk
DIFF="`echo "${DIFF}" | grep -v '\/\._' | grep -v '\/\.DS_Store$'`"

# Choose the file/directory to sync
FILE="`echo "${DIFF}" | head -n 1`"
ACTION="`echo "${FILE}" | head -c 1`"
FILE="`echo "${FILE}" | cut -d "${ACTION}" -f 2-`"

# Determine the action (i.e. copy to or delete from remote)
if [ "${ACTION}" == '+' ]; then
	echo "Will not delete from remote: ${FILE}" 1>&2
	exit 2
elif [ "${ACTION}" == '-' ]; then
	PATH_LOCAL="${BASE_LOCAL}/${FILE}"
	PATH_REMOTE="${BASE_REMOTE}/${FILE}"

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

# Cleanup
rm -f "${TMP_LOCAL}"
rm -f "${TMP_REMOTE}"
exit 0
