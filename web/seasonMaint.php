#!/usr/local/bin/php
<?

set_time_limit(0);
require_once 'includes/main.php';

global $TV_PATH;
$all_series = allSeriesSeasons($TV_PATH);

# Check each series for new seasons listed on TVDB but not locally
foreach ($all_series as $series => $seasons) {

	# Long wait between series, to avoid TVDB bans
	sleep(rand(20, 40));

	# Grab the season parameters
	$flags = readFlags($series);

	# Respect the "skip" flag
	if ($flags['skip']) {
		next;
	}

	# Grab the TVDB season list
	$tvdb_seasons = getTVDBSeasons($flags['tvdb-id'], $flags['tvdb-lid']);

	# We only care about "new" seasons -- don't force old seasons into the local tree
	$tvdb_max = @max(array_keys($tvdb_seasons));
	$local_max = @max(array_keys($seasons));

	# If we detect one or more missing seasons
	if ($tvdb_max > $local_max) {

		# Sanity check
		if ($tvdb_max - $local_max > 5) {
			echo 'TheTVDB lists ' . $tvdb_max . ' season for ' . $series. ". Skipping...\n";
			next;
		}

		# Add the seasons
		echo $series . "\n";
		for ($season = $local_max + 1; $season <= $tvdb_max; $season++) {
			echo "\tAdding season: " . $season . "\n";
			#addSeason($series, $season);
		}
	}

	# Check for multiple monitored seasons in a series
	$seasons = findSeasons($series);
	$monitored_count = 0;
	foreach ($seasons as $season => $status) {
		if ($status) {
			$monitored_count++;
		}
	}
	if ($monitored_count > 1) {
		echo 'Multiple seasons monitored for: ' . $series . "\n";
	}
}

?>
