<?

require 'config.php';

# Cleanup the provided series name
# This does NOT provide comprehensively safe output,
# it merely attempts to make names compatible with the filesystem and local convetions
function cleanSeries($series) {
	# Clearly unreasonable characters
	$series = preg_replace('/[\0\n\r]/', ' ', $series);

	# Not allowed on our filesystem
	$series = preg_replace('/\s+[\/\:]\s+/', ' - ', $series);

	# General string cleanup
	$series = preg_replace('/\s+/', ' ', $series);

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

function sortTitle($name) {
	$name = preg_replace('/^The\s+/i', '', $name);
	$name = preg_replace('/^A\s+/i', '', $name);
	return $name;
}

?>
