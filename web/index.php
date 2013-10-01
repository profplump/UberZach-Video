<?

# Include the TV functions
require_once 'includes/main.php';

# Send our headers early
header('Content-type: text/html; charset=utf-8');

# Did the user request a specific show?
$show = false;
if (isset($_REQUEST['show'])) {
	# This is not a great filter, but it should make the string safe for use as a quoted path
	$show = preg_replace('/[\0\n\r]/', '', $_REQUEST['show']);
	$show = basename($show);
}

# Did the user request an update?
if ($show !== false && isset($_POST['Save'])) {
	echo '<h4 style="color: red;">Saving not yet implemented</h4>';

	# Grab the current settings for comparison
	global $TV_PATH;
	$series_path = $TV_PATH . '/'. $show;
	$series_last = readFlags($series_path);
	$seasons_last = findSeasons($series_path);

	saveFlags($series_path, $_POST, $series_last, $seasons_last);
	saveSeasons($series_path, $_POST, $series_last, $seasons_last);
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
