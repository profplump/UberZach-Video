<?

require 'config.php';

function printSeries($series) {
	global $EXISTS_FILES;
	global $CONTENT_FILES;

	# Ensure our series name is reasonable
	$series_html = htmlspecialchars(displayTitle($series));
	if (!seriesExists($series)) {
		die('Unknown series: ' . $series_html);
	}

	# Grab the flag and season data
	$flags = readFlags($series);
	$seasons = findSeasons($series);

	# Header
	echo '<div data-role="header">';
	echo '<h1>' . $series_html . '</h1>';
	echo '<a href="' . $_SERVER['PHP_SELF'] . '" data-icon="arrow-l" data-iconpos="notext" data-ajax="false">Back</a>';
	echo '</div>';

	# Form
	echo '<form action="' . $_SERVER['PHP_SELF'] . '?series=' . urlencode($series) . '" method="post" data-ajax="false">';
	echo '<input type="hidden" name="series" value="' . htmlspecialchars($series) . '"/>';

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
		echo '<dl>';
		foreach ($seasons as $season => $monitored) {
			$season_html = htmlspecialchars($season);

			$episodes = findEpisodes($series, $season);

			echo '<h3>Season ' . $season_html . '</h3>';
			echo '<label>Monitored: <input type="checkbox" value="1" name="season_' . $season_html . '" ';
			if ($monitored !== false) {
				echo 'checked="checked"';
			}
			echo '/></label><br/>';
			echo '<label>Search URL: <input type="text" size="150" name="url_' . $season_html . '" value="';
			if ($monitored !== false && $monitored !== true) {
				echo htmlspecialchars($monitored);
			}
			echo '"/></label><br/>';
			echo '<input type="submit" name="season_del_' . $season_html . '" value="Delete"><br/>';
			echo 'Episode count: ' . count($episodes) . '<br/>';
			echo 'Highest episode number: ' . @max(array_keys($episodes)) . '<br/>';
			echo '<hr/>';
		}
		echo '</dl>';

		# Add a season
		$next_season = @max(array_keys($seasons)) + 1;
		echo '<p>Add season: ';
		echo '<input type="text" size="2" name="season_add" value="' . htmlspecialchars($next_season) . '"/>';
		echo '<input type="submit" name="AddSeason" value="Add Season">';
		echo '</p>';

	}

	# Save button
	echo '<p><input type="submit" name="Save" value="Save"/></p>';

	# End Form
	echo '</form>';

	# TheTVDB Frame
	$url_html = htmlspecialchars(TVDBURL($flags['tvdb-id'], $flags['tvdb-lid']));
	echo '<h2>The TVDB</h2>';
	echo '<p><a target="_blank" href="' . $url_html . '">' . $url_html . '</a></p>';
	echo '<iframe height="5000" style="width: 90%; display: block; margin: 0 auto;" src="' . $url_html . '">';
	echo '</iframe>';
}

# Print a DL of all series and note the available and monitored seasons
function printAllSeries() {
	global $TV_PATH;
	$all_series = allSeriesSeasons($TV_PATH);

	# Wrap the entire jquery section
	echo '<div data-role="page" id="linkbar-page">';

	# Header
	echo '<div data-role="header">';
	echo '<h1>UberZach TV</h1>';
	echo '</div>';

	# Wrap all the sorted/filtered content
	echo '<div data-role="content">';

	# Display the sorter
	echo '<div id="sorter">';
	echo '<ul data-role="listview">';
	echo '<li><span>#</span></li>';
	foreach (range('A', 'Z') as $char) {
		echo '<li><span>' . $char . '</span></li>';
	}
	echo '</ul>';
	echo '</div>';

	# Sort by "sortTitle" -- an approximation of the Plex sort title
	$sorted_series = array();
	foreach ($all_series as $series => $seasons) {
		$sorted_series[ $series ] = sortTitle($series);
	}
	asort($sorted_series, SORT_FLAG_CASE | SORT_NATURAL);

	# Display all series
	echo '<ul data-role="listview" data-filter="true" data-autodividers="true" id="sortedList">';
	foreach ($sorted_series as $series => $sort) {

		# Determine if the series has any monitored seasons
		$monitored = false;
		foreach ($all_series[ $series ] as $season => $status) {
			if ($status) {
				$monitored = true;
			}
		}

		echo '<li><a href="?series=' . urlencode($series) . '">';
		if ($monitored) {
			echo '<img src="tv.png" class="ui-li-icon ui-corner-none">';
		}
		echo htmlspecialchars($sort);
		echo '<span class="ui-li-count">' . count($all_series[ $series ]) . '</span>';
		echo '</a></li>';
	}
	echo '</ul>';

	# End the sorted/filtered content
	echo '</div>';

	# Add a series
	echo '<div data-role="footer"><p>';
	echo '<form action="' . $_SERVER['PHP_SELF'] . '" method="post" data-ajax="false">';
	echo '<label>TheTVDB ID or URL: <input type="text" name="series_add"/></label>';
	echo '<input type="submit" value="Add Series"/>';
	echo '</form>';
	echo '</p></div>';

	# End the jquery section
	echo '</div>';
}

?>
