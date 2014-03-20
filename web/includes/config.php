<?

### Config
$TV_PATH    = '/mnt/media/TV';	# Root path for all TV series
$MAX_AGE    = 86400 * 90;		# Consider a series "old" if it has not been updated for this many seconds
$CACHE_AGE  = 300;
$CACHE_FILE = '/var/tmp/php/tv_web.cache';

### TVDB
$ENABLE_TVDB      = true;	# Master enable/disable flag
$TVDB_DELAY       = 20;		# Minimum delay between TVDB downloads
$TVDB_DELAY_COUNT = 3;		# Number of TVDB requests allowed without throttling
$TVDB_TIMEOUT     = 15;		# Maximum load time for TVDB pages
$TVDB_LANG_ID     = 7;		# Default language ID for TVDB URLs
$TVDB_URL         = 'http://thetvdb.com/?tab=series';

### App Config
$EXISTS_FILES  = array('no_quality_checks', 'more_number_formats', 'skip');
$CONTENT_FILES = array('must_match', 'search_name', 'excludes');

### Login Config
$LOGIN_PAGE  = 'login';
$MAIN_PAGE = '/tv/';

### PAM Config
$PAM_SERVICE = 'tv_web';

### MyPlex Config
$PLEX_PRODUCT = 'UberZach TV';
$PLEX_VERSION = '0.1';
$PLEX_ID      = 'UberZach-TV-v' . $PLEX_VERSION;

# Import the secret (i.e. non-repo) config
require_once('secrets.php');

?>
