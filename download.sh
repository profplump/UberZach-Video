#!/bin/bash

# Config
source ~/.download.config
TIMEOUT=10
AGENT="Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.2.8) Gecko/20100722 Firefox/3.6.8"

# Grab the input URLs
URLS="`cat -`"

# Bail if there's nothing to process
if [ -z "${URLS}" ]; then
	exit 0
fi

# Choose an inter-file delay
DELAY="${2}"
if [ -z "${DELAY}" ]; then
	DELAY=10
fi

# Find the destination directory
DEST="${1}"
if [ -z "${DEST}" ]; then
	DEST="${HOME}/Desktop"
	if [ -e "${DEST}" ]; then DEST="${HOME}"; fi
fi

# Use Transmission if the URL is a magenet link
if [ -n "${TRANS_URL}" ] && echo "${URLS}" | head -n 1 | grep -Eqi '^magnet:'; then
	SESSION_ID=$(curl --silent --max-time "${TIMEOUT}" "${TRANS_URL}" | sed 's/.*<code>//g;s/<\/code>.*//g')
	if [ -n "${SESSION_ID}" ]; then
		IFS=$'\n'
		SLEEP=0
		for i in ${URLS}; do
			if [ $SLEEP -gt 0 ]; then sleep $SLEEP; fi
			SLEEP="${DELAY}"
			RESULT="`curl --silent --max-time "${TIMEOUT}" \
				--header "${SESSION_ID}" "${TRANS_URL}" \
				-d '{"method":"torrent-add", "arguments":{"paused": "false", "filename": "'${i}'"}}'`"
			if ! echo "${RESULT}" | grep -q '"result":"success"'; then
				exit 1
			fi
		done
		exit 0
	else
		echo "Transmission not available for magnet link, falling back..." 1>&2
	fi

# Use NZBGet if the URL is an NZB file
elif [ -n "${NZB_URL}" ] && echo "${URLS}" | head -n 1 | grep -Eqi '\/(getnzb\/|api\?t\=get\&id\=)'; then
	if curl -k --silent --max-time "${TIMEOUT}" "${NZB_URL}" | grep -q 'version'; then
		IFS=$'\n'
		SLEEP=0
		for i in ${URLS}; do
			if [ $SLEEP -gt 0 ]; then sleep $SLEEP; fi
			SLEEP="${DELAY}"
			URL="`echo "${i}" | cut -d '#' -f 1`"
			NAME="`echo "${i}" | cut -d '#' -f 2-`"
			RESULT="`curl -k --silent --max-time "${TIMEOUT}" "${NZB_URL}" \
				-d '{"method":"append","params":["'"${NAME}"'.nzb","'"${URL}"'","",0,false,false,"",0,"force"]}'`"
			if ! echo "${RESULT}" | grep 'result' | grep -q '[1-9]'; then
				exit 1
			fi
		done
		exit 0
	else
		echo "NZBGet not available for NZB link, falling back..." 1>&2
	fi
fi

# Use "open", if available, for non-HTTP URLs
if ! echo "${URLS}" | head -n 1 | grep -Eqi '^http'; then
	if open >/dev/null 2>&1; then
		echo "${URLS}" | xargs -n 1 open
		exit "${?}"
	else
		echo "Non-HTTP URL, open() not available. Aborting..." 1>&2
		exit 1
	fi
fi

# Failure
echo "Cannot fetch: ${URLS}" 1>&2
exit 1
