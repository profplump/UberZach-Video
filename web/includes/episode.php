<?

require 'config.php';

# Find all the episodes in a provided season folder
function findEpisodes($series, $season) {
	$retval = array();

	$season_path = seasonPath($series, $season);
	$dir = @opendir($season_path);
	if ($dir === FALSE) {
		echo 'Unable to opendir(): ' . htmlspecialchars($season_path) . "\n";
		return false;
	}
	while (false !== ($episode = readdir($dir))) {

		# Skip junk
		if (isJunk($episode)) {
			continue;
		}

		# Record the episode number
		if (preg_match('/^(20\d\d)\-(\d\d)\-(\d\d)\s*\-\s*(\S.*\.\w{2,4})$/i', $episode, $matches)) {
			$episode_num = intval($matches[1] . $matches[2] . $matches[3]);
			$retval[ $episode_num ] = $matches[4];
		} elseif (preg_match('/^(?:S\d+E)?(\d+)\s*\-\s*(\S.*\.\w{2,4})$/i', $episode, $matches)) {
			$episode_num = intval($matches[1]);
			$retval[ $episode_num ] = $matches[2];
		}
	}
	closedir($dir);

	# Sort numerically; the directory listing typically returns a lexicographic order
	ksort($retval, SORT_NUMERIC);

	return $retval;
}

?>
