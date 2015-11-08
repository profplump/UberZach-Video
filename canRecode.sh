#!/bin/bash

# Only OS X machines can recode currently
if [ "`uname`" == "Darwin" ]; then
	exit 0
fi

# Everything else cannot
exit 1