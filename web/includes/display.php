<?

function printSeries($series) {
	require 'config.php';
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
	if (authenticated()) {
		echo '<a href="' . $LOGIN_PAGE . '?logout=1" data-ajax="false">Logout: ' . username() . '</a>';
	} else {
		echo '<a href="' . $LOGIN_PAGE . '" data-ajax="false">Login</a>';
	}
	echo '</div>';

	# Wrap all the content
	echo '<div role="main" class="ui-content" style="width: 95%; margin-left: auto; margin-right: auto;">';

	# Form
	echo '<form action="' . $_SERVER['PHP_SELF'] . '?series=' . urlencode($series) . '" method="post" data-ajax="false">';
	echo '<input type="hidden" name="series" value="' . htmlspecialchars($series) . '"/>';

	# Series flags
	echo '<h2>Series Parameters</h2>';
	echo '<fieldset><div data-role="fieldcontain">';
	foreach ($EXISTS_FILES as $file) {
		if ($file == 'skip' || !$flags['skip']) {
			$file_html = htmlspecialchars($file);
			echo '<label for="' . $file_html . '">' . $file_html . '</label>';
			echo '<input type="checkbox" data-inline="true" data-role="flipswitch" value="1" id="' .
				$file_html . '" name="' . $file_html . '"';
			if ($flags[ $file ] !== false) {
				echo ' checked';
			}
			echo '/><br style="clear: both" />';
		}
	}
	echo '</div></fieldset>';
	if (!$flags['skip']) {
		echo '<fieldset><div data-role="fieldcontain">';
		foreach ($CONTENT_FILES as $file) {
			$file_html = htmlspecialchars($file);
			echo '<label for="' . $file_html . '">' . $file_html . ':</label>';
			echo '<input type="text" data-inline="true" id="' . $file_html . '" name="' . $file_html . '"';
			if ($flags[ $file ]) {
				echo ' value="' . htmlspecialchars($flags[ $file ]) . '"';
			}
			echo '>';
		}
		echo '</div></fieldset>';
	}

	# Save button
	echo '<p><input type="submit" name="Save" value="Save"/></p>';

	# Seasons
	if (!$flags['skip']) {
		echo '<h2>Season Parameters</h2>';

		# Existing seasons
		echo '<dl>';
		foreach ($seasons as $season => $monitored) {
			$season_html = htmlspecialchars($season);
			$episodes = findEpisodes($series, $season);
			$count = count($episodes);
			$max = @max(array_keys($episodes));
			if (!$max) {
				$max = 0;
			}

			echo '<h3>Season ' . $season_html . '</h3>';

			if ($season) {
				echo '<input type="checkbox" data-inline="true" data-role="flipswitch" value="1"'.
					' name="season_' . $season_html . '"';
				if ($monitored !== false) {
					echo ' checked';
				}
				echo '/>';
			}

			if ($count) {
				echo '<div data-role="fieldcontain">';
				echo '<label for="episodes_' . $season_html . '">Episodes';
				if ($count == $max) {
					echo ' (' . $count . ')';
				} else {
					echo ' (' . $count . '/' . $max . ')';
				}
				echo '</label>';
				echo '<select id="episodes_' . $season_html . '">';
				foreach ($episodes as $num => $episode) {
					echo '<option>' . htmlspecialchars(sprintf('%02d', $num) . ' - ' . $episode) . '</option>';
				}
				echo '</select></label>';
				echo '</div>';
			} else {
				echo '<input type="submit" name="season_del_' . $season_html . '" value="Delete Empty Season"><br/>';
			}
		}
		echo '</dl>';

		# Save button
		echo '<p><input type="submit" name="Save" value="Save"/></p>';

		# Add a season
		echo '<h2>Add Season</h2>';
		$next_season = @max(array_keys($seasons)) + 1;
		echo '<div data-role="fieldcontain">';
		echo '<label for="season_add">';
		echo '<input pattern="[0-9]*" type="text" id="season_add" name="season_add" value="' . htmlspecialchars($next_season) . '"/>';
		echo '</label>';
		echo '<input type="submit" id="season_add" name="AddSeason" value="Add Season">';
		echo '</div>';
	}

	# End Form
	echo '</form>';
	echo '</div>';

	# TheTVDB Frame
	$url_html = htmlspecialchars(TVDBURL($flags['tvdb-id'], $flags['tvdb-lid']));
	echo '<h2>The TVDB</h2>';
	echo '<p><a target="_blank" href="' . $url_html . '">' . $url_html . '</a></p>';
	echo '<iframe height="1000" style="width: 95%; display: block; margin: 0 auto;" id="tvdb_iframe" src="' . $url_html . '">';
	echo '</iframe>';
	echo '<script type="text/javascript">';
	echo 'function tvdb_iframe_height() { $("#tvdb_iframe").attr("height", document.body.offsetHeight * 0.95); }';
	echo '$(window).ready(tvdb_iframe_height);';
	echo '$(window).resize(tvdb_iframe_height);';
	echo '</script>';
}

# Print a DL of all series and note the available and monitored seasons
function printAllSeries() {
	require 'config.php';
	global $TV_PATH;
	$all_series = allSeriesSeasons($TV_PATH);

	# Header
	echo '<div data-role="header">';
	echo '<h1>UberZach TV</h1>';
	if (authenticated()) {
		echo '<a href="' . $LOGIN_PAGE . '?logout=1" class="ui-btn-right" data-ajax="false">Logout: ' . username() . '</a>';
	} else {
		echo '<a href="' . $LOGIN_PAGE . '" class="ui-btn-right" data-ajax="false">Login</a>';
	}
	echo '</div>';

	# Wrap all the content
	echo '<div role="main" class="ui-content">';

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
			echo '<img src="tv.png" class="ui-li-icon ui-corner-none" alt="Currently Airing" />';
		}
		echo htmlspecialchars($sort);
		echo '<span class="ui-li-count">' . count($all_series[ $series ]) . '</span>';
		echo '</a></li>';
	}
	echo '</ul>';

	# End the sorted/filtered content
	echo '</div>';

	# Add a series
	echo '<form action="' . $_SERVER['PHP_SELF'] . '" method="post" data-ajax="false">';
	echo '<div data-role="footer"><p>';
	echo '<label>TheTVDB ID or URL: <input type="text" name="series_add"/></label>';
	echo '<input type="submit" value="Add Series"/>';
	echo '</p></div>';
	echo '</form>';
}

?>
