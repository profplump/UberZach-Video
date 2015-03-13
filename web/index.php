<?

# Include the TV functions
require_once 'includes/main.php';

# Send our headers early
header('Content-type: text/html; charset=utf-8');

# Form debug
if (false) {
	echo '<H4>$_POST</H4>';
	echo '<pre>';
	print_r($_POST);
	echo '</pre>';
}

# Did the user request a specific series?
$series = false;
if (isset($_REQUEST['series'])) {

	# Allow overloading of series requests for certain functions
	if (preg_match('/^\*\*\*/', $_REQUEST['series'])) {
		require_authentication();

		# Force refresh of the series list
		if (preg_match('/refresh/i', $_REQUEST['series'])) {
			set_time_limit(0);
			global $TV_PATH;
			allSeriesSeasons($TV_PATH, false);
		}

		# Always redirect to the main page
		global $MAIN_PAGE;
		header('Location: ' . $MAIN_PAGE);
		exit();
	}

	# Set the safe series name
	$series = cleanSeries($_REQUEST['series']);
}

# Did the user request an update?
if ($series !== false && isset($_POST['Save'])) {
	require_authentication();

	# Grab the current settings for comparison
	$series_last = readFlags($series);
	$seasons_last = findSeasons($series);

	# Save series and season data
	saveFlags($series, $_POST, $series_last, $seasons_last);
	saveSeasons($series, $_POST, $series_last, $seasons_last);
}

# Did the user add a season?
if ($series !== false && isset($_POST['AddSeason'])) {
	require_authentication();

	# Add a season folder
	$season = intval($_POST['season_add']);
	addSeason($series, $season);
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
		require_authentication();

		# Remove a season folder (if empty)
		delSeason($series, $season);
	}
}

# Did the user add a series?
if ($series === false && isset($_POST['series_add'])) {
	require_authentication();

	# Add a series folder
	$series = addSeries($_POST['series_add']);
}

#=========================================================================================

printHeader('UberZach TV');

if ($series === false) {
	printAllSeries();
} else {
	printSeries($series);
}

printFooter();

?>
