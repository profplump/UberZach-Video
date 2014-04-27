#!/bin/bash

# Parameters
MEDIA_PATH="`~/bin/video/mediaPath`"

# Check and write the run file
PID_FILE="${TMPDIR}/ytUpdate.pid"
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

# Execute
find "${MEDIA_PATH}/YouTube" -maxdepth 1 -mindepth 1 -type d \
	-exec ~/bin/video/yt/ytSubscribe.pl {} \;

# Cleanup
rm -f "${PID_FILE}"
