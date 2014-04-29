#!/bin/bash

if [ -z "${1}" ] || [ ! -r "${1}" ]; then
	echo "Usage: `basename "${0}"` input" 1>&2
	exit 1
fi

cat "${1}" | \
	grep 'href="/watch?v=[a-zA-Z0-9_-]*"' | \
	sed 's%^.*href="/watch?v=\([a-zA-Z0-9_-]*\)".*$%\1%' | \
	uniq | \
	tail -r | \
	nl -n ln | \
	sed 's%^\([0-9]*\)   %\1 =>%'
