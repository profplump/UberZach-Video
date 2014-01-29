<?

require 'config.php';

function seriesExists($series) {
	return is_dir(seriesPath($series));
}

function seriesPath($series) {
	global $TV_PATH;
	return $TV_PATH . '/' . $series;
}

# Find all series and seasons under a given path
function allSeriesSeasons($base, $use_cache = true) {
	global $CACHE_AGE;
	global $CACHE_FILE;
	$retval = array();

	# Use the cache file if it exists, is fresh and contains at least 1 series
	if ($use_cache && file_exists($CACHE_FILE)) {
		if (filemtime($CACHE_FILE) > time() - $CACHE_AGE) {
			$retval = @unserialize(@file_get_contents($CACHE_FILE));
			if (is_array($retval) && count($retval) > 0) {
				return $retval;
			}
		}
	}

	# Read live data from the disk
	$all_series = allSeries($base);
	foreach ($all_series as $series) {
		$retval[ $series ] = findSeasons($series);
	}

	# Always update the cache if we read from disk
	$temp = @tempnam(dirname($CACHE_FILE), 'tv_web.cache');
	if ($temp) {
		file_put_contents($temp, serialize($retval));
		rename($temp, $CACHE_FILE);
	}

	return $retval;
}

# Find all series under the given path
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

		$retval[] = $series;
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

	# Find the most recent mtime in the series directory
	$flags['mtime'] = filemtime($path);
	$objects = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($path), RecursiveIteratorIterator::SELF_FIRST);
	foreach($objects as $name => $object) {

		# Skip junk
		if (isJunk($name)) {
			continue;
		}

		# Track the most recent mtime
		$mtime = filemtime($name);
		if ($mtime > $flags['mtime']) {
			$flags['mtime'] = $mtime;
		}
	}

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
	die_if_not_authenticated();

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

	# Force a cache update
	clearCache();
}

# Add a series as identified by TVDB URL or ID
function addSeries($str) {
	die_if_not_authenticated();

	global $TVDB_LANG_ID;
	$id     = false;
	$lid    = false;
	$series = false;

	# Accept URLs or raw IDs
	if (preg_match('/^\d+$/', $str)) {
		$id = intval($str);
	} else {
		$result = parseTVDBURL($str);
		$id = $result['tvdb-id'];
		$lid = $result['tvdb-lid'];
	}

	# Ensure we got something useful
	if (!$id) {
		die('Invalid ID or URL: ' . htmlspecialchars($str) . "\n");
	}
	if (!$lid) {
		$lid = $TVDB_LANG_ID;
	}

	# Find the show name
	$series = getTVDBTitle($id, $lid);

	# Ensure the title is reasonable
	if (!$series) {
		die('No such TVDB series: ' . htmlspecialchars($id) . "\n");
	}

	# Clean the title for filesystem use
	$series = cleanSeries($series);

	if (seriesExists($series)) {
		die('Series already exists: ' . htmlspecialchars($series) . "\n");
	}

	# Return the series name or FALSE on failure
	$retval = false;

	# If all is well, create the folder and webloc file
	$series_path = seriesPath($series);
	if (@mkdir($series_path)) {
		writeWebloc(TVDBURL($id, $lid), $series_path . '/' . $series . '.webloc');
		addSeason($series, 1);
		$retval = $series;
	}

	return $retval;
}

?>
