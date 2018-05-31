#!/bin/bash
set failglob
BASE="/mnt/media/TV"

NOW="`date '+%s'`"
THEN=$(( $NOW - 3600 ))

function updateCount() {
	for i in "${dir}/${num} - "*; do
		if echo "${i}" | grep -q '.nfo$'; then
			continue
		fi
		if echo "${i}" | grep -q '.srt$'; then
			continue
		fi
		count=$(( $count + 1 ))
	done
}

declare -A seen
while IFS= read -r -d '' lpath; do
	# Reset the loop
	count=0
	file="`basename "${lpath}"`"
	dir="`dirname "${lpath}"`"
	num="`echo "${file}" | sed 's%\([0-9]*\).*%\1%'`"

	# Only process things in a format we understand
	if [ -z "${num}" ]; then
		echo "Error on: ${lpath}" 1>&2
		continue
	fi

	# Skip if we're down to one
	updateCount
	if [ $count -lt 2 ]; then
		continue
	fi

	# Build a list of checked files and skip dups
	id="${dir}/${num} - "
	if [ -n "${seen["${id}"]}" ]; then
		continue
	fi
	seen["${id}"]=1

	# Skip things modified since $THEN
	if [ "`uname`" == "Darwin" ]; then
		MTIME="`stat -f '%m' "${id}"*`"
	else
		MTIME="`stat -c '%Y' "${id}"*`"
	fi
	MTIME="`echo "${MTIME}" | sort | head -n 1`"
	if [ $MTIME -gt $THEN ]; then
		echo "Skipping recent file: ${lpath}" 1>&2
		continue
	fi

	# Use mkvRename (which protects against small files internally)
	sudo chattr -i "${id}"*
	echo mkvRename "${lpath}"

	# Skip if we're down to one
	updateCount
	if [ $count -lt 2 ]; then
		continue
	fi

	# Human intervention
	sudo chattr -i "${id}"*
	touch "${id}"*
	echo "Multiple matches for: ${id}" 1>&2
	short="`echo "${id}" | sed "s%^${BASE}/%%"`"
	(cd "${BASE}" && ls -lhtQ "${short}"*)
done< <(find "${BASE}" -type f -path '*Season*' -name '[0-9]*.*' -print0)
