<?
# Config
$MEDIA_PATH    = '/mnt/media';
$TV_PATH       = $MEDIA_PATH . '/TV';
$MONITORED_CMD = '/home/profplump/bin/video/torrentMonitored.pl NULL ';
$EXISTS_FILES  = array('no_quality_checks', 'more_number_formats', 'skip');
$CONTENT_FILES = array('must_match', 'search_name');
$TVDB_URL      = 'http://thetvdb.com/?tab=series';

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

# Find all the monitored series/seasons from the given command
function monitoredShows($cmd) {
	$retval = array();
	$proc = popen($cmd . ' 2>&1', 'r');
	$paths = array();
	while (!feof($proc)) {
		$str = fread($proc, 4096);
		$arr = explode("\0", $str);
		$paths = array_merge($paths, $arr);
	}
	pclose($proc);

	# Translates paths to a series/seasons structure
	foreach ($paths as $path) {
		preg_match('@/([^\/]+)/Season\s+(\d+)@', $path, $matches);
		if (!array_key_exists($matches[1], $retval)) {
			$retval[ $matches[1] ] = array();
		}
		$retval[ $matches[1] ][ $matches[2] ] = true;
	}
	
	return $retval;
}

# Find all shows under the given path
function allShows($base)	{
	$retval = array();

	# Look for series folders
	$tv_dir = opendir($base);
	if ($tv_dir === FALSE) {
		die('Unable to opendir(): ' . $path . "\n");
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

		# Record the show title
		$retval[ $show ] = array();

		# Look for season folders
		$show_dir = opendir($show_path);
		if ($show_dir === FALSE) {
			die('Unable to opendir(): ' . $show_path . "\n");
		}
		while (false !== ($season = readdir($show_dir))) {

			# Skip junk
			if (isJunk($show)) {
				continue;
			}

			# We only care about directories
			$season_path = $show_path . '/' . $season;
			if (!is_dir($season_path)) {
				continue;
			}

			# Record season numbers
			if (preg_match('/Season\s+(\d+)/i', $season, $matches)) {
				$retval[ $show ][ $matches[1] ] = true;
			}
		}
		closedir($show_dir);
	}
	closedir($tv_dir);
	
	return $retval;
}

# Print a DL of all shows and note the available and monitored seasons
function printAllShows() {
	global $TV_PATH;
	global $MEDIA_PATH;
	global $MONITORED_CMD;

	$shows = allShows($TV_PATH);
	$monitored = monitoredShows($MONITORED_CMD . $MEDIA_PATH);

	echo "<dl>\n";
	foreach ($shows as $show => $seasons) {
		echo '<dt><a href="?show=' . urlencode($show) . '">' . htmlspecialchars($show) . "</a></dt>\n";
		foreach ($seasons as $season => $val) {
			if ($val) {
				echo '<dd>Season ' . htmlspecialchars($season);
				if ($monitored[ $show ][ $season ]) {
					echo ' (monitored)';
				}
				echo "</dd>\n";
			}
		}
	}
	echo "</dl>\n";
}

function printShow($show) {
	global $TV_PATH;
	global $EXISTS_FILES;
	global $CONTENT_FILES;
	global $TVDB_URL;

	# Construct our show path and make sure it's reasonable
	$path = $TV_PATH . '/' . $show;
	if (!is_dir($path)) {
		die('Unknown show: ' . $show);
	}

	# Look for all the exists and content files
	$flags = array();
	foreach ($EXISTS_FILES as $name) {
		$flags[ $name ] = false;
		if (file_exists($path . '/' . $name)) {
			$flags[ $name ] = true;
		}
	}
	foreach ($CONTENT_FILES as $name) {
		$flags[ $name ] = false;
		$file = $path . '/' . $name;
		if (is_readable($file)) {
			$flags[ $name ] = trim(file_get_contents($file));
		}
	}

	# Read the TVDB IDs from the *.webloc file
	$show_dir = opendir($path);
	if ($show_dir === FALSE) {
		die('Unable to opendir(): ' . $path . "\n");
	}
	while (false !== ($name = readdir($show_dir))) {

		# Skip junk
		if (isJunk($name)) {
			continue;
		}

		# We only care about readable *.webloc files
		if (!preg_match('/\.webloc$/', $name)) {
			continue;
		}

		# The file must be readable to be useful
		$file = $path . '/' . $name;
		if (!is_readable($file)) {
			continue;
		}

		# Read and parse the file
		$str = trim(file_get_contents($file));
		if (preg_match('/[\?\&]id=(\d+)/', $str, $matches)) {
			$flags['tvdb-id'] = $matches[1];
		}
		if (preg_match('/[\?\&]lid=(\d+)/', $str, $matches)) {
			$flags['tvdb-lid'] = $matches[1];
		}

		# Construct a URL
		if (array_key_exists('tvdb-id', $flags)) {
			$flags['url'] = $TVDB_URL . '&id=' . $flags['tvdb-id'];
			if (array_key_exists('tvdb-lid', $flags)) {
				$flags['url'] .= '&lid=' . $flags['tvdb-lid'];
			}
		}
	}
	closedir($show_dir);

	echo '<pre>';
	echo $show . "\n";
	print_r($flags);
	echo '</pre>';
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

