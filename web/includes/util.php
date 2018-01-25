<?

# Cleanup the provided series name
# This does NOT provide comprehensively safe output,
# it merely attempts to make names compatible with the filesystem and local conventions
function cleanSeries($series) {
	# Clearly unreasonable characters
	$series = preg_replace('/[\0\n\r]/', ' ', $series);

	# Not allowed by the SMB filesystem -- */:?
	$series = preg_replace('/\*/', '_', $series);
	$series = preg_replace('/\s*[\/\:]\s*/', ' - ', $series);
	$series = preg_replace('/\?/', "\xef\x80\xa5", $series);

	# General string cleanup
	$series = preg_replace('/\s+/', ' ', $series);
	$series = trim($series);

	# Ensure we don't go out-of-scope
	$series = basename($series);

	return $series;
}

# True if the input path is junk -- self-links, OS X noise, etc.
function isJunk($path) {
	$path = basename($path);
	
	# Ignore certain fixed paths
	foreach (array('.', '..', '.DS_Store') as $value) {
		if ($path == $value) {
			return true;
		}
	}
	
	# Ignore ._ paths
	if (preg_match('/^\.\_/', $path)) {
		return true;
	}
	
	# Otherwise the path is good
	return false;
}

function sortTitle($title) {
	$title = displayTitle($title);
	$title = preg_replace('/^The\s+/i', '', $title);
	$title = preg_replace('/^A\s+/i', '', $title);
	return $title;
}

function displayTitle($title) {
	$title = preg_replace('/\xEF\x80\xA9$/', '.', $title);
	$title = preg_replace('/\xEF\x80\xA5/', '?', $title);
	return $title;
}

function clearCache() {
	global $CACHE_FILE;
	if (file_exists($CACHE_FILE)) {
		rename($CACHE_FILE, staleCacheName($CACHE_FILE));
	}
}

function staleCacheName($file) {
	return $file . '.stale';
}

function protocolName() {
	$protocol = 'http';
	if ($_SERVER['HTTPS']) {
		$protocol = 'https';
	}
	return $protocol;
}

function adjustProtocol($url) {
	return preg_replace('/^https?\:/i', protocolName() . ':', $url);
}

?>
