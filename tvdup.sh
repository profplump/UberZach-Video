#!/bin/bash
set failglob

cd /mnt/media/TV
declare -A seen
while IFS= read -r -d '' lpath; do
	count=0
	file="`basename "${lpath}"`"
	dir="`dirname "${lpath}"`"
	num="`echo "${file}" | sed 's%\([0-9]*\).*%\1%'`"
	if [ -z "${num}" ]; then
		echo "Error on: ${lpath}" 1>&2
		continue
	fi
	for i in "${dir}/${num} - "*; do
		if echo "${i}" | grep -q '.nfo$'; then
			continue
		fi
		if echo "${i}" | grep -q '.srt$'; then
			continue
		fi
		count=$(( $count + 1 ))
	done
	if [ $count -ne 1 ]; then
		id="${dir}/${num} - "
		if [ -n "${seen["${id}"]}" ]; then
			continue
		fi
		seen["${id}"]=1
		echo "Multiple matches for: ${id}" 1>&2
		ls -lhtQ "${id}"*
		sudo chattr -i "${id}"*
		touch "${id}"*
	fi
done< <(find . -type f -path '*Season*' -name '[0-9]*.*' -print0)
