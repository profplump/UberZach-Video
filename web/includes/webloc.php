<?

require 'config.php';

function writeWebloc($url, $path) {
	$encoded_url = htmlspecialchars($url, ENT_XML1, 'UTF-8');

	$str = '<?xml version="1.0" encoding="UTF-8"?>';
	$str .= '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">';
	$str .= '<plist version="1.0">';
	$str .= '<dict>';
	$str .= '<key>URL</key>';
	$str .= '<string>' . $encoded_url . '</string>';
	$str .= '</dict>';
	$str .= '</plist>';

	file_put_contents($path, $str);
}

# Find the *.webloc file, if in, in the provided folder
function findWebloc($path) {
	$retval = false;

	$dir = opendir($path);
	if ($dir === FALSE) {
		die('Unable to opendir(): ' . htmlspecialchars($path) . "\n");
	}
	while (false !== ($name = readdir($dir))) {

		# Skip junk
		if (isJunk($name)) {
			continue;
		}

		# We only care about *.webloc files
		if (!preg_match('/\.webloc$/', $name)) {
			continue;
		}

		# The file must be readable to be useful
		$file = $path . '/' . $name;
		if (is_readable($file)) {
			$retval = $file;
			last;
		}
	}
	closedir($dir);

	return $retval;
}

# Read and parse the provided *.webloc file
function readWebloc($file) {
	global $TVDB_URL;
	$retval = array(
		'tvdb-id'  => false,
		'tvdb-lid' => false,
		'url'      => false,
	);

	# Read and parse the file
	# Accept both the resource-fork and data-fork (i.e. plist) verisons of the file
	$str = trim(file_get_contents($file));
	if (preg_match('/(?:\?|\&(?:amp;)?)id=(\d+)/', $str, $matches)) {
		$retval['tvdb-id'] = $matches[1];
	}
	if (preg_match('/(?:\?|\&(?:amp;)?)lid=(\d+)/', $str, $matches)) {
		$retval['tvdb-lid'] = $matches[1];
	}

	# Grab the URL, if available
	$retval['url'] = TVDBURL($retval['tvdb-id'], $retval['tvdb-lid']);

	return $retval;
}

?>
