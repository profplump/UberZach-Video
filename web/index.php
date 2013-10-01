<?
# Config
$MEDIA_PATH    = '/mnt/media';
$TV_PATH       = $MEDIA_PATH . '/TV';
$EXISTS_FILES  = array('no_quality_checks', 'more_number_formats', 'skip');
$CONTENT_FILES = array('must_match', 'search_name');
$TVDB_URL      = 'http://thetvdb.com/?tab=series';

function writeWebloc($url, $path) {
	$encoded_url = htmlspecialchars($url, ENT_XML1, 'UTF-8');

	$str = '<?xml version="1.0" encoding="UTF-8"?>';
	$str .= '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">';
	$str .= '<plist version="1.0">';
	$str .= '<dict>';
	$str .= '<key>URL</key>';
	$str .= '<string>' . $encoded_url . '</string>';
	$str .= '</dict>';
	$str .= '</plist>';

	file_put_contents($path, $str);
}

# True if the input path is junk -- self-links, OS X noise, etc.
function isJunk($path) {
	$path = basename($path);
	
	# Ignore certain fixed paths
	foreach (array('.', '..', '.DS_Store') as $value) {
		if ($path == $value) {
			return true;
		}
	}
	
	# Ignore ._ paths
	if (preg_match('/^\.\_/', $path)) {
		return true;
	}
	
	# Otherwise the path is good
	return false;
}

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

# Find all shows under the given path
function allShows($base)	{
	$retval = array();

	# Look for series folders
	$tv_dir = opendir($base);
	if ($tv_dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($path) . "\n");
	}
	while (false !== ($show = readdir($tv_dir))) {

		# Skip junk
		if (isJunk($show)) {
			continue;
		}

		# We only care about directories
		$show_path = $base . '/' . $show;
		if (!is_dir($show_path)) {
			continue;
		}

		# Record the show title and look for season folders
		$retval[ $show ] = findSeasons($show_path);
	}
	closedir($tv_dir);
	
	return $retval;
}

# Find the *.webloc file, if in, in the provided folder
function findWebloc($path) {
	$retval = false;

	$dir = opendir($path);
	if ($dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($path) . "\n");
	}
	while (false !== ($name = readdir($dir))) {

		# Skip junk
		if (isJunk($name)) {
			continue;
		}

		# We only care about *.webloc files
		if (!preg_match('/\.webloc$/', $name)) {
			continue;
		}

		# The file must be readable to be useful
		$file = $path . '/' . $name;
		if (is_readable($file)) {
			$retval = $file;
			last;
		}
	}
	closedir($dir);

	return $retval;
}

# Read and parse the provided *.webloc file
function readWebloc($file) {
	global $TVDB_URL;
	$retval = array(
		'tvdb-id'  => false,
		'tvdb-lid' => false,
		'url'      => false,
	);

	# Read and parse the file
	# Accept both the resource-fork and data-fork (i.e. plist) verisons of the file
	$str = trim(file_get_contents($file));
	if (preg_match('/(?:\?|\&(?:amp;)?)id=(\d+)/', $str, $matches)) {
		$retval['tvdb-id'] = $matches[1];
	}
	if (preg_match('/(?:\?|\&(?:amp;)?)lid=(\d+)/', $str, $matches)) {
		$retval['tvdb-lid'] = $matches[1];
	}

	# Construct a URL
	if ($retval['tvdb-id'] !== false) {
		$retval['url'] = $TVDB_URL . '&id=' . $retval['tvdb-id'];
		if ($retval['tvdb-lid'] !== false) {
			$retval['url'] .= '&lid=' . $retval['tvdb-lid'];
		}
	}

	return $retval;
}

# Read and parse all of the series-level exists, content, and *.webloc files
function readFlags($path) {
	global $EXISTS_FILES;
	global $CONTENT_FILES;
	$flags = array();

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

function printShow($show) {
	global $TV_PATH;
	global $EXISTS_FILES;
	global $CONTENT_FILES;

	# Construct our show path and make sure it's reasonable
	$path = $TV_PATH . '/' . $show;
	if (!is_dir($path)) {
		die('Unknown show: ' . htmlspecialchars($show));
	}

	# Check the flags
	$flags = readFlags($path);

	# Check the seasons
	$seasons = findSeasons($path);

	# Header
	echo '<h1>' . htmlspecialchars($show) . '</h1>';
	echo '<form action="' . $SERVER['PHP_SELF'] . '" method="post">';

	# Exists and content flags
	echo '<h2>Series Parameters</h2>';
	echo '<p>';
	foreach ($EXISTS_FILES as $file) {
		$file_html = htmlspecialchars($file);
		echo '<label><input value="1" type="checkbox" name="' . $file_html . '" ';
		if ($flags[ $file ]) {
			echo 'checked="checked"';
		}
		echo '/> ' . $file_html . '</label><br/>';
	}
	foreach ($CONTENT_FILES as $file) {
		$file_html = htmlspecialchars($file);
		echo '<label><input type="text" size="40" name="' . $file_html . '" ';
		if ($flags[ $file ]) {
			echo 'value="' . htmlspecialchars($flags[ $file ]) . '"';
		}
		echo '/> ' . $file_html . '</label><br/>';
	}
	echo '</p>';

	# TVDB URL
	echo '<h2>The TVDB URL</h2>';
	echo '<p><a href="' . htmlspecialchars($flags['url']) . '">' . htmlspecialchars($flags['url']) . '</a></p>';

	# Seasons
	echo '<h2>Season Parameters</h2>';
	echo '<p>';
	foreach ($seasons as $season => $monitored) {
		$season_html = htmlspecialchars($season);
		echo '<label>Season ' . $season_html . ' ';
		echo '<input type="checkbox" value="1" name="season_' . $season_html . '" ';
		if ($monitored !== false) {
			echo 'checked="checked"';
		}
		echo '/></label>';
		echo '<input type="text" size="150" name="url_' . $season_html . '" value="';
		if ($monitored !== false && $monitored !== true) {
			echo htmlspecialchars($monitored);
		}
		echo '"/><br/>';
	}
	echo '</p>';

	# Footer
	echo '<p><input type="submit" name="submit" value="Save"/></p>';
	echo '</form>';
}

# Print a DL of all shows and note the available and monitored seasons
function printAllShows() {
	global $TV_PATH;
	global $MEDIA_PATH;

	$shows = allShows($TV_PATH);

	echo "<dl>\n";
	foreach ($shows as $show => $seasons) {
		echo '<dt><a href="?show=' . urlencode($show) . '">' . htmlspecialchars($show) . "</a></dt>\n";
		foreach ($seasons as $season => $monitored) {
			echo '<dd>Season ' . htmlspecialchars($season);
			if ($monitored) {
				echo ' (monitored)';
			}
			echo "</dd>\n";
		}
	}
	echo "</dl>\n";
}

#=========================================================================================

# Send our headers early
header('Content-type: text/html; charset=utf-8');

# Did the user request a specific show?
$show = false;
if (isset($_REQUEST['show'])) {
	# This is not a great filter, but it should make the string safe for use as a quoted path
	$show = preg_replace('/[\0\n\r]/', '', $_REQUEST['show']);
	$show = basename($show);
}

#=========================================================================================

# Generic XHTML 1.1 header
print <<<ENDOLA
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" 
   "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
	<title>UberZach TV</title>
</head>
<body>

ENDOLA;

if ($show === false) {
	printAllShows();
} else {
	printShow($show);
}

# Generic XHTML 1.1 footer
print <<<ENDOLA
</body>
</html>
ENDOLA;
?>
