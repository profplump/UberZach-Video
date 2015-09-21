#!/bin/bash

# Parameters
TARGET="Sync"
BASE_DIR="`~/bin/video/mediaPath`"

# Environmental parameters
if [ "${DEBUG}" ]; then
        DEBUG=1
else
	DEBUG=0
fi

# Command-line parameters
SUB_DIR="${1}"

# Deal with SMB mappings
# I need some way to detect when this is necessary -- maybe try both paths?
#SUB_DIR="`echo "${SUB_DIR}" | sed 's%\?%%g'`"

# Allow absolute paths, or those relative to the media path
if [ "`echo "${SUB_DIR}" | head -c 1`" == '/' ]; then
	SUB_DIR="`echo "${SUB_DIR}" | sed "s%^${BASE_DIR}/%%"`"
fi

# Allow single-file use
if [ -f "${BASE_DIR}/${SUB_DIR}" ]; then
	FILE="`basename "${SUB_DIR}"`"
	SUB_DIR="`dirname "${SUB_DIR}"`"
fi

# Construct the final paths
IN_DIR="${BASE_DIR}/${SUB_DIR}"
OUT_DIR="${BASE_DIR}/${TARGET}/${SUB_DIR}"

# Sanity check
if [ ! -d "${IN_DIR}" ]; then
	echo "Invalid input directory: ${IN_DIR}" 1>&2
	exit 1
fi

# Remember where we came from
START_DIR="`pwd`"

# Go home
cd "${IN_DIR}"

# Ensure the output directory exists
if [ ! -d "${OUT_DIR}" ]; then
	mkdir -p "${OUT_DIR}"
fi

# Export options for the encode script
export OUT_DIR
export MOBILE=1

# Handle single-file, whole-folder, or recursive use
if [ -n "${FILE}" ]; then
	FILES="${FILE}"
else
	FILES="`ls [0-9]*\ -\ *.* 2>/dev/null`"
fi

# Allow recursive use for seasons
for season in Season\ [0-9]*; do
	if [ ! -d "${season}" ]; then
		continue
	fi

	# Recurse for the season directory
	CMD="${0}"
	if [ "`echo "${CMD}" | head -c 1`" != '/' ]; then
		CMD="${START_DIR}/${0}"
	fi
	"${CMD}" "${IN_DIR}/${season}"

	# Disable the non-recursive case processing
	FILES=""
done

# Encode any missing files
IFS=$'\n'
for infile in $FILES; do
	# Skip non-files
	if [ ! -f "${infile}" ]; then
		continue
	fi

	# Don't get hung up on file extensions
	nobase="`echo "${infile}" | sed 's%\....$%%'`"

	# Copy NFO and other metadata, if present
	OLD_IFS="${IFS}"
	IFS=" "
	for meta in "${nobase}.nfo" tvshow.nfo poster.jpg poster.png; do
		if [ -e "${IN_DIR}/${meta}" ]; then
			if [ ! -e "${OUT_DIR}/${meta}" ]; then
				if [ $DEBUG -gt 0 ]; then
					echo "Copying: ${IN_DIR}/${meta}" 1>&2
				fi
				cp "${IN_DIR}/${meta}" "${OUT_DIR}/"
			fi
		fi
	done
	IFS="${OLD_IFS}"

	# Skip video files that exist
	if ls "${OUT_DIR}/${nobase}".* >/dev/null 2>&1; then
		if [ $DEBUG -gt 0 ]; then
			echo "Exists: ${SUB_DIR}/${infile}" 1>&2
		fi
		continue
	fi

	# Encode things that do not
	ERR="`~/bin/video/encode.pl "${IN_DIR}/${infile}" 2>&1`"

	# If the singular output error is "already exists" assume the error is related to filename encoding
	# Suppress the error and touch the output file to prevent it from being deleted
	if [ -n "${ERR}" ]; then
		if [ `echo "${ERR}" | wc -l` -eq 1 ] && \
			echo "${ERR}" | grep -q 'encode.pl: Output file exists: '; then
				OUTFILE="`echo "${ERR}" | \
					sed 's%encode.pl: Output file exists: %%' | \
					sed 's%. Skipping...%%'`"
				touch "${OUTFILE}"
		else
			echo "${ERR}" 1>&2
		fi
	fi
done
