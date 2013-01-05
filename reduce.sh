#!/bin/bash

cd /mnt/media/Movies
for i in *.mkv; do
	INFO="`~/bin/video/HandbrakeCLI --title 0 --input "${i}" 2>&1`"
	AUDIO_STREAMS="`echo "${INFO}" | grep 'Stream #0\.[0-9]*\(.*\): Audio: '`"
	DTS_STREAMS="`echo "${AUDIO_STREAMS}" | grep 'Audio: dca (DTS'`"
	NUM_DTS_STREAMS="`echo "${DTS_STREAMS}" | wc -l`"

	if [ ${NUM_DTS_STREAMS} -eq 2 ]; then
		CORE_STREAM=-1
		HD_STREAM=-1

		IFS=$'\n'
		for j in ${DTS_STREAMS}; do
			STREAM_ID="`echo "${j}" | sed 's%^.*Stream #0\.\([0-9]*\)(.*$%\1%'`"
			if echo "${j}" | grep -q 'DTS-HD'; then
				if [ $HD_STREAM -ge 0 ]; then
					echo "Cannot reduce: ${i}: Multiple HD streams detected"
					break
				fi
				HD_STREAM=$STREAM_ID
			else
				if [ $CORE_STREAM -ge 0 ]; then
					echo "Cannot reduce: ${i}: Multiple core streams detected"
					break
				fi
				CORE_STREAM=$STREAM_ID
			fi
		done

		if [ $CORE_STREAM -lt 0 ] || [ $HD_STREAM -lt 0 ]; then
			echo "Cannot reduce: ${i}: No HD/Core pair detected"
			continue
		fi

		KEEP_STREAMS=""
		for j in ${AUDIO_STREAMS}; do
			STREAM_ID="`echo "${j}" | sed 's%^.*Stream #0\.\([0-9]*\)(.*$%\1%'`"
			if [ ${STREAM_ID} -ne ${CORE_STREAM} ]; then
				if [ -n "${KEEP_STREAMS}" ]; then
					KEEP_STREAMS="${KEEP_STREAMS},"
				fi
				KEEP_STREAMS="${KEEP_STREAMS}${STREAM_ID}"
			fi
		done

		echo "Reducing: ${i}"
		echo -e "\n\n\n${i}\n\n" >> ~/.Trash/mkvmerge.out
		echo mkvmerge --output "${i}.new" --audio-tracks "${KEEP_STREAMS}" "${i}" >> ~/.Trash/mkvmerge.out 2>&1
		mkvmerge --output "${i}.new" --audio-tracks "${KEEP_STREAMS}" "${i}" >> ~/.Trash/mkvmerge.out 2>&1
	elif [ ${NUM_DTS_STREAMS} -gt 2 ]; then
		echo "Cannot reduce: ${i}: Too many DTS streams"
	else
		echo "No DTS streams in: ${i}"
	fi
done
