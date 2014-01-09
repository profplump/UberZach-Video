#!/bin/bash

# Bail if the load average is high
LOAD="`uptime | awk -F ': ' '{print $2}' | cut -d '.' -f 1`"
CPU_COUNT="`sysctl -n hw.ncpu`"
if [ $LOAD -gt $(( 2 * $CPU_COUNT )) ]; then
	exit 1
fi

# Bail if WoW is running
if ps auwx | grep -v grep | grep -q "World of Warcraft-64"; then
	exit 1
fi

# Otherwise exit cleanly
exit 0
