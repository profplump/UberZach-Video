#!/bin/bash

EXCLUDES_FILE="${HOME}/.findTorrent.exclude" DEBUG=1 ~/bin/video/findTorrent.pl "${1}" | download
