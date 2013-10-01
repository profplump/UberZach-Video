<?

require 'config.php';

function printShow($show) {
	global $TV_PATH;
	global $EXISTS_FILES;
	global $CONTENT_FILES;

	# Construct our show path and make sure it's reasonable
	$path = $TV_PATH . '/' . $show;
	$show_html = htmlspecialchars($show);
	if (!is_dir($path)) {
		die('Unknown show: ' . $show_html);
	}

	# Check the flags
	$flags = readFlags($path);

	# Check the seasons
	$seasons = findSeasons($path);

	# Header
	echo '<h1>' . $show_html . '</h1>';
	echo '<form action="' . $_SERVER['PHP_SELF'] . '?show=' . urlencode($show) . '" method="post">';
	echo '<input type="hidden" name="show" value="' . $show_html . '"/>';

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
	echo '<p><input type="submit" name="Save" value="Save"/></p>';
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

?>
