<?

require 'config.php';
$LAST_TVDB_DOWNLOAD = 0;

# Parse and input URL for TVDB ID and LID
function parseTVDBURL($url) {
	$retval = array(
		'tvdb-id'  => false,
		'tvdb-lid' => false,
	);

        # Accept both the raw and encoded verisons of the URL
	if (preg_match('/(?:\?|\&(?:amp;)?)(?:series)?id=(\d+)/', $url, $matches)) {
		$retval['tvdb-id'] = $matches[1];
	}
	if (preg_match('/(?:\?|\&(?:amp;)?)lid=(\d+)/', $url, $matches)) {
		$retval['tvdb-lid'] = $matches[1];
	}

	return $retval;
}

# Build a series URL from the ID and optional LID
function TVDBURL($id, $lid) {
	global $TVDB_URL;
	$url = false;

	if (!$lid) {
		$lid = $TVDB_LANG_ID;
	}
	if ($id) {
		$url = $TVDB_URL . '&id=' . $id . '&lid=' . $lid;
	}

	return $url;
}

function getTVDBPage($id, $lid) {

	# If TVDB is not enabled return FALSE
	global $ENABLE_TVDB;
	if (!$ENABLE_TVDB) {
		return false;
	}

	# Sleep between downloads to avoid TVDB bans
	global $TVDB_DELAY;
	global $LAST_TVDB_DOWNLOAD;
	if (time() - $LAST_TVDB_DOWNLOAD < $TVDB_DELAY) {
		sleep(rand($TVDB_DELAY, 2 * $TVDB_DELAY));
	}
	$LAST_TVDB_DOWNLOAD = time();

	# Download with a timeout
	global $TVDB_TIMEOUT;
	$url = TVDBURL($id, $lid);
	$ctx = stream_context_create(array(
		'http' => array( 'timeout' => $TVDB_TIMEOUT )
	)); 
	return @file_get_contents($url, 0, $ctx);
}

# Plain-text title of a TVDB entity (or FALSE on failure)
function getTVDBTitle($id, $lid) {
	$retval = false;

	# If TVDB is not enabled return FALSE
	global $ENABLE_TVDB;
	if (!$ENABLE_TVDB) {
		return false;
	}

	$page = getTVDBPage($id, $lid);
	if ($page) {
		if (preg_match('/\<h1\>([^\>]+)\<\/h1\>/i', $page, $matches)) {
			$retval = $matches[1];
		}
	}

	return $retval;
}

# Get the seasons of a TVDB entity
function getTVDBSeasons($id, $lid) {
	$retval = false;

	# If TVDB is not enabled return a fake season list
	global $ENABLE_TVDB;
	if (!$ENABLE_TVDB) {
		return array(1 => true);
	}

	# Download and parse the series page for a list of seasons
	$page = getTVDBPage($id, $lid);
	if ($page) {
		if (preg_match_all('/class=\"seasonlink\"[^\>]*\>([^\<]+)\<\/a\>/i', $page, $matches)) {
			$retval = array();
			foreach ($matches[1] as $val) {
				if (preg_match('/^\d+$/', $val)) {
					$retval[ $val ] = true;
				} else if ($val == 'Specials') {
					$retval[0] = true;
				}
			}
		}
	}

	return $retval;
}

?>
