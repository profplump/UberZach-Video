<?

require 'config.php';

function printSeries($series) {
	global $EXISTS_FILES;
	global $CONTENT_FILES;

	# Ensure our series name is reasonable
	$series_html = htmlspecialchars($series);
	if (!seriesExists($series)) {
		die('Unknown series: ' . $series_html);
	}

	# Check the flags
	$flags = readFlags($series);

	# Check the seasons
	$seasons = findSeasons($series);

	# Header
	echo '<h1>' . $series_html . '</h1>';
	echo '<form action="' . $_SERVER['PHP_SELF'] . '?series=' . urlencode($series) . '" method="post">';
	echo '<input type="hidden" name="series" value="' . $series_html . '"/>';

	# TVDB URL
	echo '<h2>TVDB</h2>';
	echo '<p><a target="_blank" href="' . 
		htmlspecialchars($flags['url']) .
		'">' . htmlspecialchars($flags['url']) . '</a></p>';

	# Series flags
	echo '<h2>Series Parameters</h2>';
	echo '<p>';
	foreach ($EXISTS_FILES as $file) {
		if ($file == 'skip' || !$flags['skip']) {
			$file_html = htmlspecialchars($file);
			echo '<label><input value="1" type="checkbox" name="' . $file_html . '" ';
			if ($flags[ $file ]) {
				echo 'checked="checked"';
			}
			echo '/> ' . $file_html . '</label><br/>';
		}
	}
	if (!$flags['skip']) {
		foreach ($CONTENT_FILES as $file) {
			$file_html = htmlspecialchars($file);
			echo '<label><input type="text" size="40" name="' . $file_html . '" ';
			if ($flags[ $file ]) {
				echo 'value="' . htmlspecialchars($flags[ $file ]) . '"';
			}
			echo '/> ' . $file_html . '</label><br/>';
		}
		echo '</p>';
	}

	# Seasons
	if (!$flags['skip']) {
		echo '<h2>Season Parameters</h2>';

		# Existing seasons
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

		# Add a season
		$next_season = max(array_keys($seasons)) + 1;
		echo '<p>Add season: ';
		echo '<input type="text" size="2" name="season_new" value="' . htmlspecialchars($next_season) . '"/>';
		echo '<input type="submit" name="AddSeason" value="Add Season">';
		echo '</p>';

	}

	# Save button
	echo '<p><input type="submit" name="Save" value="Save"/></p>';

	# Footer
	echo '</form>';
}

# Print a DL of all series and note the available and monitored seasons
function printAllSeries() {
	global $TV_PATH;
	$all_series = allSeries($TV_PATH);

	echo "<dl>\n";
	foreach ($all_series as $series => $seasons) {
		echo '<dt><a href="?series=' . urlencode($series) . '">' . htmlspecialchars($series) . "</a></dt>\n";
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
