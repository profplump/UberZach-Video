#!/bin/bash

if [ -z "${BASE_REMOTE}" ]; then
	BASE_REMOTE="/mnt/remote/opendrive"
	if [ ! -d `dirname "${BASE_REMOTE}"` ]; then
		BASE_REMOTE="/Volumes/OpenDrive"
	fi
fi
echo "${BASE_REMOTE}"
