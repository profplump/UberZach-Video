#!/bin/bash

export INI_PATH="${1}/extra_videos.ini"
export TOP_URL='http://geekandsundry.com/shows/co-optitude/'
export EP_MATCH='^https?\:\/\/geekandsundry.com\/co\-optitude[^\/]+\/$'

exec ~/bin/video/yt/critrole.pl
