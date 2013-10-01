<?

require 'config.php';

# True if the provided season folder is being monitored
function isMonitored($season_path) {
	if (file_exists(dirname($season_path) . '/skip')) {
		return false;
	}

	if (file_exists($season_path . '/season_done')) {
		return false;
	}

	$season = 0;
	if (preg_match('/^Season\s+(\d+)$/i', basename($season_path), $matches)) {
		$season = $matches[1];
	}
	if (!$season) {
		return false;
	}

	return true;
}

# Get the season search status, including the URL (if any) for the provided path
function seasonSearch($season_path) {
	$retval = isMonitored($season_path);

	if ($retval) {
		$file = $season_path . '/url';
		if (is_readable($file)) {
			$retval = trim(file_get_contents($file));
		}
	}

	return $retval;
}

# Find all the season in a provided series folder and determine which are being monitored
function findSeasons($series) {
	$retval = array();

	# Check for the skip file
	$skip = false;
	if (file_exists($path . '/skip')) {
		$skip = true;
	}

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
			$retval[ $matches[1] ] = seasonSearch($season_path);
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
		$season_path = seriesPath($series) . '/Season ' . $season;

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

		$url = $data[ 'url_' . $season ];
		$url_path = $season_path . '/url';
		if ($url) {
			if (isMonitored($season_path)) {
				file_put_contents($url_path, $url . "\n");
			}
		} else {
			if ($seasons_last[ $season ] && isMonitored($season_path)) {
				if (file_exists($url_path)) {
					unlink($url_path);
				}
			}
		}
	}
}

# Add the specified season folder
function addSeason($series, $season) {

	# Ensure the series exists
	if (!seriesExists($series)) {
		die('Invalid series: ' . htmlspecialchars($series) . "\n");
	}

	# Ensure the season does not exist
	$season_path = seriesPath($series) . '/Season ' . intval($season);
	if (file_exists($season_path)) {
		die('Invalid season: ' . htmlspecialchars($season) . "\n");
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
	$season_path = seriesPath($series) . '/Season ' . intval($season);
	if (!file_exists($season_path)) {
		die('Invalid season: ' . htmlspecialchars($season) . "\n");
	}

	# Remove the directory (or fail silently)
	@rmdir($season_path);
}

?>
