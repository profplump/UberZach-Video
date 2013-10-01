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
function findSeasons($path) {
	$retval = array();

	# Check for the skip file
	$skip = false;
	if (file_exists($path . '/skip')) {
		$skip = true;
	}

	$dir = opendir($path);
	if ($dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($path) . "\n");
	}
	while (false !== ($season = readdir($dir))) {

		# Skip junk
		if (isJunk($show)) {
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
function saveSeasons($data) {
}

# Add a folder for the provided show and season
function addSeason($show, $season) {
	global $TV_DIR;

	# Ensure the show exists
	$show_path = $TV_DIR . '/' . $show;
	if (!is_dir($show_path)) {
		die('Invalid show: ' . htmlspecialchars($show) . "\n");
	}

	# Ensure the season does not exist
	$season_path = $show_path . '/Season ' . intval($season);
	if (file_exists($season_path)) {
		die('Invalid season: ' . htmlspecialchars($season) . "\n");
	}

	# Create the directory
	mkdir($season_path);
}

?>
