#!/bin/bash

export INI_PATH="${1}/extra_videos.ini"
export TOP_URL='http://geekandsundry.com/shows/larps/'
export EP_MATCH='^https?\:\/\/geekandsundry.com\/[^\/]+\/$'

exec ~/bin/video/yt/critrole.pl
