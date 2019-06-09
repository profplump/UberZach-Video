#!/bin/bash

MAX_MOVE=25

PREFIX="${1}"
if [ -z "${PREFIX}" ]; then
	echo "Usage: ${0} PREFIX" 1>&2
	exit 1
fi

# Validate the prefix
NUM="`echo "${PREFIX}" | sed 's%^S0E\(20[0-9]*\)$%\1%'`"
if [ -z "${NUM}" ] || ! echo "${NUM}" | grep -Eq '^[0-9]+$'; then
	echo "Invalid prefix: ${PREFIX}" 1>&2
	exit 1
fi

# Find the NFO and MKV
YTID=""
shopt -s nullglob
for i in "${PREFIX}"*; do
	ID="`echo "${i}" | sed 's%^S0E[0-9]* - \(.*\)\.[mn][kf][vo]$%\1%'`"
	if [ -z "${ID}" ]; then
		echo "Invalid YTID for: ${i}" 1>&2
		exit 1
	fi
	if [ -z "${YTID}" ]; then
		YTID="${ID}"
	elif [ "${ID}" != "${YTID}" ]; then
		echo "Moving ${YTID}, leaving ${ID}" 1>&2
		continue
	fi

	TYPE="`echo "${i}" | sed 's%^.*\.\([mn][kf][vo]\)$%\1%'`"
	if [ -z "${TYPE}" ]; then
		echo "Invalid file extension for: ${i}" 1>&2
		exit 1
	fi

	if [ "${TYPE}" == "nfo" ]; then
		NFO="${i}"
	elif [ "${TYPE}" == "mkv" ]; then
		MKV="${i}"
	else
		echo "Unknown file type for: ${i}" 1>&2
		exit 1
	fi
done
if [ -z "${MKV}" ] || [ -z "${NFO}" ]; then
	echo "Unable to find an NFO/MKV set for: ${PREFIX}" 1>&2
	exit 1
fi

function checkNew() {
	if [ -z "${NUM_NEW}" ]; then
		COUNT=0
		for foo in "S0E${1}"*; do
			COUNT=$(( $COUNT + 1 ))
		done
		if [ $COUNT -eq 0 ]; then
			NUM_NEW=$1
		fi
	fi
}

# Find a new file name
NUM_NEW=""
i=1
while [ $i -lt $MAX_MOVE ]; do
	checkNew $(( NUM + $i ))
	checkNew $(( NUM - $i ))
	i=$(( $i + 1 ))
done
if [ -z "${NUM_NEW}" ]; then
	echo "Unable to find new number for: ${PREFIX}" 1>&2
	exit 1
fi

# Rename the files
MKV_NEW="S0E${NUM_NEW} - ${YTID}.mkv"
NFO_NEW="S0E${NUM_NEW} - ${YTID}.nfo"
sudo chattr -i "${MKV}" "${NFO}" && \
	mv -v "${MKV}" "${MKV_NEW}" && \
	mv -v "${NFO}" "${NFO_NEW}"

# Renumber the NFO
sed -i 's%<episode>[0-9]*<\/episode>%<episode>'"${NUM_NEW}"'<\/episode>%' "${NFO_NEW}"
