<?

require 'config.php';

function seriesExists($series) {
	return is_dir(seriesPath($series));
}

function seriesPath($series) {
	global $TV_PATH;
	return $TV_PATH . '/' . $series;
}

# Find all seriess under the given path
function allSeries($base) {
	$retval = array();

	# Look for series folders
	$tv_dir = opendir($base);
	if ($tv_dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($path) . "\n");
	}
	while (false !== ($series = readdir($tv_dir))) {

		# Skip junk
		if (isJunk($series)) {
			continue;
		}

		# Ensure the series is reasonable
		if (!seriesExists($series)) {
			continue;
		}

		# Record the series title and look for season folders
		$retval[ $series ] = findSeasons($series);
	}
	closedir($tv_dir);
	
	return $retval;
}

# Read and parse all of the series-level exists, content, and *.webloc files
function readFlags($series) {
	global $EXISTS_FILES;
	global $CONTENT_FILES;
	$flags = array();

	# Ensure the series exists
	if (!seriesExists($series)) {
		die('Invalid series: ' . htmlspecialchars($series) . "\n");
	}
	$path = seriesPath($series);

	# Look for all the exists files
	foreach ($EXISTS_FILES as $name) {
		$flags[ $name ] = false;
		if (file_exists($path . '/' . $name)) {
			$flags[ $name ] = true;
		}
	}

	# Read all the content files
	foreach ($CONTENT_FILES as $name) {
		$flags[ $name ] = false;
		$file = $path . '/' . $name;
		if (is_readable($file)) {
			$flags[ $name ] = trim(file_get_contents($file));
		}
	}

	# Read the TVDB IDs from the *.webloc file
	$webloc = findWebloc($path);
	if ($webloc !== false) {
		$flags = array_merge($flags, readWebloc($webloc));
	}

	return $flags;
}

# Parse and save all of the serires-level exists and content files
function saveFlags($series, $data, $series_last, $seasons_last) {
	global $EXISTS_FILES;
	global $CONTENT_FILES;

	# Ensure the series exists
	if (!seriesExists($series)) {
		die('Invalid series: ' . htmlspecialchars($series) . "\n");
	}
	$series_path = seriesPath($series);

	# Special handling for "skip"
	{
		$path = $series_path . '/skip';
		if ($data['skip']) {
			if (!file_exists($path)) {
				touch($path);
			}
		} else {
			if (file_exists($path)) {
				unlink($path);
			}
		}
	}

	# Ignore everything else if we are now or were just in "skip" mode
	if ($series_last['skip'] || $data['skip']) {
		return;
	}
	
	# Exists files
	foreach ($EXISTS_FILES as $file) {
		$path = $series_path . '/' . $file;
		if ($data[ $file ]) {
			if (!file_exists($path)) {
				touch($path);
			}
		} else {
			if (file_exists($path)) {
				unlink($path);
			}
		}
	}

	# Content files
	foreach ($CONTENT_FILES as $file) {
		$path = $series_path . '/' . $file;
		if ($data[ $file ]) {
			file_put_contents($path, $data[ $file ]);
		} else {
			if (file_exists($path)) {
				unlink($path);
			}
		}
	}
}

# Add a series as identified by TVDB ID
function addSeries($id) {
}

?>
