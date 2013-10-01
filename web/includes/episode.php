<?

require 'config.php';

# Find all the episodes in a provided season folder
function findEpisodes($season_path) {
	$retval = array();

	$dir = opendir($season_path);
	if ($dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($season_path) . "\n");
	}
	while (false !== ($episode = readdir($dir))) {

		# Skip junk
		if (isJunk($episode)) {
			continue;
		}

		# We only care about files
		$episode_path = $path . '/' . $episode;
		if (!is_file($episode_path)) {
			continue;
		}

		# Record the episode number
		if (preg_match('/^(?:S\d+E)?(\d+)\s*\-\s*\.\w\w\w$/i', $season, $matches)) {
			$episode_num = intval($matches[1]);
			$retval[ $episode_num ] = true;
		}
	}
	closedir($dir);

	# Sort numerically; the directory listing typically returns a lexicographic order
	ksort($retval, SORT_NUMERIC);

	return $retval;
}

?>
