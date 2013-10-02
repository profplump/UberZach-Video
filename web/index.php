<?

# Include the TV functions
require_once 'includes/main.php';

# Send our headers early
header('Content-type: text/html; charset=utf-8');

# Did the user request a specific series?
$series = false;
if (isset($_REQUEST['series'])) {
	$series = cleanSeries($_REQUEST['series']);
}

# Did the user request an update?
if ($series !== false && isset($_POST['Save'])) {
	# Require auth (or for the time being, specific IP addresses)
	if (preg_match('/^(?:172\.19\.[17]\.|2602:3f:e50d:76|74\.93\.97\.65)/', $_SERVER['REMOTE_ADDR'])) {

		# Grab the current settings for comparison
		$series_last = readFlags($series);
		$seasons_last = findSeasons($series);

		# Save series and season data
		saveFlags($series, $_POST, $series_last, $seasons_last);
		saveSeasons($series, $_POST, $series_last, $seasons_last);
	} else {
		echo '<h4 style="color: red;">Cannot save: User not authenticated</h4>';
	}
}

# Did the user add a season?
if ($series !== false && isset($_POST['AddSeason'])) {
	# Require auth (or for the time being, specific IP addresses)
	if (preg_match('/^(?:172\.19\.[17]\.|2602:3f:e50d:76|74\.93\.97\.65)/', $_SERVER['REMOTE_ADDR'])) {

		# Add a season folder
		$season = intval($_POST['season_add']);
		addSeason($series, $season);
	} else {
		echo '<h4 style="color: red;">Cannot save: User not authenticated</h4>';
	}
}

# Did the user delete a season?
if ($series !== false) {
	$season = false;
	foreach (array_keys($_POST) as $key) {
		if (preg_match('/season_del_(\d+)/', $key, $matches)) {
			$season = intval($matches[1]);
			last;
		}
	}
	if ($season !== false) {

		# Require auth (or for the time being, specific IP addresses)
		if (preg_match('/^(?:172\.19\.[17]\.|2602:3f:e50d:76|74\.93\.97\.65)/', $_SERVER['REMOTE_ADDR'])) {

			# Remove a season folder (if empty)
			delSeason($series, $season);
		} else {
			echo '<h4 style="color: red;">Cannot save: User not authenticated</h4>';
		}
	}
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

if ($series === false) {
	printAllSeries();
} else {
	printSeries($series);
}

# Generic XHTML 1.1 footer
print <<<ENDOLA
</body>
</html>
ENDOLA;
?>
