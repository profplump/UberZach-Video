#!/usr/local/bin/php
<?

set_time_limit(0);
require_once 'includes/main.php';

global $TV_PATH;
$all_series = allSeriesSeasons($TV_PATH);
$old_series = array();
$added_seasons = array();
$multi_seasons = array();
$empty_seasons = array();

# Set this to "false" for offline testing
#$ENABLE_TVDB = false;

# Check each series for new seasons listed on TVDB but not locally
foreach ($all_series as $series => $seasons) {

	# Grab the season parameters
	$flags = readFlags($series);

	# Respect the "skip" flag
	if ($flags['skip']) {
		continue;
	}

	# Grab the TVDB season list
	$tvdb_seasons = getTVDBSeasons($flags['tvdb-id'], $flags['tvdb-lid']);

	# We only care about "new" seasons -- don't force old seasons into the local tree
	$tvdb_max = @max(array_keys($tvdb_seasons));
	$local_max = @max(array_keys($seasons));

	# Sanity checks
	if (!is_array($tvdb_seasons) || $tvdb_max < 1) {
		echo 'Unable to retrive reasonable season data from TheTVDB for ' . $series. ". Skipping...\n";
		continue;
	}
	if ($tvdb_max - $local_max > 5) {
		echo 'TheTVDB lists ' . $tvdb_max . ' season for ' . $series. ". Skipping...\n";
		continue;
	}

	# Add missing seasons
	for ($season = $local_max + 1; $season <= $tvdb_max; $season++) {
		$added_seasons[] = $series . ' - Season ' . $season;
		addSeason($series, $season);
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
		$multi_seasons[] = $series;
	}

	# Check for seasons with no episodes
	foreach ($seasons as $season => $status) {
		if ($status) {
			$episodes = findEpisodes($series, $season);
			if (count($episodes) < 1) {
				$empty_seasons[] = $series . ' - Season ' . $season;
			}
		}
	}

	# Check for "old" but still monitored series
	foreach ($seasons as $season => $status) {
		if ($status) {
			if ($flags['mtime'] < time() - $MAX_AGE) {
				$old_series[] = $series;
				break;
			}
		}
	}
}

# Display series with multiple monitored seasons
if (count($multi_seasons) > 0) {
	echo "\n";
	echo "Series with multiple monitored seasons:\n";
	foreach ($multi_seasons as $val) {
		echo "\t" . $val . "\n";
	}
}

# Display added seasons
if (count($added_seasons) > 0) {
	echo "\n";
	echo "Added seasons:\n";
	foreach ($added_seasons as $val) {
		echo "\t" . $val . "\n";
	}
}

# Display "old" series
if (count($old_series) > 0) {
	echo "\n";
	echo "Monitored series with no recent updates:\n";
	foreach ($old_series as $val) {
		echo "\t" . $val . "\n";
	}
}

# Display empty seasons
if (count($empty_seasons) > 0) {
	echo "\n";
	echo "Monitored seasons with no episodes:\n";
	foreach ($empty_seasons as $val) {
		echo "\t" . $val . "\n";
	}
}

# Display "old" seasons

?>
