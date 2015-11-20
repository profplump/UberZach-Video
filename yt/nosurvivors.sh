#!/bin/bash

export INI_PATH="${1}/extra_videos.ini"
export TOP_URL='http://geekandsundry.com/tag/no-survivors/'
export EP_MATCH='^https?\:\/\/geekandsundry.com\/[^\/]+\/$'

exec ~/bin/video/yt/critrole.pl
