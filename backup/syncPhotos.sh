#!/bin/bash

BASE_LOCAL="/Volumes/iPhoto"
BASE_REMOTE="/Volumes/webdav.opendrive.com"

MOUNTED_PHOTOS=0
if [ ! -d /Volumes/iPhoto ]; then
	MOUNTED_PHOTOS=1
	hdiutil attach -readonly /mnt/media/Pictures/iPhoto.sparsebundle >/dev/null 2>&1
fi
if [ -d /Volumes/iPhoto ]; then
	~/bin/video/backup/sync.sh Shared.photolibrary 1000
	if [ $MOUNTED_PHOTOS -gt 0 ]; then
		hdiutil detach /Volumes/iPhoto >/dev/null 2>&1
	fi
fi

# Always exit cleanly
exit 0
