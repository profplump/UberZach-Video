#!/usr/local/bin/php
<?php

define('DEBUG', true);
set_time_limit(0);
require_once 'includes/main.php';
require_once 'includes/tvdb_update.php';

# Allow single-ID use
if ($argv[1]) {
	return tvdb_update($argv[1], true);
}

# Update all series
$all_series = allSeriesSeasons(TV_PATH, false);
foreach ($all_series as $series => $seasons) {
        $flags = readFlags($series);
	if (!$flags['tvdb-id']) {
		echo 'No TVDB ID for: ' . $series . "\n";
		continue;
	}

	echo 'Updating: ' . $series . ' (' . $flags['tvdb-id'] . ")\n";
	tvdb_update($flags['tvdb-id']);
}

?>
