#!/usr/bin/perl
use strict;
use warnings;

# Includes
use Date::Parse;
use URI::Encode qw(uri_encode);
use HTML::Entities;
use HTML::Strip;
use JSON;
use Sys::Syslog qw(:standard :macros);
use Capture::Tiny ':all';
use File::Temp;
use File::Spec;
use File::Basename;
use FindBin qw($Bin);
use lib $Bin;
use Fetch;

# Prototypes
sub confDefault($;$);
sub readExcludes($);
sub parseNZB($);
sub badTor($);
sub seedCleanup($);
sub lowQualityTor($);
sub getHash($);
sub resolveSecondary($);
sub resolveTrackers($);
sub splitTags($$$$);
sub findSE($);
sub initSources();
sub findProxy($$);
sub fetch($;$$);
sub phantomFetch($$);

# Globals
my %CONFIG  = ();
my $SOURCES = undef();
my $COOKIES = undef();
my $FETCH   = undef();
my $SCRIPT  = undef();

# Command line
my ($dir, $search) = @ARGV;
if (!defined($dir)) {
	die('Usage: ' . basename($0) . " input_directory [search_string]\n");
}

# Pre-config environment
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	if ($ENV{'DEBUG'} =~ /(\d+)/) {
		$DEBUG = $1;
	} else {
		$DEBUG = 1;
	}
}
my $CONF_FILE = $ENV{'HOME'} . '/.findTorrent.config';
if (defined($ENV{'CONF_FILE'})) {
	$CONF_FILE = $ENV{'CONF_FILE'};
}

# Read the config file
if ($CONF_FILE && -r $CONF_FILE) {
	my $fh;
	open($fh, '<', $CONF_FILE)
	  or die('Unable to open config file: ' . $CONF_FILE . ': ' . $! . "\n");
	while (<$fh>) {

		# Skip blank lines and comments
		if (/^\s*#/ || /^\s*$/) {
			next;
		}

		# Assume everything else is key = val pairs
		if (my ($key, $val) = $_ =~ /^\s*(\S[^\=]+)\=\>?\s*(\S.*)$/) {
			$key =~ s/^\s+//;
			$key =~ s/\s+$//;
			$val =~ s/^\s+//;
			$val =~ s/\s+$//;
			$CONFIG{$key} = $val;
			if ($DEBUG > 1) {
				print STDERR 'Adding config: ' . $key . ' => ' . $val . "\n";
			}
		} else {
			warn('Ignoring config line: ' . $_ . "\n");
		}
	}
	close($fh);
}

# Config defaults
confDefault('EXCLUDES_FILE', $ENV{'HOME'} . '/.findTorrent.exclude');
confDefault('TV_DIR',        `~/bin/video/mediaPath` . '/TV');
confDefault('PHANTOM_BIN',   '/usr/local/bin/phantomjs');
confDefault('UA',
	'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/538.39.41 (KHTML, like Gecko) Version/8.0 Safari/538.39.41');
confDefault('PROTOCOL',            'https');
confDefault('SLEEP',               1);
confDefault('DELAY',               5);
confDefault('TIMEOUT',             15);
confDefault('ERR_DELAY',           $CONFIG{'TIMEOUT'} * 2);
confDefault('ERR_RETRIES',         3);
confDefault('MORE_NUMBER_FORMATS', 0);
confDefault('NO_QUALITY_CHECKS',   0);
confDefault('NEXT_EPISODES',       3);
confDefault('MIN_DAYS_BACK',       0);
confDefault('MAX_DAYS_BACK',       3);
confDefault('SYSLOG',              1);
confDefault('MIN_COUNT',           10);
confDefault('MIN_SIZE',            100);
confDefault('SIZE_BONUS',          5);
confDefault('SIZE_PENALTY',        $CONFIG{'SIZE_BONUS'});
confDefault('TITLE_PENALTY',       $CONFIG{'SIZE_BONUS'} / 2);
confDefault('MAX_SEEDS',           500);
confDefault('MAX_SEED_RATIO',      0.25);
confDefault('SEED_RATIO_COUNT',    $CONFIG{'MIN_COUNT'});
confDefault('TRACKER_LOOKUP',      1);
confDefault(
	'PHANTOM_CONFIG', "var system = require('system');
var page = require('webpage').create();
var resources = [];

page.open(system.args[1], function(status)
{
    console.log(resources[0].status);
    console.log(page.content);
    phantom.exit();
});

// Add responses for completed text/html resources
page.onResourceReceived = function(response) {
    if (response.stage !== 'end') return;
    if (response.headers.filter(function(header) {
        if (header.name == 'Content-Type' && header.value.indexOf('text/html') == 0) {
            return true;
        }
        return false;
    }).length > 0)
        resources.push(response);
};"
);

# Re-parse a few config items
if (exists($CONFIG{'TRACKERS'})) {
	my @trackers = ();
	foreach my $tracker (split(/\s*,\s*/, $CONFIG{'TRACKERS'})) {
		$tracker =~ s/^\s+//;
		$tracker =~ s/\s+$//;
		push(@trackers, $tracker);
	}
	$CONFIG{'TRACKERS'} = \@trackers;
}
if (exists($CONFIG{'SOURCES'})) {
	my %sources = ();
	foreach my $source (split(/\s*,\s*/, $CONFIG{'SOURCES'})) {
		$source =~ s/^\s+//;
		$source =~ s/\s+$//;
		$source = uc($source);
		$sources{$source} = 1;
	}
	$CONFIG{'SOURCES'} = \%sources;
}

# Sanity checks
if (ref($CONFIG{'SOURCES'}) ne 'HASH' || !exists($CONFIG{'SOURCES'}) || scalar(keys(%{ $CONFIG{'SOURCES'} })) < 1) {
	die("No sources configured\n");
}
if (ref($CONFIG{'TRACKERS'}) ne 'ARRAY' || !exists($CONFIG{'TRACKERS'}) || scalar(@{ $CONFIG{'TRACKERS'} }) < 1) {
	warn("No trackers configured\n");
}
if (!exists($CONFIG{'NZB_AGE_GOOD'}) || !exists($CONFIG{'NZB_AGE_MAX'})) {
	warn("No NZB good/max age provided\n");
}

# Open the log if enabled
if ($CONFIG{'SYSLOG'}) {
	openlog(basename($0), '', LOG_DAEMON);
}

# Read the torrent excludes list
$CONFIG{'EXCLUDES'} = readExcludes($CONFIG{'EXCLUDES_FILE'});

# Figure out what we're searching for
my $show          = '';
my @urls          = ();
my $CUSTOM_SEARCH = 0;
my $season        = 0;
my @need          = ();
my %need          = ();

# Clean up the input "directory" path
{

	# Allow use of the raw series name
	if (!($dir =~ /\//)) {
		$show = $dir;
		$dir  = $CONFIG{'TV_DIR'} . '/' . $dir;
	}

	# Allow use of relative paths
	$dir = File::Spec->rel2abs($dir);

	# Sanity check
	if (!-d $dir) {
		die('Invalid input directory: ' . $dir . "\n");
	}

	# Isolate the season from the path, if provided
	$dir =~ /\/Season\s+(\d+)\/?$/i;
	if ($1) {
		$season = $1;
		$dir    = dirname($dir);
	}

	# If no season is provided find the latest
	if (!$season) {
		opendir(SERIES, $dir)
		  or die("Unable to open series directory: ${!}\n");
		while (my $file = readdir(SERIES)) {
			if ($file =~ /^Season\s+(\d+)$/i) {
				if (!$season || $season < $1) {
					$season = $1;
				}
			}
		}
		closedir(SERIES);
	}

	# Isolate and clean the series name
	if (!$show) {
		$show = basename($dir);
	}
	$show =~ s/[\'\"\.]//g;

	if ($DEBUG) {
		print STDERR 'Checking directory: ' . $dir . "\n";
	}
	if ($CONFIG{'SYSLOG'}) {
		syslog(LOG_NOTICE, $show);
	}
}

# Allow the show name to be overriden
{
	my $search_name = $dir . '/search_name';
	if (-e $search_name) {
		local ($/, *FH);
		open(FH, $search_name)
		  or die('Unable to read search_name for show: ' . $show . ': ' . $! . "\n");
		my $text = <FH>;
		close(FH);
		if ($text =~ /^\s*(\S.*\S)\s*$/) {
			$show = $1;
		} else {
			print STDERR 'Skipping invalid search_name for show: ' . $show . ': ' . $text . "\n";
		}
	}
	if ($DEBUG) {
		print STDERR 'Searching with series title: ' . $show . "\n";
	}
}

# Allow quality checks to be disabled
if (-e $dir . '/no_quality_checks') {
	$CONFIG{'NO_QUALITY_CHECKS'} = 1;
	if ($DEBUG) {
		print STDERR 'Searching with no quality checks: ' . $show . "\n";
	}
}

# Allow use of more number formats
if (-e $dir . '/more_number_formats') {
	$CONFIG{'MORE_NUMBER_FORMATS'} = 1;
	if ($DEBUG) {
		print STDERR 'Searching with more number formats: ' . $show . "\n";
	}
}

# Read the search excludes file, if any
my $exclude        = '';
my %TITLE_EXCLUDES = ();
if (-e $dir . '/excludes') {
	local $/ = undef;
	open(EX, $dir . '/excludes')
	  or die("Unable to open series excludes file: ${!}\n");
	my $ex = <EX>;
	close(EX);

	$ex =~ s/^\s+//;
	$ex =~ s/\s+$//;
	my @excludes = split(/\s*,\s*/, $ex);
	foreach my $ex (@excludes) {
		$TITLE_EXCLUDES{$ex} = 1;

		if (length($exclude)) {
			$exclude .= ' ';
		}
		$exclude .= '-"' . $ex . '"';
	}

	$exclude = uri_encode(' ' . $exclude);
}

# Setup our sources
$SOURCES = initSources();
$CONFIG{'DELAY'} /= scalar(keys(%{$SOURCES})) / 2;

# Handle custom searches
if ((scalar(@urls) < 1) && defined($search) && length($search) > 0) {

	# Note the custom search string
	$CUSTOM_SEARCH = 1;
	if ($DEBUG) {
		print STDERR "Custom search\n";
	}

	# Create the relevent search strings
	foreach my $key (keys(%{$SOURCES})) {
		my $source = $SOURCES->{$key};
		push(@urls, $source->{'search_url'} . $search . $exclude . $source->{'search_suffix'});
	}
}

# Handle search-by-date series
if ((scalar(@urls) < 1) && -e $dir . '/search_by_date') {

	# Note the search-by-date status
	# Set the CUSTOM_SERACH flag to skip season/epsiode matching
	$CUSTOM_SEARCH = 1;

	# Read the find-by-date string
	my $search_by_date = '';
	local ($/, *FH);
	open(FH, $dir . '/search_by_date')
	  or die('Unable to read search_by_date for show: ' . $show . ': ' . $! . "\n");
	my $text = <FH>;
	close(FH);
	if ($text =~ /^\s*(\S.*\S)\s*$/) {
		$search_by_date = $1;
	} else {
		die('Skipping invalid search_by_date for show: ' . $show . ': ' . $text . "\n");
	}

	# Create search strings for each date in the range, unless the related file already exists
	my (%years, %months, %days) = ();
	for (my $days_back = $CONFIG{'MIN_DAYS_BACK'} ; $days_back <= $CONFIG{'MAX_DAYS_BACK'} ; $days_back++) {

		# Calculate the date
		my (undef(), undef(), undef(), $day, $month, $year) = localtime(time() - (86400 * $days_back));

		# Format as strings
		$year  = sprintf('%04d', $year + 1900);
		$month = sprintf('%02d', $month + 1);
		$day   = sprintf('%02d', $day);

		# Check for an existing file
		my $exists = 0;
		{
			my $season_dir = $dir . '/Season ' . $year;
			my $prefix     = qr/${year}\-${month}\-${day}\s*\-\s*/;
			opendir(SEASON, $season_dir)
			  or die('Unable to open season directory (' . $season_dir . '): ' . $! . "\n");
			while (my $file = readdir(SEASON)) {
				if ($file =~ $prefix) {
					$exists = 1;
					last;
				}
			}
			closedir(SEASON);
		}
		if ($exists) {
			next;
		}

		# Save all the date string components
		$years{$year}   = 1;
		$months{$month} = 1;
		$days{$day}     = 1;

		# Create the relevent search strings
		my $search_str = $search_by_date;
		$search_str =~ s/%Y/${year}/g;
		$search_str =~ s/%m/${month}/g;
		$search_str =~ s/%d/${day}/g;
		foreach my $key (keys(%{$SOURCES})) {
			my $source = $SOURCES->{$key};
			push(@urls, $source->{'search_url'} . $search_str . $exclude . $source->{'search_suffix'});
		}
	}

	# Build a date string matching regex
	my $str = '\b(?:' . join('|', keys(%years)) . ')\b';
	$str .= '.*';
	$str .= '\b(?:' . join('|', keys(%months)) . ')\b';
	$str .= '.*';
	$str .= '\b(?:' . join('|', keys(%days)) . ')\b';
	$CUSTOM_SEARCH = qr/${str}/;

	# Debug
	if ($DEBUG) {
		print STDERR 'Searching with date template: ' . $str . "\n";
	}
}

# Handle standard series
if (scalar(@urls) < 1) {

	# Validate the season number
	if (!defined($season) || $season < 1 || $season > 2000) {
		die('Invalid season number: ' . $show . ' => ' . $season . "\n");
	}

	# Get the last episode number
	my $no_next  = 0;
	my %episodes = ();
	my $highest  = 0;
	opendir(SEASON, $dir . '/Season ' . $season)
	  or die("Unable to open season directory: ${!}\n");
	while (my $file = readdir(SEASON)) {

		# Skip support files
		if ($file =~ /\.(?:png|xml|jpg|gif|tbn|txt|nfo|torrent)\s*$/i) {
			next;
		}

		# Check for a season_done file
		if ($file eq 'season_done') {
			$no_next = 1;
			next;
		}

		# Extract the episode number
		my ($num) = $file =~ /^\s*\.?(\d+)\s*\-\s*/i;
		if (defined($num)) {
			$num = int($num);
			if ($DEBUG) {
				print STDERR 'Found episode number: ' . $num . ' in file: ' . $file . "\n";
			}

			# Record it
			$episodes{$num} = 1;

			# Track the highest episode number
			if ($num > $highest) {
				$highest = $num;
			}
		}
	}
	close(SEASON);

	# Assume we need the next 2 episodes, unless no_next is set (i.e. season_done)
	if (!$no_next) {
		for (my $i = 1 ; $i <= $CONFIG{'NEXT_EPISODES'} ; $i++) {
			push(@need, $highest + $i);
		}
	}

	# Find any missing episodes
	for (my $i = 1 ; $i <= $highest ; $i++) {
		if (!$episodes{$i}) {
			push(@need, $i);
		}
	}
	if ($DEBUG) {
		print STDERR 'Needed episodes: ' . join(', ', @need) . "\n";
	}

	# Reverse the array for later matching
	foreach my $episode (@need) {
		$need{$episode} = 1;
	}

	# Construct a URL-friendly show name
	my $safeShow = $show;
	$safeShow =~ s/\s+\&\s+/ and /i;
	$safeShow =~ s/^\s*The\b//i;
	$safeShow =~ s/\s+\-\s+/ /g;
	$safeShow =~ s/[\'\:]//g;
	$safeShow =~ s/[^\w\"\-]+/ /g;
	$safeShow =~ s/^\s+//;
	$safeShow =~ s/\s+$//;
	$safeShow =~ s/\s\s+/ /g;
	$safeShow =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	$safeShow =~ s/\%20/\+/g;

	# Calculate possible name variations
	my @urlShowVarients = ();
	{

		# Default name
		push(@urlShowVarients, $safeShow);

		# Search for both "and" and "&"
		if ($safeShow =~ /\+and\+/i) {
			my $tmp = $safeShow;
			$tmp =~ s/\+and\+/\+%26\+/;
			push(@urlShowVarients, $tmp);
		}
	}

	# Construct the URL for each title varient of each needed episode
	foreach my $urlShow (@urlShowVarients) {
		foreach my $episode (@need) {
			my $episode_long = sprintf('%02d', $episode);
			my $season_long  = sprintf('%02d', $season);
			foreach my $source (values(%{$SOURCES})) {

				# Allow custom handling
				if (defined($source->{'custom_search'}) && ref($source->{'custom_search'}) eq 'CODE') {
					$source->{'custom_search'}->(\@urls, $urlShow, $season, $episode);
					next;
				}

				# Use quotes around the show name if the source needs them
				my $quote = '%22';
				if (!$source->{'quote'}) {
					$quote = '';
				}

				# Calculate the compete search prefix and suffix to simplify later concatenations
				my $prefix = $source->{'search_url'} . $quote . $urlShow . $quote;
				my $suffix = '';
				if ($source->{'search_exclude'}) {
					$suffix .= $exclude;
				}
				if ($source->{'search_suffix'}) {
					$suffix .= $source->{'search_suffix'};
				}

				# SXXEYY
				my $url = $prefix . '+s' . $season_long . 'e' . $episode_long . $suffix;
				push(@urls, $url);

				# Extra searches for shows that have lazy/non-standard number formats
				if ($CONFIG{'MORE_NUMBER_FORMATS'}) {

					# SXEY
					if ($season_long ne $season || $episode_long ne $episode) {
						$url = $prefix . '+s' . $season . 'e' . $episode . $suffix;
						push(@urls, $url);
					}

					# SXX EYY
					$url = $prefix . '+s' . $season_long . '+e' . $episode_long . $suffix;
					push(@urls, $url);

					# Season XX Episode YY
					$url = $prefix . '+season+' . $season_long . '+episode+' . $episode_long . $suffix;
					push(@urls, $url);

					# Series X Episode Y
					$url = $prefix . '+series+' . $season . '+episode+' . $episode . $suffix;
					push(@urls, $url);

					# SxEE
					$url = $prefix . '+' . $season . 'x' . $episode_long . $suffix;
					push(@urls, $url);

					# Season X
					if ($CONFIG{'NO_QUALITY_CHECKS'}) {
						$url = $prefix . '+Season+' . $season . $suffix;
						push(@urls, $url);
					}
				}
			}
		}
	}
}

my @html_content = ();
my @json_content = ();
foreach my $url (@urls) {

	# Fetch the page
	my $errCount = 0;
	my $content  = '';
  HTTP_ERR_LOOP: {
		my $code = 0;
		if ($DEBUG) {
			print STDERR 'Searching with URL: ' . $url . "\n";
		}

		# Fetch
		($content, $code) = fetch($url, 'primary.html');

		# Check for useful errors
		if ($code == 404) {
			if ($DEBUG) {
				print STDERR "Skipping content from 404 response\n";
			}
			next;
		}

		# Check for less useful errors
		if ($code != 200) {
			if ($code >= 500 && $code <= 599) {
				if ($errCount > $CONFIG{'ERR_RETRIES'}) {
					print STDERR 'Unable to fetch URL: ' . $url . "\n";
					$errCount = 0;
					next;
				}
				if ($DEBUG) {
					print STDERR 'Retrying URL (' . $code . '): ' . $url . "\n";
				}
				$errCount++;
				sleep($CONFIG{'ERR_DELAY'});
				redo HTTP_ERR_LOOP;
			} else {
				print STDERR 'Error fetching URL (' . $code . '): ' . $url . "\n";
			}
			next;
		}
	}

	# Save the content, discriminating by data type
	if ($DEBUG > 1) {
		print STDERR 'Fetched ' . length($content) . " bytes\n";
	}
	if ($content =~ /^\s*[\{\[]/) {
		my $json = eval { decode_json($content); };
		if (defined($json) && ref($json)) {
			push(@json_content, $json);
		} elsif ($DEBUG) {
			print STDERR 'JSON parsing failure on: ' . $content . "\n";
		}
	} else {
		push(@html_content, scalar($content));
	}
}

# We need someplace to store parsed torrent data from the various sources
my @tors = ();

# Handle HTML content
foreach my $content (@html_content) {
	if ($content =~ /\<title\>The Pirate Bay/i) {

		# Find TR elements from TPB
		my @trs = splitTags($content, 'TR', 'TH', undef());
		foreach my $tr (@trs) {

			# Find the show title
			my ($title) = $tr =~ /title\=\"Details\s+for\s+([^\"]*)\"/i;
			if (!defined($title) || length($title) < 1) {
				if ($DEBUG) {
					print STDERR "Unable to find show title in TR\n\t" . $tr . "\n";
				}
				next;
			}
			$title =~ s/^\s+//;

			# Extract the season and episode numbers
			my ($fileSeason, $episode) = findSE($title);

			# Extract the URL
			my ($url) = $tr =~ /\<a\s+href\=\"(magnet\:\?[^\"]+)\"/i;
			if (!defined($url) || length($url) < 1) {
				if ($DEBUG) {
					print STDERR "Skipping TR with no magnet URL\n";
				}
				next;
			}
			$url = decode_entities($url);

			# Count the sum of seeders and leachers
			my $seeds   = 0;
			my $leaches = 0;
			if ($tr =~ /\<td(?:\s+[^\>]*)?\>(\d+)\<\/td\>\s*\<td(?:\s+[^\>]*)?\>(\d+)\<\/td\>\s*$/i) {
				$seeds   = $1;
				$leaches = $2;
			}

			# Extract the size (from separate column or inline)
			my $size = 0;
			my $unit = 'M';
			if ($tr =~ m/Size (\d+(?:\.\d+)?)\&nbsp\;(G|M)iB/) {
				$size = $1;
				$unit = $2;
			} elsif ($tr =~ m/(\d+(?:\.\d+)?)\&nbsp\;(G|M)iB\<\/[tT][dD]\>/) {
				$size = $1;
				$unit = $2;
			}
			if ($unit eq 'G') {
				$size *= 1024;
			}
			$size = int($size);

			if ($DEBUG) {
				print STDERR 'Found file (' . $title . '): ' . $url . "\n";
			}

			# Save the extracted data
			my %tor = (
				'title'   => $title,
				'season'  => $fileSeason,
				'episode' => $episode,
				'seeds'   => $seeds,
				'leaches' => $leaches,
				'size'    => $size,
				'url'     => $url,
				'source'  => 'TPB'
			);
			push(@tors, \%tor);
		}

	} elsif ($content =~ /\<title\>[^\<\>]*\bisoHunt\b[^\<\>]*\<\/title\>/i) {

		# Find each TR element from ISOHunt
		my @trs = splitTags($content, 'TR', 'TH', undef());
		foreach my $tr (@trs) {

			# Split each TD element from the row
			my @tds = split(/\<td(?:\s+[^\>]*)?\>/i, $tr);
			if (scalar(@tds) > 10 || scalar(@tds) < 9) {
				if ($tds[1] =~ /No results found/) {
					next;
				}
				print STDERR 'Skipping invalid ISO TR: ' . $tr . "\n";
				for (my $i = 0 ; $i < scalar(@tds) ; $i++) {
					print STDERR 'TD' . $i . ': ' . $tds[$i] . "\n";
				}
				next;
			}

			# Skip sponsored results
			if ($tds[1] =~ /\bSponsored\b/i) {
				if ($DEBUG > 1) {
					print STDERR "Skipping sponsored result\n";
				}
				next;
			}

			# Find the torrent ID and show title
			my ($id, $title) = $tds[2] =~ /\<a(?:\s+[^\>]*)?href=\"\/torrent_details\/(\d+\/[^\"]+)\"\>\<span\>([^\>]+)\<\/span\>/i;
			if (!defined($id) || length($id) < 1 || !defined($title) || length($title) < 1) {
				if ($DEBUG > 1) {
					print STDERR "Unable to find show ID or title in TD:\n\t" . $tds[2] . "\n";
				}
				next;
			}
			$title =~ s/^\s+//;

			# Extract the season and episode numbers
			my ($fileSeason, $episode) = findSE($title);

			# Extract the size
			my $size = 0;
			my $unit = 'M';
			if ($tds[6] =~ m/(\d+(?:\.\d+)?) (G|M)B<\/td\>/i) {
				$size = $1;
				$unit = $2;
			}
			if ($unit eq 'G') {
				$size *= 1024;
			}
			$size = int($size);

			# Count the sum of seeders and leachers
			my $seeds = 0;
			if ($tds[7] =~ /(\d+)\<\/td\>/i) {
				$seeds = $1;
			}
			my $leaches = 0;
			if ($tds[8] =~ /(\d+)\<\/td\>/i) {
				$leaches = $1;
			}

			# Build the detail page URL
			my $url = $SOURCES->{'ISO'}->{'protocol'} . '://' . $SOURCES->{'ISO'}->{'host'} . '/torrent_details/' . $id;

			if ($DEBUG) {
				print STDERR 'Found file (' . $title . '): ' . $url . "\n";
			}

			# Save the extracted data
			my %tor = (
				'title'   => $title,
				'season'  => $fileSeason,
				'episode' => $episode,
				'seeds'   => $seeds,
				'leaches' => $leaches,
				'size'    => $size,
				'url'     => $url,
				'source'  => 'ISO'
			);
			push(@tors, \%tor);
		}

	} elsif ($content =~ /Kickass\s*Torrents\<\/title\>/i) {

		# Find each TR element from Kickass
		my @trs = splitTags($content, 'TR', 'TH', undef());
		foreach my $tr (@trs) {

			# Split each TD element from the row
			my @tds = split(/\<td(?:\s+[^\>]*)?\>/i, $tr);
			if (scalar(@tds) != 6) {
				print STDERR "Invalid KICK TR:\n";
				for (my $i = 0 ; $i < scalar(@tds) ; $i++) {
					print STDERR 'TD' . $i . ': ' . $tds[$i] . "\n";
				}
				next;
			}

			# Skip empty results
			if (   $tds[1] =~ /\<h2\>Nothing found\!\<\/h2\>/i
				|| $tds[1] =~ /\<p\>\<strong\>Page not found\<\/strong\>\<\/p\>/i)
			{
				if ($DEBUG) {
					print STDERR "Skipping empty TD\n";
				}
				next;
			}

			# Find the torrent title
			my ($title) = $tds[1] =~ /\<a(?:\s+[^\>]*)?href\=\"[^\"]+\?title\=\[[^\]\"]+\]([^\"]+)\"/i;
			if (!defined($title) || length($title) < 1) {
				if ($DEBUG) {
					print STDERR "Unable to find torrent title in TD:\n\t" . $tds[1] . "\n";
				}
				next;
			}
			$title =~ s/^\s+//;

			# Find the torrent URL
			my ($url) = $tds[1] =~ /\<a(?:\s+[^\>]*)?href=\"(magnet:[^\"]+)\"/i;
			if (!defined($url) || length($url) < 1) {
				if ($DEBUG) {
					print STDERR "Unable to find torrent URL in TD:\n\t" . $tds[1] . "\n";
				}
				next;
			}
			$url = decode_entities($url);

			# Extract the season and episode numbers
			my ($fileSeason, $episode) = findSE($title);

			# Extract the size
			my $size = 0;
			my $unit = 'M';
			if ($tds[2] =~ m/(\d+(?:\.\d+)?)\s+\<span\>(G|M)B\<\/span\>\<\/td\>/i) {
				$size = $1;
				$unit = $2;
			}
			if ($unit eq 'G') {
				$size *= 1024;
			}
			$size = int($size);

			# Count the sum of seeders and leachers
			my $seeds = 0;
			if ($tds[4] =~ /(\d+)\<\/td\>/i) {
				$seeds = $1;
			}
			my $leaches = 0;
			if ($tds[5] =~ /(\d+)\<\/td\>/i) {
				$leaches = $1;
			}

			if ($DEBUG) {
				print STDERR 'Found file (' . $title . '): ' . $url . "\n";
			}

			# Save the extracted data
			my %tor = (
				'title'   => $title,
				'season'  => $fileSeason,
				'episode' => $episode,
				'seeds'   => $seeds,
				'leaches' => $leaches,
				'size'    => $size,
				'url'     => $url,
				'source'  => 'KICK'
			);
			push(@tors, \%tor);
		}

	} elsif ($content =~ /\<a(?:\s+[^\>]*)?\>Torrentz\<\/a\>/i) {

		# We'll need to strip HTML
		my $hs = HTML::Strip->new();

		# Find each DL element from Torrentz
		my @dls = splitTags($content, 'DL', undef(), undef());
		foreach my $dl (@dls) {

			# Skip ads
			if ($dl =~ /\s+rel\=\"nofollow/i) {
				next;
			}

			# Find the torrent title
			my ($hash, $title) = $dl =~ /\<a href\=\"\/(\w+)\">(.*)\<\/a\>/i;
			if (!defined($hash) || length($hash) < 1 || !defined($title) || length($title) < 1) {
				if ($DEBUG) {
					print STDERR "Unable to find torrent title in DL:\n\t" . $dl . "\n";
				}
				next;
			}
			$hash  = lc($hash);
			$title = $hs->parse($title);
			$hs->eof;
			$title =~ s/^\s+//;

			# Extract the season and episode numbers
			my ($fileSeason, $episode) = findSE($title);

			# Extract the size
			my $size = 0;
			if ($dl =~ /\<span class\=\"s\">(\d+(?:\.\d+)?) (G|M)B\<\/span\>/i) {
				$size = $1;
				if ($2 eq 'G') {
					$size *= 1024;
				}
				$size = int($size);
			}

			# Count the sum of seeders and leachers
			my $seeds = 0;
			if ($dl =~ /<span class\=\"u\">(\d+)\<\/span\>/i) {
				$seeds = $1;
			}
			my $leaches = 0;
			if ($dl =~ /<span class\=\"d\">(\d+)\<\/span\>/i) {
				$leaches = $1;
			}

			# Construct a magnet URL from the hash
			# Assume the seconary lookup will append a list of trackers
			my $url = 'magnet:?xt=urn:btih:' . $hash . '&dn=' . uri_encode($title, { 'encode_reserved' => 1 });

			if ($DEBUG) {
				print STDERR 'Found file (' . $title . '): ' . $url . "\n";
			}

			# Save the extracted data
			my %tor = (
				'title'   => $title,
				'season'  => $fileSeason,
				'episode' => $episode,
				'seeds'   => $seeds,
				'leaches' => $leaches,
				'size'    => $size,
				'url'     => $url,
				'source'  => 'Z'
			);
			push(@tors, \%tor);
		}

	} elsif ($content =~ /ExtraTorrent\.cc The World\'s Largest BitTorrent System\<\/title\>/i) {

		# Find TR elements from ET
		my @trs = splitTags($content, 'TR', undef(), 'magnet\:');
		foreach my $tr (@trs) {

			# Find the show title
			my ($title) = $tr =~ /title\=\"Download\s+([^\"]*)\s+torrent\"/i;
			if (!defined($title) || length($title) < 1) {
				if ($DEBUG) {
					print STDERR "Unable to find show title in TR\n\t" . $tr . "\n";
				}
				next;
			}
			$title =~ s/^\s+//;

			# Find the magnet URL
			my ($url) = $tr =~ /\<a\s+href=\"(magnet\:[^\"]+)\"/i;
			if (!defined($url) || length($url) < 1) {
				if ($DEBUG) {
					print STDERR "Skipping TR with no magnet URL\n";
				}
				next;
			}
			$url = decode_entities($url);

			# Extract the season and episode numbers
			my ($fileSeason, $episode) = findSE($title);

			# Count the sum of seeders and leachers
			my $seeds   = 0;
			my $leaches = 0;
			if ($tr =~ /\<td\s+class=\"sy\">(\d+)\<\/td\>/) {
				$seeds = $1;
			}
			if ($tr =~ /\<td\s+class=\"ly\">(\d+)\<\/td\>/) {
				$leaches = $1;
			}

			# Extract the size (from separate column or inline)
			my $size = 0;
			my $unit = 'M';
			if ($tr =~ /\<td\>(\d+(?:\.\d+)?)\&nbsp\;(G|M)B\<\/td\>/) {
				$size = $1;
				$unit = $2;
			}
			if ($unit eq 'G') {
				$size *= 1024;
			}
			$size = int($size);

			if ($DEBUG) {
				print STDERR 'Found file (' . $title . '): ' . $url . "\n";
			}

			# Save the extracted data
			my %tor = (
				'title'   => $title,
				'season'  => $fileSeason,
				'episode' => $episode,
				'seeds'   => $seeds,
				'leaches' => $leaches,
				'size'    => $size,
				'url'     => $url,
				'source'  => 'ET'
			);
			push(@tors, \%tor);
		}

	} elsif ($content =~ /\<title\>Sorry/) {
		if ($DEBUG) {
			print STDERR "ISO offline\n";
		}
	} elsif ($content =~ /Database\s+maintenance/i) {
		if ($DEBUG) {
			print STDERR "TPB offline\n";
		}
	} elsif ($content =~ /^\s*$/) {
		if ($DEBUG) {
			print STDERR "Source returned no content\n";
		}
	} elsif ($content =~ /limit\s*reached/i) {
		if ($DEBUG) {
			print STDERR "Source request limit reached\n";
		}
	} elsif ($content =~ /\<title\>.*Not\s+Found\<\/title\>/i) {
		if ($DEBUG) {
			print STDERR "No results\n";
		}
	} else {
		print STDERR "Unknown HTML content:\n" . $content . "\n\n";
	}
}

# Handle JSON content
foreach my $content (@json_content) {
	if (ref($content) eq 'ARRAY' && scalar(@{$content}) == 0) {
		if ($DEBUG > 1) {
			print STDERR "Empty JSON array\n";
		}
	} elsif (exists($content->{'channel'})
		&& ref($content->{'channel'}) eq 'HASH'
		&& exists($content->{'channel'}->{'title'})
		&& $content->{'channel'}->{'title'} =~ /nzbplanet/i)
	{
		print STDERR "Index: NZBplanet\n";
	} elsif (exists($content->{'channel'})
		&& ref($content->{'channel'}) eq 'HASH'
		&& exists($content->{'channel'}->{'title'})
		&& $content->{'channel'}->{'title'} =~ /usenet\-crawler/i)
	{
		print STDERR "Index: usenet-crawler\n";
	} elsif (ref($content) eq 'ARRAY'
		&& scalar(@{$content}) > 0
		&& ref($content->[0]) eq 'HASH'
		&& exists($content->[0]->{'guid'}))
	{
		print STDERR "Index: NZB.is\n";
	} elsif (exists($content->{'title'}) && $content->{'title'} =~ /NZBCat/i) {
		my $list = $content->{'item'};
		if (!$list || ref($list) ne 'ARRAY') {
			if ($DEBUG) {
				warn("Empty/invalid NCAT list\n");
			}
			next;
		}

		foreach my $item (@{$list}) {
			my $tor = parseNZB($item);
			if ($tor) {
				$tor->{'source'} = 'NCAT';
				push(@tors, $tor);
			}
		}
	} elsif (ref($content) eq 'HASH'
		&& exists($content->{'channel'})
		&& ref($content->{'channel'}) eq 'HASH'
		&& exists($content->{'channel'}->{'title'})
		&& $content->{'channel'}->{'title'} =~ /\bNzb\s+Planet\b/i)
	{
		if (!exists($content->{'channel'}->{'item'}) || ref($content->{'channel'}->{'item'}) ne 'ARRAY') {
			if ($DEBUG) {
				print STDERR "Empty/invalid NZB Planet result\n";
			}
			next;
		}
		foreach my $item (@{ $content->{'channel'}->{'item'} }) {
			my $tor = parseNZB($item);
			if ($tor) {
				$tor->{'source'} = 'PLANET';
				push(@tors, $tor);
			}
		}
	} else {
		print STDERR "Unknown JSON content:\n" . $content . "\n\n";
	}
}

# Filter for size/count/etc.
my %tors      = ();
my $showRegex = undef();
{
	my $showClean = $show;
	$showClean =~ s/[\"\']//g;
	$showClean =~ s/[\W_]+/\[\\W_\].*/g;
	$showRegex = qr/^${showClean}[\W_]/i;
}

foreach my $tor (@tors) {

	# Extract the BTIH/GUID, if available
	getHash($tor);

	# Skip bad TORs based on name/etc.
	if (badTor($tor)) {
		next;
	}

	# Skip files that contain a word from the series exclude list
	my $exclude = undef();
	foreach my $ex (keys(%TITLE_EXCLUDES)) {
		$ex = quotemeta($ex);
		if ($tor->{'title'} =~ m/${ex}/i) {
			$exclude = $ex;
			last;
		}
	}
	if (defined($exclude)) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "' . $exclude . '": ' . $tor->{'title'} . "\n";
		}
		next;
	}

	# Enforce season and episode number matches for standard searches, or CUSTOM_SEARCH matching (if it's a regex)
	if (!$CUSTOM_SEARCH) {

		# Skip files that don't contain the right season number
		if (!defined($tor->{'season'}) || $tor->{'season'} != $season) {
			if ($DEBUG) {
				print STDERR 'Skipping file: No match for season number (' . $season . '): ' . $tor->{'title'} . "\n";
			}
			next;

			# Skip files that don't contain a needed episode number, unless there is no episode number and NO_QUALITY_CHECKS is set
		} elsif ((defined($tor->{'episode'}) && !$need{ $tor->{'episode'} })
			|| (!defined($tor->{'episode'}) && !$CONFIG{'NO_QUALITY_CHECKS'}))
		{
			if ($DEBUG) {
				print STDERR 'Skipping file: No match for episode number (' . $tor->{'episode'} . '): ' . $tor->{'title'} . "\n";
			}
			next;
		}
	} elsif (ref($CUSTOM_SEARCH) eq 'Regexp') {

		# Skip files that don't match the regex
		if (!($tor->{'title'} =~ $CUSTOM_SEARCH)) {
			if ($DEBUG) {
				print STDERR 'Skipping file: No match for CUSTOM_SEARCH regex (' . $CUSTOM_SEARCH . '): ' . $tor->{'title'} . "\n";
			}
			next;
		}
	}

	# Ensure the seed/leach count is usable
	seedCleanup($tor);

	# Only apply the quality rules if NO_QUALITY_CHECKS is not in effect
	if (!$CONFIG{'NO_QUALITY_CHECKS'} && lowQualityTor($tor)) {
		next;
	}

	# Save good torrents
	push(@{ $tors{ $tor->{'episode'} } }, $tor);
	if ($DEBUG) {
		print STDERR 'Possible URL ('
		  . $tor->{'seeds'} . '/'
		  . $tor->{'leaches'}
		  . ' seeds/leaches, '
		  . $tor->{'size'}
		  . ' MiB): '
		  . $tor->{'title'} . "\n";
	}
}

# Find the average torrent size for each episode
my %size = ();
{
	my %max = ();
	my %avg = ();

	foreach my $episode (keys(%tors)) {
		my $count = 0;
		$avg{$episode} = 0.001;
		$max{$episode} = 0.001;
		foreach my $tor (@{ $tors{$episode} }) {
			$count++;
			$avg{$episode} += $tor->{'size'};

			if ($tor->{'size'} > $max{$episode}) {
				$max{$episode} = $tor->{'size'};
			}
		}
		if ($count > 0) {
			$avg{$episode} /= $count;
		}
		if (!defined($max{$episode})) {
			warn("Invalid max episode\n");
		}
		if (!defined($avg{$episode})) {
			warn("Invalid avg episode\n");
		}
		$size{$episode} = ($max{$episode} + $avg{$episode}) / 2;

		if ($DEBUG) {
			print STDERR 'Episode '
			  . $episode
			  . ' max/avg/cmp size: '
			  . int($max{$episode}) . '/'
			  . int($avg{$episode}) . '/'
			  . int($size{$episode})
			  . " MiB\n";
		}
	}
}

# Calculate an adjusted count based on the peer count, relative file size, and title contents
foreach my $episode (keys(%tors)) {
	foreach my $tor (@{ $tors{$episode} }) {
		my $count = $tor->{'seeds'} + $tor->{'leaches'};

		# Start with the peer count
		$tor->{'adj_count'} = $count;

		# Adjust based on file size
		{
			my $size_ratio = $tor->{'size'} / $size{$episode};
			if ($tor->{'size'} >= $size{$episode}) {
				$tor->{'adj_count'} *= $CONFIG{'SIZE_BONUS'} * $size_ratio;
			} else {
				$tor->{'adj_count'} *= (1 / $CONFIG{'SIZE_PENALTY'}) * $size_ratio;
			}
		}

		# Adjust based on title contents
		if ($tor->{'title'} =~ /Subtitulado/i) {
			$tor->{'adj_count'} *= 1 / $CONFIG{'TITLE_PENALTY'};
		}

		# Truncate to an integer
		$tor->{'adj_count'} = int($tor->{'adj_count'});

		if ($DEBUG) {
			print STDERR 'Possible URL (' . $tor->{'adj_count'} . ' size-adjusted sources): ' . $tor->{'url'} . "\n";
		}
	}
}

# Pick the best-adjusted-count torrent for each episode
my %urls = ();
foreach my $episode (keys(%tors)) {
	my @sorted = sort { $b->{'adj_count'} <=> $a->{'adj_count'} } @{ $tors{$episode} };
	my $max = undef();
	foreach my $tor (@sorted) {
		if (!defined($max) || $tor->{'adj_count'} > $max) {
			if ($urls{$episode} = resolveSecondary($tor)) {
				if (!$tor->{'hash'} || $CONFIG{'EXCLUDES'}->{ $tor->{'hash'} }) {
					print STDERR 'Double-skipping file: Excluded hash (' . $tor->{'hash'} . '): ' . $tor->{'title'} . "\n";
					next;
				}
				$max = $tor->{'adj_count'};
			}
			if ($DEBUG) {
				print STDERR 'Semi-final URL (adjusted count: ' . $tor->{'adj_count'} . '): ' . $tor->{'url'} . "\n";
			}
		} elsif ($DEBUG) {
			print STDERR 'Skipping for lesser adjusted count (' . $tor->{'adj_count'} . '): ' . $tor->{'url'} . "\n";
		}
	}
}

# Output
foreach my $episode (keys(%tors)) {
	if (defined($urls{$episode})) {
		$urls{$episode} = resolveTrackers($urls{$episode});
		print $urls{$episode} . "\n";
		if ($CONFIG{'SYSLOG'}) {
			syslog(LOG_NOTICE, $show . ': ' . getHash($urls{$episode}));
		}
		if ($DEBUG) {
			print STDERR 'Final URL: ' . $urls{$episode} . "\n";
		}
	} elsif ($DEBUG) {
		print STDERR 'No URL for: ' . $episode . "\n";
	}
}

# Cleanup
if ($COOKIES) {
	unlink($COOKIES);
}
if ($SCRIPT) {
	unlink($SCRIPT);
}
if ($CONFIG{'SYSLOG'}) {
	closelog();
}
exit(0);

sub confDefault($;$) {
	my ($name, $default) = @_;
	if (!$name) {
		return;
	}

	# Enviornment, config file, default, undef()
	if (defined($ENV{$name})) {
		$CONFIG{$name} = $ENV{$name};
	} elsif (!defined($CONFIG{$name})) {
		if ($default) {
			$CONFIG{$name} = $default;
		} else {
			$CONFIG{$name} = undef();
		}
	}
}

sub readExcludes($) {
	my ($file) = @_;
	my %excludes = ();
	if (!$file || !-r $file) {
		warn('No excludes files available' . $file . "\n");
		return \%excludes;
	}

	my $fh;
	open($fh, '<', $file)
	  or die('Unable to open excludes file: ' . $file . ': ' . $! . "\n");
	while (<$fh>) {

		# Skip blank lines and comments
		if (/^\s*$/ || /^\s*#/) {
			next;
		}

		# Assume everything else is one BT hash/NZB GUID per line
		if (/^\s*(\w+)\s*$/) {
			my $hash = lc($1);
			if ($DEBUG > 1) {
				print STDERR 'Excluding hash: ' . $hash . "\n";
			}
			$excludes{$hash} = 1;
		} else {
			die('Invalid exclude line: ' . $_ . "\n");
		}
	}
	close($fh);

	return \%excludes;
}

sub parseNZB($) {
	my ($item) = @_;
	if (!$item || ref($item) ne 'HASH' || !exists($item->{'guid'})) {
		warn("Unable to parse NZB item\n");
		return undef();
	}

	# Ensure the record is sensible
	my $id = undef();
	if (ref($item->{'guid'}) eq 'HASH' && exists($item->{'guid'}->{'text'})) {
		$id = $item->{'guid'}->{'text'};
	} elsif (!ref($item->{'guid'})) {
		$id = $item->{'guid'};
	}
	if (!$id) {
		warn("Unable to parse NZB item GUID\n");
		return undef();
	}

	# NZB URL
	my $url = undef();
	if (exists($item->{'link'}) && $item->{'link'}) {
		$url = $item->{'link'};
		$url =~ s/^(https?)\:/${CONFIG{'PROTOCOL'}}\:/;
	}

	# Title
	my $title = undef();
	if (exists($item->{'title'}) && $item->{'title'}) {
		$title = $item->{'title'};
	} elsif (exists($item->{'description'}) && $item->{'description'}) {
		$title = $item->{'description'};
	}
	if ($title) {
		$url .= '#' . $title;
	}

	# Extract the season and episode numbers
	my ($season, $episode) = findSE($title);

	# Size
	my $size = 0;
	if (exists($item->{'newznab:attr'}) && $item->{'newznab:attr'} && ref($item->{'newznab:attr'}) eq 'ARRAY') {
		foreach my $hash (@{ $item->{'newznab:attr'} }) {
			if (ref($hash) eq 'HASH' && exists($hash->{'_name'}) && exists($hash->{'_value'}) && $hash->{'_name'} eq 'size') {
				$size = int($hash->{'_value'}) / 1024;
				last;
			}
		}
	} elsif (exists($item->{'attr'}) && $item->{'attr'} && ref($item->{'attr'}) eq 'ARRAY') {
		foreach my $hash (@{ $item->{'attr'} }) {
			if (!exists($hash->{'@attributes'}) || ref($hash->{'@attributes'}) ne 'HASH') {
				next;
			}
			$hash = $hash->{'@attributes'};
			if (exists($hash->{'name'}) && $hash->{'name'} eq 'size' && exists($hash->{'value'})) {
				$size = int($hash->{'value'}) / 1024;
				last;
			}
		}
	}

	# Date
	my $date = undef();
	if (exists($item->{'pubDate'}) && $item->{'pubDate'}) {
		$date = str2time($item->{'pubDate'});
	}

	# Sanity checks
	if (!$url) {
		warn('No URL in NZB item: ' . $id . "\n");
		return undef();
	}
	if (!$title) {
		warn('No title in NZB item: ' . $id . "\n");
		return undef();
	}
	if (!$size) {
		warn('No size in NZB item: ' . $id . "\n");
		return undef();
	}

	if ($DEBUG) {
		print STDERR 'Found file (' . $title . '): ' . $url . "\n";
	}

	# Save the extracted data
	my %tor = (
		'title'   => $title,
		'season'  => $season,
		'episode' => $episode,
		'date'    => $date,
		'size'    => $size,
		'url'     => $url,
	);
	return \%tor;
}

sub badTor($) {
	my ($tor) = @_;

	# Skip files that are in the torrent excludes list
	if ($tor->{'hash'} && $CONFIG{'EXCLUDES'}->{ $tor->{'hash'} }) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Excluded hash (' . $tor->{'hash'} . '): ' . $tor->{'title'} . "\n";
		}
		return 1;
	}

	# Skip files that don't start with our show title
	if (!($tor->{'title'} =~ $showRegex)) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title does not match (' . $showRegex . '): ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip leaked files
	} elsif ($tor->{'title'} =~ /leaked/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "leaked": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip pre-air files
	} elsif ($tor->{'title'} =~ /preair/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "preair": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip SWESUB files
	} elsif ($tor->{'title'} =~ /swesub/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "SWESUB": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip .rus. files
	} elsif ($tor->{'title'} =~ /\.rus\./i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains ".rus.": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip German files
	} elsif ($tor->{'title'} =~ /german/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "german": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip French files
	} elsif ($tor->{'title'} =~ /french/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "french": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip Spanish files
	} elsif ($tor->{'title'} =~ /Español/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "Español": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip Castellano files
	} elsif ($tor->{'title'} =~ /Castellano/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "Castellano": ' . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip unedited files
	} elsif ($tor->{'title'} =~ /unedited/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "unedited": ' . $tor->{'title'} . "\n";
		}
		return 1;
	}

	# If we're still around the TOR is good
	return 0;
}

sub seedCleanup($) {
	my ($tor) = @_;

	# Cap seeds/leaches/date and ensure they are always defined
	if (!exists($tor->{'seeds'}) || !$tor->{'seeds'}) {
		$tor->{'seeds'} = 0;
	}
	if ($tor->{'seeds'} > $CONFIG{'MAX_SEEDS'}) {
		$tor->{'seeds'} = $CONFIG{'MAX_SEEDS'};
	}
	if (!exists($tor->{'leaches'}) || !$tor->{'leaches'}) {
		$tor->{'leaches'} = 0;
	}
	if ($tor->{'leaches'} > $CONFIG{'MAX_SEEDS'}) {
		$tor->{'leaches'} = $CONFIG{'MAX_SEEDS'};
	}

	# Proxy publication date to seeder/leacher quality
	if ($tor->{'date'} && !$tor->{'seeds'}) {
		my $age = time() - $tor->{'date'};
		if ($age < 0) {
			warn('Invalid date (' . $tor->{'date'} . '): ' . $tor->{'name'} . "\n");
			$age = 0;
		}
		$age /= 86400;

		if ($age > $CONFIG{'NZB_AGE_GOOD'}) {
			$tor->{'seeds'} = $CONFIG{'MIN_COUNT'};
			if ($age > $CONFIG{'NZB_AGE_MAX'}) {
				$tor->{'seeds'} = ($CONFIG{'MIN_COUNT'} / 2) - 1;
			}
		} else {
			my $penalty = ($CONFIG{'MAX_SEEDS'} / 2) / $CONFIG{'NZB_AGE_GOOD'};
			$tor->{'seeds'} = $CONFIG{'MAX_SEEDS'} - ($age * $penalty);
		}
		$tor->{'seeds'}   = int($tor->{'seeds'});
		$tor->{'leaches'} = $tor->{'seeds'};
	}
}

sub lowQualityTor($) {
	my ($tor) = @_;

	# Skip torrents with too few seeders/leachers
	if (($tor->{'seeds'} + $tor->{'leaches'}) * $SOURCES->{ $tor->{'source'} }->{'weight'} < $CONFIG{'MIN_COUNT'}) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Insufficient seeder/leacher count ('
			  . $tor->{'seeds'} . '/'
			  . $tor->{'leaches'} . '): '
			  . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip torrents with unusual seed/leach ratios
	} elsif ($tor->{'seeds'} > 1
		&& $tor->{'seeds'} < $CONFIG{'SEED_RATIO_COUNT'}
		&& $tor->{'seeds'} > $tor->{'leaches'} * $CONFIG{'MAX_SEED_RATIO'})
	{
		if ($DEBUG) {
			print STDERR 'Skipping file: Unusual seeder/leacher ratio ('
			  . $tor->{'seeds'} . '/'
			  . $tor->{'leaches'} . '): '
			  . $tor->{'title'} . "\n";
		}
		return 1;

		# Skip torrents that are too small
	} elsif ($tor->{'size'} < $CONFIG{'MIN_SIZE'}) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Insufficient size (' . $tor->{'size'} . ' MiB): ' . $tor->{'title'} . "\n";
		}
		return 1;
	}

	# If we're still around the TOR is good
	return 0;
}

sub getHash($) {
	my ($tor) = @_;
	my $url;

	# Allow either a URL or a tor hashref
	if (ref($tor) eq 'HASH') {
		$url = $tor->{'url'};
	} else {
		$url = $tor;
		undef($tor);
	}

	# Extract the BTIH hash or NZB ID, if available
	my $hash = undef();
	if ($url =~ /\bxt\=urn\:btih\:(\w+)/i) {
		$hash = lc($1);
	} elsif ($url =~ /\/getnzb\/(\w+)\.nzb\&/i) {
		$hash = lc($1);
	}

	# Save back to the tor, if provided
	if (defined($tor) && defined($hash)) {
		$tor->{'hash'} = lc($hash);
	}

	# Always return the hash, or undef() if none can be found
	return $hash;
}

# Resolve secondary URLs
sub resolveSecondary($) {
	my ($tor) = @_;

	# Fetch the torrent-specific page and extract the magent link
	if ($tor->{'source'} eq 'ISO') {
		my ($content, $code) = fetch($tor->{'url'}, 'secondary.html');
		if ($code != 200) {
			print STDERR 'Error fetching secondary URL: ' . $tor->{'url'} . "\n";
			goto OUT;
		}
		my ($magnet) = $content =~ /\<a\s+href\=\"(magnet\:\?[^\"]+)\"/i;
		if (!defined($magnet) || length($magnet) < 1) {
			if ($DEBUG) {
				print STDERR 'No secondary URL available from: ' . $tor->{'url'} . "\n";
			}
			goto OUT;
		}
		$tor->{'url'} = decode_entities($magnet);
	}

	# Extract the hash
	getHash($tor);
	if (!$tor->{'hash'} || $CONFIG{'EXCLUDES'}->{ $tor->{'hash'} }) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Excluded hash (' . $tor->{'hash'} . '): ' . $tor->{'title'} . "\n";
		}
		goto OUT;
	}

  OUT:
	return $tor->{'url'};
}

sub resolveTrackers($) {
	my ($url) = @_;

	# Always append a few static trackers to the URI
	if ($url =~ /^magnet\:/i) {
		foreach my $tracker (@{ $CONFIG{'TRACKERS'} }) {
			my $arg = '&tr=' . uri_encode($tracker, { 'encode_reserved' => 1 });
			my $match = quotemeta($arg);
			if (!($url =~ /${match}/)) {
				$url .= $arg;
			}
		}
	}

	# Fetch a dynamic tracker list for any hashinfo from TorrentZ
	if ($CONFIG{'TRACKER_LOOKUP'} && defined($SOURCES->{'Z'}) && $url =~ /^magnet\:/ && $url =~ /\bxt\=urn\:btih\:(\w+)/i) {
		my $hash    = lc($1);
		my $baseURL = $SOURCES->{'Z'}->{'protocol'} . '://' . $SOURCES->{'Z'}->{'host'};
		my $hashURL = $baseURL . '/' . $hash;
		my ($content, $code) = fetch($hashURL, 'hashinfo.html');
		if ($code != 200) {
			print STDERR 'Error fetching hashinfo URL: ' . $hashURL . "\n";
			return $url;
		}

		# Parse out and fetch the tracker list URL
		my ($list) = $content =~ /\<a rel\=\"nofollow\" href\=\"(\/announcelist_\d+)\"\>/;
		if (!defined($list)) {
			if ($DEBUG) {
				print STDERR 'Unable to find tracker list link at: ' . $hashURL . "\n";
			}
			return $url;
		}
		my $listURL = $baseURL . $list;
		($content, $code) = fetch($listURL, 'tracker.html');
		if ($code != 200) {
			print STDERR 'Error fetching tracker list URL: ' . $listURL . "\n";
			return $url;
		}

		# Parse the tracker list and append our URL
		foreach my $line ($content) {
			if ($line =~ /^\s*$/) {
				next;
			}
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;
			if ($line =~ /^(?:http|udp)\:/i) {
				my $arg = '&tr=' . uri_encode($line, { 'encode_reserved' => 1 });
				my $match = quotemeta($arg);
				if (!($url =~ /${match}/)) {
					if ($DEBUG) {
						print STDERR 'Adding tracker: ' . $line . "\n";
					}
					$url .= $arg;
				}
			} else {
				print STDERR 'Unknown tracker type: ' . $line . "\n";
			}
		}
	}

	return $url;

}

sub splitTags($$$$) {
	my ($content, $tag, $header, $match) = @_;

	# Find each tag element
	my @out = ();
	my @parts = split(/\<${tag}(?:\s+[^\>]*)?\>/i, $content);
	foreach my $part (@parts) {

		# Trim trailing tags and skip things that aren't complete tags
		if (!($part =~ s/\<\/${tag}\>.*$//is)) {
			if ($DEBUG > 2) {
				print STDERR 'Skipping non-tag line: ' . $part . "\n\n";
			}
			next;
		}

		# Skip headers
		if (defined($header) && $part =~ /<${header}(?:\s+[^\>]*)?\>/i) {
			if ($DEBUG > 2) {
				print STDERR 'Skipping header line: ' . $part . "\n\n";
			}
			next;
		}

		# Skip non-matches
		if (defined($match) && !($part =~ m/${match}/i)) {
			if ($DEBUG > 2) {
				print STDERR 'Skipping non-match line: ' . $part . "\n\n";
			}
			next;
		}

		# Save good tags
		push(@out, $part);
	}

	return @out;
}

# Extract season
sub findSE($) {
	my ($name)  = @_;
	my $season  = 0;
	my $episode = 0;

	my $seasonBlock = '';
	if ($name =~ /(?:\b|_)(20\d\d(?:\.|\-)[01]?\d(?:\.|\-)[0-3]?\d)(?:\b|_)/) {
		$seasonBlock = $1;
		my ($month, $day);
		($season, $month, $day) = $seasonBlock =~ /(20\d\d)(?:\.|\-)([01]?\d)(?:\.|\-)([0-3]?\d)/;
		$episode = sprintf('%04d-%02d-%02d', $season, $month, $day);
	} elsif ($name =~ /(?:\b|_)(S(?:eason)?[_\s\.\-]*\d{1,2}[_\s\.\-]*E(?:pisode)?[_\s\.]*\d{1,3}(?:E\d{1,3})?)(?:\b|_)/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /S(?:eason)?[_\s\.\-]*(\d{1,2})[_\s\.\-]*E(?:pisode)?[_\s\.\-]*(\d{1,3})/i;
	} elsif ($name =~ /[\[\_\.](\d{1,2}x\d{2,3})[\]\_\.]/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /(\d+)x(\d+)/i;
	} elsif ($name =~ /(?:\b|_)([01]?\d[_\s\.]?[0-3]\d)(?:\b|_)/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /(?:\b|_)([01]?\d)[_\s\.]?([0-3]\d)/i;
	}

	# Return something valid and INTy or UNDEF
	if (!defined($seasonBlock) || $season < 1 || length($episode) < 1 || $episode eq '0') {
		if ($DEBUG) {
			print STDERR 'Could not find seasonBlock in: ' . $name . "\n";
		}
		$season  = undef();
		$episode = undef();
	} elsif ($episode =~ /^20\d{2}\-\d{2}\-\d{2}$/) {

		# Episode-by-date
		$season = int($season);
	} else {

		# Catchall
		# This will warn and return undef() (which is valid) on error
		$season  = int($season);
		$episode = int($episode);
	}
	return ($season, $episode);
}

sub initSources() {
	my %sources = ();

	# NZBplanet.net
	if ($CONFIG{'SOURCES'}->{'PLANET'}) {
		my @proxies = ('api.nzbplanet.net/api');
		my $source = findProxy(\@proxies, '\bNzbplanet\b');
		if ($source && exists($CONFIG{'PLANET_APIKEY'}) && $CONFIG{'PLANET_APIKEY'}) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 0;
			$source->{'search_exclude'} = 0;
			$source->{'search_suffix'}  = '';
			$source->{'custom_search'}  = sub ($$$$) {
				my ($urls, $series, $season, $episode) = @_;
				my $url =
				    $source->{'search_url'}
				  . '?o=json&t=tvsearch&q='
				  . $series
				  . '&season='
				  . $season . '&ep='
				  . $episode
				  . '&apikey='
				  . $CONFIG{'PLANET_APIKEY'};
				push(@{$urls}, $url);
			};
			$sources{'PLANET'} = $source;
		}
	}

	# NZB.is
	if ($CONFIG{'SOURCES'}->{'IS'}) {
		my @proxies = ('nzb.is/api');
		my $source = findProxy(\@proxies, '\bnzb\.is\b');
		if ($source && exists($CONFIG{'IS_APIKEY'}) && $CONFIG{'IS_APIKEY'}) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 0;
			$source->{'search_exclude'} = 0;
			$source->{'search_suffix'}  = '';
			$source->{'custom_search'}  = sub ($$$$) {
				my ($urls, $series, $season, $episode) = @_;
				my $url =
				    $source->{'search_url'}
				  . '?o=json&t=tvsearch&q='
				  . $series
				  . '&season='
				  . $season . '&ep='
				  . $episode
				  . '&apikey='
				  . $CONFIG{'IS_APIKEY'};
				push(@{$urls}, $url);
			};
			$sources{'IS'} = $source;
		}
	}

	# Usenet Crawler
	if ($CONFIG{'SOURCES'}->{'UC'}) {
		my @proxies = ('www.usenet-crawler.com/api');
		my $source = findProxy(\@proxies, '\busenet-crawler\b');
		if ($source && exists($CONFIG{'UC_APIKEY'}) && $CONFIG{'UC_APIKEY'}) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 0;
			$source->{'search_exclude'} = 0;
			$source->{'search_suffix'}  = '';
			$source->{'custom_search'}  = sub ($$$$) {
				my ($urls, $series, $season, $episode) = @_;
				my $url =
				    $source->{'search_url'}
				  . '?o=json&t=tvsearch&q='
				  . $series
				  . '&season='
				  . $season . '&ep='
				  . $episode
				  . '&apikey='
				  . $CONFIG{'UC_APIKEY'};
				push(@{$urls}, $url);
			};
			$sources{'UC'} = $source;
		}
	}

	# NZB Cat
	if ($CONFIG{'SOURCES'}->{'NCAT'}) {
		my @proxies = ('nzb.cat/api');
		my $source = findProxy(\@proxies, '\bforgottenpassword\b');
		if ($source && exists($CONFIG{'NCAT_APIKEY'}) && $CONFIG{'NCAT_APIKEY'}) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 0;
			$source->{'search_exclude'} = 0;
			$source->{'search_suffix'}  = '';
			$source->{'custom_search'}  = sub ($$$$) {
				my ($urls, $series, $season, $episode) = @_;
				my $url =
				    $source->{'search_url'}
				  . '?o=json&t=tvsearch&q='
				  . $series
				  . '&season='
				  . $season . '&ep='
				  . $episode
				  . '&apikey='
				  . $CONFIG{'NCAT_APIKEY'};
				push(@{$urls}, $url);
			};
			$sources{'NCAT'} = $source;
		}
	}

	# The Pirate Bay
	if ($CONFIG{'SOURCES'}->{'TPB'}) {
		my @proxies = ('thepiratebay.org/search/', 'tpb.unblocked.co/search/');
		my $source = findProxy(\@proxies, '\bPirate Search\b');
		if ($source) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 0;
			$source->{'search_exclude'} = 1;
			$source->{'search_suffix'}  = '/0/7/0';
			$sources{'TPB'}             = $source;
		}
	}

	# ISOhunt
	if ($CONFIG{'SOURCES'}->{'ISO'}) {
		my @proxies = ('isohunt.to/torrents/?ihq=', 'isohunters.net/torrents/?ihq=');
		my $source = findProxy(\@proxies, 'Last\s+\d+\s+files\s+indexed');
		if ($source) {
			$source->{'weight'}         = 0.75;
			$source->{'quote'}          = 1;
			$source->{'search_exclude'} = 1;
			$source->{'search_suffix'}  = '';
			$sources{'ISO'}             = $source;
		}
	}

	# Kickass
	if ($CONFIG{'SOURCES'}->{'KICK'}) {
		my @proxies = ('kickass.cd/search.php?q=', 'kickass.mx/search.php?q=');
		my $source = findProxy(\@proxies, '/search.php');
		if ($source) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 1;
			$source->{'search_exclude'} = 1;
			$source->{'search_suffix'}  = '/';
			$sources{'KICK'}            = $source;
		}
	}

	# Torrentz
	if ($CONFIG{'SOURCES'}->{'Z'}) {
		my @proxies = ('torrentz.eu/search?q=', 'torrentz.me/search?q=', 'torrentz.ch/search?q=', 'torrentz.in/search?q=');
		my $source = findProxy(\@proxies, 'Indexing [\d\,]+ active torrents');
		if ($source) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 1;
			$source->{'search_exclude'} = 1;
			$source->{'search_suffix'}  = '';
			if (!$CONFIG{'NO_QUALITY_CHECKS'}) {
				$source->{'search_suffix'} = '+peer+%3E+' . $CONFIG{'MIN_COUNT'};
			}
			$sources{'Z'} = $source;
		}
	}

	# ExtraTorrent
	if ($CONFIG{'SOURCES'}->{'ET'}) {
		my @proxies = (
			'extra.to/search/?search=',    'etmirror.com/search/?search=',
			'etproxy.com/search/?search=', 'extratorrentlive.com/search/?search='
		);
		my $source = findProxy(\@proxies, '/search/');
		if ($source) {
			$source->{'weight'}         = 1.00;
			$source->{'quote'}          = 1;
			$source->{'search_exclude'} = 0;
			$source->{'search_suffix'}  = '&new=1&x=0&y=0&srt=seeds&order=desc';
			$source->{'search_url'}     = 'phantomjs:' . $source->{'search_url'};
			$sources{'ET'}              = $source;
		}
	}

	# Sanity check
	if (scalar(keys(%sources)) < 1) {
		die("No sources available\n");
	}

	return \%sources;
}

sub findProxy($$) {
	my ($proxies, $match) = @_;

	# Automatically select a proxy
	my $host       = '';
	my $protocol   = '';
	my $search_url = '';
	foreach my $url (@{$proxies}) {
		my $path;
		($protocol, $host, $path) = $url =~ /^(?:(https?)\:\/\/)?([^\/]+)(\/.*)?$/i;
		if (!$protocol) {
			$protocol = $CONFIG{'PROTOCOL'};
		}
		if (!$host) {
			print STDERR 'Could not parse proxy URL: ' . $url . "\n";
			next;
		}
		my ($content, $code) = fetch($protocol . '://' . $host, undef(), 1);
		if ($code == 200 && $content =~ m/${match}/i) {
			$search_url = $protocol . '://' . $host . $path;
			last;
		} elsif ($DEBUG) {
			print STDERR 'Proxy not available: ' . $host . "\n";
			if ($DEBUG > 1) {
				print STDERR $content . "\n";
			}
		}
	}

	# Return the search data if at least one proxy is up
	if ($search_url) {
		my %tmp = (
			'protocol'   => $protocol,
			'host'       => $host,
			'search_url' => $search_url,
		);
		return \%tmp;
	}

	# Return undef if we didn't find any working proxies
	return undef();
}

sub fetch($;$$) {
	my ($url, $file, $nocheck) = @_;
	if ($DEBUG > 1) {
		print STDERR 'Fetch: ' . $url . "\n";
	}

	# Allow usage with short names
	if ($file && !($file =~ /^\//)) {
		$file = '/tmp/findTorrent-' . $file;
	}

	# Random delay
	if ($DEBUG > 1) {
		sleep($CONFIG{'SLEEP'} * 0.25);
	} else {
		sleep($CONFIG{'DELAY'} * (rand($CONFIG{'SLEEP'}) + ($CONFIG{'SLEEP'} / 2)));
	}

	# Allow JS processing
	if ($url =~ /^phantomjs\:\s*(\S.*)$/i) {
		return phantomFetch($1, $file);
	}

	# Fetch object
	if (!$FETCH) {
		if (!$COOKIES) {
			$COOKIES = mktemp('/tmp/findTorrent.cookies.XXXXXXXX');
		}
		$FETCH = Fetch->new(
			'cookiefile' => $COOKIES,
			'timeout'    => $CONFIG{'TIMEOUT'},
			'uas'        => $CONFIG{'UA'}
		);
	}

	# Debug as requested
	if ($DEBUG > 1 && $file) {
		$FETCH->file($file);
	} else {
		$FETCH->file('');
	}

	# Standard fetch
	$FETCH->url($url);
	if ($nocheck) {
		$FETCH->fetch('nocheck' => 1);
	} else {
		$FETCH->fetch();
	}
	return (scalar($FETCH->content()), $FETCH->status_code());
}

sub phantomFetch($$) {
	my ($url, $file) = @_;

	# Init
	if (!$SCRIPT) {
		$SCRIPT = mktemp('/tmp/findTorrent.phantom.XXXXXXXX');
		open(my $fh, '>', $SCRIPT)
		  or die('Unable to open PhantomJS script file: ' . $! . "\n");
		print $fh $CONFIG{'PHANTOM_CONFIG'};
		close($fh);
	}

	# Capture STDOUT, drop STDERR
	my @cmd = ($CONFIG{'PHANTOM_BIN'}, $SCRIPT, $url);
	my ($content, undef(), undef()) = capture { system(@cmd); };

	# Debug as requested
	if ($DEBUG > 1 && $file) {
		open(my $fh, '>', $file)
		  or warn('Unable to open phantom debug file: ' . $! . "\n");
		if ($fh) {
			print $fh $content;
			close($fh);
		}
	}

	# Try to get the response status code, fake one if we cannot
	my ($code) = $content =~ /^(\d\d\d)$/m;
	if (!defined($code)) {
		warn("Unable to retrive HTTP status code. Faking success...\n");
		$code = 200;
	}

	return ($content, $code);
}
