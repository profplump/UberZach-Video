#!/bin/bash
set -e

# Parameters
TV_DIR="`~/bin/video/mediaPath`/TV";
SERIES="${1}"
SEARCH="${2}"
DAYS_BACK="${3}"
MAX_DAYS_BACK="${4}"

# Usage
if [ -z "${SERIES}" ] || [ -z "${SEARCH}" ] || [ -z "${DAYS_BACK}" ] || \
	! echo "${DAYS_BACK}" | grep -qE '^[0-9]*$' || [ $DAYS_BACK -lt 0 ] || [ $DAYS_BACK -gt 90 ]; then
		echo "Usage: `basename "${0}" series search days_back [max_days_back]`" 1>&2
		exit 1
fi

# Allow use in recursive mode
if [ -n "${MAX_DAYS_BACK}" ]; then
	if ! echo "${MAX_DAYS_BACK}" | grep -qE '^[0-9]*$' || [ $MAX_DAYS_BACK -lt $DAYS_BACK ] || [ $MAX_DAYS_BACK -gt 90 ]; then
		echo "Usage: `basename "${0}" series search days_back [max_days_back]`" 1>&2
		exit 1
	fi
	while [ $DAYS_BACK -le $MAX_DAYS_BACK ]; do
		"${0}" "${SERIES}" "${SEARCH}" "${DAYS_BACK}"
		DAYS_BACK=$(( $DAYS_BACK + 1 ))
	done
	exit 0
fi

# Calculate some dates
YEAR="`date -v-${DAYS_BACK}d '+%Y'`"
MONTH="`date -v-${DAYS_BACK}d '+%m'`"
DAY="`date -v-${DAYS_BACK}d '+%d'`"

# Bail if we already have a matcing file
FILES="`find "${TV_DIR}/${SERIES}/Season ${YEAR}" -type f -not -name '*.nfo' -not -name '*.tbn' -name "${YEAR}-${MONTH}-${DAY} - *"`"
if [ -n "${FILES}" ]; then
	exit 0
fi

# Otherwise run a search
SEARCH="`echo "${SEARCH}" | sed "s/%Y/${YEAR}/g"`"
SEARCH="`echo "${SEARCH}" | sed "s/%m/${MONTH}/g"`"
SEARCH="`echo "${SEARCH}" | sed "s/%d/${DAY}/g"`"
~/bin/video/findTorrent.pl "${SERIES}" "${SEARCH}"
