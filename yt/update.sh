#!/bin/bash

# Parameters
MEDIA_PATH="`~/bin/video/mediaPath`"

# Check and write the run file
PID_FILE="/tmp/ytUpdate.pid"
if [ -f "${PID_FILE}" ]; then
	PID=`cat "${PID_FILE}"`
	if ps auwx | grep -v grep | grep "`basename "${0}"`" | grep -q "${PID}"; then
			exit 0
	fi
fi
echo $$ > "${PID_FILE}"

# Execute
find "${MEDIA_PATH}/YouTube" -maxdepth 1 -mindepth 1 -type d \
	-exec ~/bin/video/yt/subscribe.pl {} \;

# Cleanup
rm -f "${PID_FILE}"
