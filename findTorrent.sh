#!/bin/bash

BASE_DIR="`~/bin/video/mediaPath`/TV"

SERIES="${1}"
SEASON="${2}"

usage() {
	echo "Usage: `basename "${0}"` series_name [season]" 1>&2
	exit 1
}

# Resolve relative paths
if echo "${SERIES}" | grep -qE "\.\.?/"; then
	SERIES="`cd "${SERIES}" && pwd`"
fi

# Split the season directory, if provided
if echo "${SERIES}" | grep -qE '\/Season [0-9]*\/?$'; then
		SEASON="`basename "${SERIES}" | sed 's%^Season %%'`"
		SERIES="`dirname "${SERIES}"`"
fi

# Construct the series directory path
if echo "${SERIES}" | grep -q "/"; then
	SERIES_DIR="${SERIES}"
else
	SERIES_DIR="${BASE_DIR}/${SERIES}"
fi

# Standardize the series name
SERIES="`basename "${SERIES_DIR}"`"

# Sanity check
if [ ! -d "${SERIES_DIR}" ]; then
	echo "No such series directory: ${SERIES_DIR}" 1>&2
	usage
fi

# Find the season directory -- if no season is provided, use the last season in the series directory
if [ -z "${SEASON}" ]; then
	SEASON="`ls "${SERIES_DIR}" | awk '$1 == "Season" && $2 ~ "[0-9]*" {print $2}' | sort -n -r | head -n 1`"
	SEASON=$(( $SEASON + 0 ))
fi
SEASON_DIR="${SERIES_DIR}/Season ${SEASON}"

# Sanity check
if [ ! -d "${SEASON_DIR}" ]; then
	echo "No such season directory: ${SEASON_DIR}" 1>&2
	usage
fi

# Special handling for search-by-date folders
if [ -r "${SERIES_DIR}/search_by_date" ]; then
	SEARCH_STR=`cat "${SERIES_DIR}/search_by_date"`
	DEBUG=1 ~/bin/video/findDate.sh "${SERIES}" "${SEARCH_STR}" 0 3 | download
	exit $?
fi

# Run the standard command, in debug mode
DEBUG=1 ~/bin/video/findTorrent.pl "${SEASON_DIR}" | download
