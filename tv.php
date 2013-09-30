<?
	$MEDIA_PATH='/mnt/media';
	$TV_PATH=$MEDIA_PATH . '/TV';
	$MONITORED_CMD='/home/profplump/bin/video/torrentMonitored.pl NULL ' . $MEDIA_PATH;

	function isJunk($path) {
		$path = basename($path);
		if (preg_match('/^\.+$/', $path)) {
			return true;
		}
		if (preg_match('/^\.\_/', $path)) {
			return true;
		}
		if (preg_match('/^\.DS_Store$/', $path)) {
			return true;
		}
		return false;
	}

	$monitored = array();
	{
		$proc = popen($MONITORED_CMD . ' 2>&1', 'r');
		$paths = array();
		while (!feof($proc)) {
			$str = fread($proc, 4096);
			$arr = explode("\0", $str);
			$paths = array_merge($paths, $arr);
		}
		pclose($proc);

		foreach ($paths as $path) {
			preg_match('@/([^\/]+)/Season\s+(\d+)@', $path, $matches);
			if (!array_key_exists($matches[1], $monitored)) {
				$monitored[ $matches[1] ] = array();
			}
			$monitored[ $matches[1] ][ $matches[2] ] = true;
		}
	}

	$shows = array();
	{
		# Look for series folders
		$tv_dir = opendir($TV_PATH);
		if ($tv_dir === FALSE) {
			die('Unable to opendir(): ' . $TV_PATH . "\n");
		}
		while (false !== ($show = readdir($tv_dir))) {

			# Skip junk
			if (isJunk($show)) {
				continue;
			}

			# We only care about directories
			$show_path = $TV_PATH . '/' . $show;
			if (!is_dir($show_path)) {
				continue;
			}

			# Record the show title
			$shows[ $show ] = array();

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
					$shows[ $show ][ $matches[1] ] = true;
				}
			}
			closedir($show_dir);
		}
		closedir($tv_dir);
	}

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

	echo '<dl>';
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

print <<<ENDOLA
</body>
</html>
ENDOLA;
?>

