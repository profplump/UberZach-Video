<?
# Config
$MEDIA_PATH    = '/mnt/media';
$MONITORED_CMD = '/home/profplump/bin/video/torrentMonitored.pl NULL ';

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

# Find all shows and all monitored shows
$shows = allShows($MEDIA_PATH . '/TV');
$monitored = monitoredShows($MONITORED_CMD . $MEDIA_PATH);

# Generic XHTML 1.1 header
header('Content-type: text/html; charset=utf-8');
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

# Print a DL of all shows and note the available and monitored seasons
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

# Generic XHTML 1.1 footer
print <<<ENDOLA
</body>
</html>
ENDOLA;
?>

