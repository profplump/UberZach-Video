<?

require 'config.php';

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
	$url = TVDBURL($id, $lid);
	$ctx = stream_context_create(array(
		'http' => array( 'timeout' => 15 )
	)); 
	return @file_get_contents($url, 0, $ctx);
}

# Plain-text title of a TVDB entity (or FALSE on failure)
function getTVDBTitle($id, $lid) {
	$retval = false;

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
