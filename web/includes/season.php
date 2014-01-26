<?

require 'config.php';

function seasonExists($series, $season) {
        return is_dir(seasonPath($series, $season));
}

function seasonPath($series, $season) {
	return seriesPath($series) . '/Season ' . intval($season);
}

# True if the provided season folder is being monitored
function isMonitored($series, $season) {

	# Season 0 is never monitored
	if (!$season) {
		return false;
	}

	# Imaginary series are not monitored
	if (!seriesExists($series)) {
		return false;
	}

	# Imaginary seasons are not monitored
	if (!seasonExists($series, $season)) {
		return false;
	}

	# Series marked "skip" are not monitored
	if (file_exists(seriesPath($series) . '/skip')) {
		return false;
	}

	# Seasons marked done are not monitored
	if (file_exists(seasonPath($series, $season) . '/season_done')) {
		return false;
	}

	# The default behavior is to search
	return true;
}

# Find all the season in a provided series folder and determine which are being monitored
function findSeasons($series) {
	$retval = array();

	$path = seriesPath($series);
	$dir = opendir($path);
	if ($dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($path) . "\n");
	}
	while (false !== ($season = readdir($dir))) {

		# Skip junk
		if (isJunk($season)) {
			continue;
		}

		# We only care about directories
		$season_path = $path . '/' . $season;
		if (!is_dir($season_path)) {
			continue;
		}

		# Record the season number and search status
		if (preg_match('/Season\s+(\d+)/i', $season, $matches)) {
			$season_num = $matches[1];
			$retval[ $season_num ] = isMonitored($series, $season_num);
		}
	}
	closedir($dir);

	# Sort numerically; the directory listing typically returns a lexicographic order
	ksort($retval, SORT_NUMERIC);

	return $retval;
}

# Save the search status for all seasons in a series
function saveSeasons($series, $data, $series_last, $seasons_last) {
	# Do nothing if we are or just were in "skip" mode
	if ($data['skip'] || $series_last['skip']) {
		return;
	}

	# For each season
	$seasons = findSeasons($series);
	foreach ($seasons as $season => $status) {
		$season_path = seasonPath($series, $season);

		$monitored = $data[ 'season_' . $season ];
		$monitored_path = $season_path . '/season_done';
		if ($monitored) {
			if (file_exists($monitored_path)) {
				unlink($monitored_path);
			}
		} else {
			if (!file_exists($monitored_path)) {
				touch($monitored_path);
			}
		}

	}
}

# Add the specified season folder
function addSeason($series, $season) {

	# Cheap validation
	$season = intval($season);

	# Ensure the series exists
	if (!seriesExists($series)) {
		die('Invalid series: ' . htmlspecialchars($series) . "\n");
	}

	# Ensure the season does not exist
	$season_path = seasonPath($series, $season);
	if (file_exists($season_path)) {
		die('Invalid season: ' . htmlspecialchars($season) . "\n");
	}

	# Ensure the season number is listed on TVDB
	$flags = readFlags($series);
	if (!$flags['tvdb-id']) {
		die('No TVDB ID for series: ' . htmlspecialchars($series) . "\n");
	}
	$seasons = getTVDBSeasons($flags['tvdb-id'], $flags['tvdb-lid']);
	if (!$seasons[ $season ]) {
		die('Season not listed in TheTVDB: ' . htmlspecialchars($season) . "\n");
	}

	# Create the directory
	mkdir($season_path);
}

# Remove the specified season folder, if possible (i.e. if empty)
function delSeason($series, $season) {

	# Ensure the series exists
	if (!seriesExists($series)) {
		die('Invalid series: ' . htmlspecialchars($series) . "\n");
	}

	# Ensure the season exists
	if (!seasonExists($series, $season)) {
		die('Invalid season: ' . htmlspecialchars($season) . "\n");
	}

	# Remove the directory (or fail silently)
	@rmdir(seasonPath($series, $season));
}

?>
