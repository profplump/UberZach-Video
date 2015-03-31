#!/bin/bash

# Static config
IFS=''
MAX_RESULTS=200
CURL_OPTS=(--silent --connect-timeout 5 --max-time 30)

# Functional environmental parameters
if [ -z "${NUM_SERIES}" ]; then
	NUM_SERIES=25
fi
if [ -z "${NUM_EPISODES}" ]; then
	NUM_EPISODES=4
fi

# Construct URL components from the environment
if [ -z "${PMS_URL}" ]; then
	if [ -z "${PMS_HOST}" ]; then
		PMS_HOST="localhost"
	fi
	if [ -z "${PMS_PORT}" ]; then
		PMS_PORT=32400
	fi
	PMS_URL="http://${PMS_HOST}:${PMS_PORT}"
fi
if [ -z "${PMS_TOKEN}" ]; then
	echo "No PMS_TOKEN provided" 1>&2
fi
CURL_OPTS+=(-H "X-Plex-Token: ${PMS_TOKEN}")

# Select a configuration mode
URL1="${PMS_URL}/library/sections/2/onDeck/"
URL2_POST="children/allLeaves?unwatched=1"
if echo "${1}" | grep -iq Movie; then
	URL1="${PMS_URL}/library/sections/1/recentlyAdded/"
	URL2_POST=""
elif echo "${1}" | grep -iq YouTube; then
	URL1="${PMS_URL}/library/sections/16/onDeck/"
	NUM_EPISODES=$(( $NUM_EPISODES * 3 ))
	NUM_SERIES=$(( $NUM_SERIES * 2 ))
fi

# Find recent items
ITEMS="`curl ${CURL_OPTS[@]} "${URL1}" | \
	grep '<Video ' | \
	head -n "${MAX_RESULTS}" | \
	sed 's%^.* ratingKey="\([0-9]*\)".*$%\1%'`"

# Resolve the series item
SERIES=""
IFS=$'\n'
for i in $ITEMS; do
	ITEM="`curl ${CURL_OPTS[@]} "${PMS_URL}/library/metadata/${i}/" | \
		grep '<Video ' | \
		head -n "${MAX_RESULTS}"`"
	if echo "${ITEM}" | grep -q 'type="episode"'; then
		KEY="`echo "${ITEM}" | \
			sed 's%^.* parentRatingKey="\([0-9]*\)".*$%\1%'`"
	elif  echo "${ITEM}" | grep -q 'type="movie"'; then
		KEY="`echo "${ITEM}" | \
			grep -v 'lastViewedAt="' | \
			sed 's%^.* ratingKey="\([0-9]*\)".*$%\1%'`"
	else
		echo "Unknown type: ${ITEM}" 1>&2
		exit -1
	fi

	if [ -n "${KEY}" ]; then
		SERIES="${SERIES}${KEY}"$'\n'
	fi
done

SERIES_COUNT=0
IFS=$'\n'
for i in $SERIES; do
	SERIES_COUNT=$(( $SERIES_COUNT + 1 ))
	FILES="`curl ${CURL_OPTS[@]} "${PMS_URL}/library/metadata/${i}/${URL2_POST}" 2>/dev/null | \
		grep '<Part ' | \
		head -n "${MAX_RESULTS}" | \
		sed 's%^.*file="\([^\"]*\)".*$%\1%' | \
		sed "s%^.*/media/%%"`"

	SEASON_COUNTS=()
	IFS=$'\n'
	for j in $FILES; do
		# Find the season number and increment the count
		# I know the metadata has the season number in it, but this is less work
		# Account no-season items (i.e. movies) separately
		SEASON="`echo "${j}" | sed 's%^.*/Season \([0-9]*\)/.*$%\1%'`"
		if ! echo "${SEASON}" | grep -q '^[0-9]*$'; then
			SEASON="`echo "${j}" | sed 's%^.*/S\([0-9]*\)E[0-9].*$%\1%'`"
		fi
		if ! echo "${SEASON}" | grep -q '^[0-9]*$'; then
			SEASON=-1
		else
			SEASON_COUNTS[$SEASON]=$(( ${SEASON_COUNTS[$SEASON]} + 1 ))
		fi

		# Limit the number of series (or movies)
		if [ $SERIES_COUNT -gt $NUM_SERIES ]; then
			continue
		# Only output NUM_EPISODES files per season
		elif [ $SEASON -ge 0 ] && [ ${SEASON_COUNTS[$SEASON]} -gt $NUM_EPISODES ]; then
			continue
		fi

		# Print the name, decoding both hex encoding and XML entities, and fixing SMB mapping
		echo "${j}" | \
			sed 's/%C3%A9/é/' | \
			perl -pe 's/%([0-9a-f]{2})/sprintf("%s", pack("H2",$1))/eig' | \
			perl -e 'use XML::Entities; while (<>) { print XML::Entities::decode('all', $_); }'
	done
done
