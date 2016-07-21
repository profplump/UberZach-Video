#!/usr/bin/perl
use strict;
use warnings;

# Defaults
my $DEBUG               = 0;
my $NO_QUALITY_CHECKS   = 0;
my $MORE_NUMBER_FORMATS = 0;
my $MIN_DAYS_BACK       = 0;
my $MAX_DAYS_BACK       = 3;
my $NEXT_EPISODES       = 3;

# Local config
my $TV_DIR = `~/bin/video/mediaPath` . '/TV';

# Search parameters
my $PROTOCOL = 'https';
my %ENABLE_SOURCE = ('TPB' => 1, 'ISO' => 1, 'KICK' => 1, 'Z' => 0);

# Selection parameters
my $MIN_COUNT        = 10;
my $MIN_SIZE         = 100;
my $SIZE_BONUS       = 7;
my $SIZE_PENALTY     = $SIZE_BONUS;
my $TITLE_PENALTY    = $SIZE_BONUS / 2;
my $MAX_SEED_RATIO   = .25;
my $SEED_RATIO_COUNT = 10;
my $TRACKER_LOOKUP   = 1;

# App config
my $DELAY         = 10;
my $TIMEOUT       = 15;
my $ERR_DELAY     = $TIMEOUT * 2;
my $ERR_RETRIES   = 3;
my $UA            = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/538.39.41 (KHTML, like Gecko) Version/8.0 Safari/538.39.41';
my $EXCLUDES_FILE = $ENV{'HOME'} . '/.findTorrent.exclude';

# Static tracker list, appended to all magnet URIs
my @TRACKERS = ('udp://open.demonii.com:1337/announce', 'udp://tracker.publicbt.com:80/announce', 'udp://tracker.openbittorrent.com:80/announce', 'udp://9.rarbg.com:2710/announce');

# Includes
use URI::Encode qw(uri_encode);
use HTML::Entities;
use HTML::Strip;
use JSON;
use File::Temp;
use File::Spec;
use File::Basename;
use FindBin qw($Bin);
use lib $Bin;
use Fetch;

# Prototypes
sub getHash($);
sub resolveSecondary($);
sub resolveTrackers($);
sub splitTags($$$);
sub findSE($);
sub initSources();
sub findProxy($$);

# Command line
my ($dir, $search) = @ARGV;
if (!defined($dir)) {
	die('Usage: ' . basename($0) . " input_directory [search_string]\n");
}

# Fetch object
my $cookies = mktemp('/tmp/findTorrent.cookies.XXXXXXXX');
my $fetch   = Fetch->new(
	'cookiefile' => $cookies,
	'timeout'    => $TIMEOUT,
	'uas'        => $UA
);

# Environment
if ($ENV{'DEBUG'}) {
	if ($ENV{'DEBUG'} =~ /(\d+)/) {
		$DEBUG = $1;
	} else {
		$DEBUG = 1;
	}
}
if (exists($ENV{'EXCLUDES_FILE'})) {
	$EXCLUDES_FILE = $ENV{'EXCLUDES_FILE'};
}
if ($ENV{'NO_QUALITY_CHECKS'}) {
	$NO_QUALITY_CHECKS = 1;
}
if ($ENV{'MORE_NUMBER_FORMATS'}) {
	$MORE_NUMBER_FORMATS = 1;
}
if (defined($ENV{'MIN_DAYS_BACK'})) {
	$MIN_DAYS_BACK = $ENV{'MIN_DAYS_BACK'};
}
if (defined($ENV{'MAX_DAYS_BACK'})) {
	$MAX_DAYS_BACK = $ENV{'MAX_DAYS_BACK'};
}
if (defined($ENV{'NEXT_EPISODES'})) {
	$NEXT_EPISODES = $ENV{'NEXT_EPISODES'};
}

# Read the torrent excludes list
my %EXCLUDES = ();
if ($EXCLUDES_FILE && -r $EXCLUDES_FILE) {
	my $fh;
	open($fh, '<', $EXCLUDES_FILE)
	  or die('Unable to open excludes file: ' . $EXCLUDES_FILE . ': ' . $! . "\n");
	while (<$fh>) {

		# Skip blank lines and comments
		if (/^\s*$/ || /^\s*#/) {
			next;
		}

		# Assume everything else is one BT hash per line
		if (/^\s*(\w+)\s*$/) {
			my $hash = lc($1);
			if ($DEBUG > 1) {
				print STDERR 'Excluding hash: ' . $hash . "\n";
			}
			$EXCLUDES{$hash} = 1;
		} else {
			die('Invalid exclude line: ' . $_ . "\n");
		}
	}
	close($fh);
} elsif ($DEBUG) {
	print STDERR 'No excludes file available';
	if ($EXCLUDES_FILE) {
		print STDERR ': ' . $EXCLUDES_FILE;
	}
	print STDERR "\n";
}

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
		$dir  = $TV_DIR . '/' . $dir;
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
	$NO_QUALITY_CHECKS = 1;
	if ($DEBUG) {
		print STDERR 'Searching with no quality checks: ' . $show . "\n";
	}
}

# Allow use of more number formats
if (-e $dir . '/more_number_formats') {
	$MORE_NUMBER_FORMATS = 1;
	if ($DEBUG) {
		print STDERR 'Searching with more number formats: ' . $show . "\n";
	}
}

# Read the search excludes file, if any
my $exclude = '';
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
		if (length($exclude)) {
			$exclude .= ' ';
		}
		$exclude .= '-"' . $ex . '"';
	}
	$exclude = uri_encode(' ' . $exclude);
}

# Setup our sources
my $SOURCES = initSources();

# Adjust the inter-page delay with respect to the number of unique sources
$DELAY /= scalar(keys(%{$SOURCES})) / 2;

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
	for (my $days_back = $MIN_DAYS_BACK ; $days_back <= $MAX_DAYS_BACK ; $days_back++) {

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
		print STDERR 'Seaching with date template: ' . $str . "\n";
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
		for (my $i = 1 ; $i <= $NEXT_EPISODES ; $i++) {
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

				# Use quotes around the show name if the source needs them
				my $quote = '%22';
				if (!$source->{'quote'}) {
					$quote = '';
				}

				# Calculate the compete search prefix and suffix to simplify later concatenations
				my $prefix = $source->{'search_url'} . $quote . $urlShow . $quote;
				my $suffix = $exclude;
				if ($source->{'search_suffix'}) {
					$suffix .= $source->{'search_suffix'};
				}

				# SXXEYY
				my $url = $prefix . '+s' . $season_long . 'e' . $episode_long . $suffix;
				push(@urls, $url);

				# Extra searches for shows that have lazy/non-standard number formats
				if ($MORE_NUMBER_FORMATS) {

					# SXEY
					if ($season_long ne $season || $episode_long ne $episode) {
						$url = $prefix . '+s' . $season . 'e' . $episode . $exclude . $suffix;
						push(@urls, $url);
					}

					# SXX EYY
					$url = $prefix . '+s' . $season_long . '+e' . $episode_long . $exclude . $suffix;
					push(@urls, $url);

					# Season XX Episode YY
					$url = $prefix . '+season+' . $season_long . '+episode+' . $episode_long . $exclude . $suffix;
					push(@urls, $url);

					# Series X Episode Y
					$url = $prefix . '+series+' . $season . '+episode+' . $episode . $exclude . $suffix;
					push(@urls, $url);

					# SxEE
					$url = $prefix . '+' . $season . 'x' . $episode_long . $exclude . $suffix;
					push(@urls, $url);

					# Season X
					if ($NO_QUALITY_CHECKS) {
						$url = $prefix . '+Season+' . $season . $exclude . $suffix;
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
	HTTP_ERR_LOOP: {
		if ($DEBUG) {
			print STDERR 'Searching with URL: ' . $url . "\n";
			$fetch->file('/tmp/findTorrent-lastPage.html');
		}
		sleep($DELAY * (rand(2) + 0.5));
		$fetch->url($url);
		$fetch->fetch('nocheck' => 1);

		# Check for useful errors
		if ($fetch->status_code() == 404) {
			if ($DEBUG) {
				print STDERR "Skipping content from 404 response\n";
			}
			next;
		}

		# Check for errors
		if ($fetch->status_code() != 200) {
			if ($fetch->status_code() >= 500 && $fetch->status_code() <= 599) {
				if ($errCount > $ERR_RETRIES) {
					print STDERR 'Unable to fetch URL: ' . $url . "\n";
					$errCount = 0;
					next;
				}
				if ($DEBUG) {
					print STDERR 'Retrying URL (' . $fetch->status_code() . '): ' . $url . "\n";
				}
				$errCount++;
				sleep($ERR_DELAY);
				redo HTTP_ERR_LOOP;
			} else {
				print STDERR 'Error fetching URL (' . $fetch->status_code() . '): ' . $url . "\n";
			}
			next;
		}
	}

	# Save the content, discriminating by data type
	if ($DEBUG) {
		print STDERR 'Fetched ' . length($fetch->content()) . " bytes\n";
	}
	if ($fetch->content() =~ /^\s*{/) {
		my $json = eval { decode_json($fetch->content()); };
		if (defined($json) && ref($json)) {
			push(@json_content, \@{ $json->{'items'}->{'list'} });
		} elsif ($DEBUG) {
			print STDERR 'JSON parsing failure on: ' . $fetch->content() . "\n";
		}
	} else {
		push(@html_content, scalar($fetch->content()));
	}
}

# We need someplace to store parsed torrent data from the various sources
my @tors = ();

# Handle HTML content
foreach my $content (@html_content) {
	if ($content =~ /\<title\>The Pirate Bay/i) {

		# Find TR elements from TPB
		my @trs = splitTags($content, 'TR', 'TH');
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
		my @trs = splitTags($content, 'TR', 'TH');
		foreach my $tr (@trs) {

			# Split each TD element from the row
			my @tds = split(/\<td(?:\s+[^\>]*)?\>/i, $tr);
			my $numCols = scalar(@tds) - 1;
			if ($numCols > 9 && $numCols < 8) {
				print STDERR 'Invalid ISO TR: ' . $tr . "\n";
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
				if ($DEBUG) {
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

			# Fetch the detail page for the URL
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
		my @trs = splitTags($content, 'TR', 'TH');
		foreach my $tr (@trs) {

			# Split each TD element from the row
			my @tds = split(/\<td(?:\s+[^\>]*)?\>/i, $tr);
			my $numCols = scalar(@tds) - 1;
			if ($numCols > 9 && $numCols < 8) {
				print STDERR 'Invalid KICK TR: ' . $tr . "\n";
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
			if ($tds[5] =~ /(\d+)\<\/td\>/i) {
				$seeds = $1;
			}
			my $leaches = 0;
			if ($tds[6] =~ /(\d+)\<\/td\>/i) {
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
		my @dls = splitTags($content, 'DL', undef());
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

	} elsif ($content =~ /Database\s+maintenance/i) {
		if ($DEBUG) {
			print STDERR "Source down for maintenance\n";
		}
	} elsif ($content =~ /^\s*$/) {
		if ($DEBUG) {
			print STDERR "Source returned no content\n";
		}
	} else {
		print STDERR "Unknown HTML content:\n" . $content . "\n\n";
	}
}

# Handle JSON content
foreach my $content (@json_content) {
	print STDERR "Unknown JSON content:\n" . $content . "\n\n";
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

	# Extract the BTIH, if available
	getHash($tor);

	# Skip files that are in the torrent excludes list
	if ($tor->{'hash'} && $EXCLUDES{ $tor->{'hash'} }) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Excluded hash (' . $tor->{'hash'} . '): ' . $tor->{'title'} . "\n";
		}
		next;
	}

	# Skip files that don't start with our show title
	if (!($tor->{'title'} =~ $showRegex)) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title does not match (' . $showRegex . '): ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip pre-air files
	} elsif ($tor->{'title'} =~ /preair/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "preair": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip SWESUB files
	} elsif ($tor->{'title'} =~ /swesub/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "SWESUB": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip .rus. files
	} elsif ($tor->{'title'} =~ /\.rus\./i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains ".rus.": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip German files
	} elsif ($tor->{'title'} =~ /german/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "german": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip French files
	} elsif ($tor->{'title'} =~ /french/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "french": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip Spanish files
	} elsif ($tor->{'title'} =~ /Español/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "Español": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip Castellano files
	} elsif ($tor->{'title'} =~ /Castellano/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "Castellano": ' . $tor->{'title'} . "\n";
		}
		next;

		# Skip unedited files
	} elsif ($tor->{'title'} =~ /unedited/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "unedited": ' . $tor->{'title'} . "\n";
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
		} elsif ((defined($tor->{'episode'}) && !$need{ $tor->{'episode'} }) || (!defined($tor->{'episode'}) && !$NO_QUALITY_CHECKS)) {
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

	# Only apply the quality rules if NO_QUALITY_CHECKS is not in effect
	if (!$NO_QUALITY_CHECKS) {

		# Skip torrents with too few seeders/leachers
		if (($tor->{'seeds'} + $tor->{'leaches'}) * $SOURCES->{ $tor->{'source'} }->{'weight'} < $MIN_COUNT) {
			if ($DEBUG) {
				print STDERR 'Skipping file: Insufficient seeder/leacher count (' . $tor->{'seeds'} . '/' . $tor->{'leaches'} . '): ' . $tor->{'title'} . "\n";
			}
			next;

			# Skip torrents with unusual seed/leach ratios
		} elsif ($tor->{'seeds'} > 1
			&& $tor->{'seeds'} < $SEED_RATIO_COUNT
			&& $tor->{'seeds'} > $tor->{'leaches'} * $MAX_SEED_RATIO)
		{
			if ($DEBUG) {
				print STDERR 'Skipping file: Unusual seeder/leacher ratio (' . $tor->{'seeds'} . '/' . $tor->{'leaches'} . '): ' . $tor->{'title'} . "\n";
			}
			next;

			# Skip torrents that are too small
		} elsif ($tor->{'size'} < $MIN_SIZE) {
			if ($DEBUG) {
				print STDERR 'Skipping file: Insufficient size (' . $tor->{'size'} . ' MiB): ' . $tor->{'title'} . "\n";
			}
			next;
		}
	}

	# Save good torrents
	push(@{ $tors{ $tor->{'episode'} } }, $tor);
	if ($DEBUG) {
		print STDERR 'Possible URL (' . $tor->{'seeds'} . '/' . $tor->{'leaches'} . ' seeds/leaches, ' . $tor->{'size'} . ' MiB): ' . $tor->{'title'} . "\n";
	}
}

# Find the average torrent size for each episode
my %avg = ();
foreach my $episode (keys(%tors)) {
	my $count = 0;
	$avg{$episode} = 0.001;
	foreach my $tor (@{ $tors{$episode} }) {
		$avg{$episode} += $tor->{'size'};
		$count++;
	}
	if ($count > 0) {
		$avg{$episode} /= $count;
	}
	if ($DEBUG) {
		print STDERR 'Episode ' . $episode . ' average size: ' . int($avg{$episode}) . " MiB\n";
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
			my $size_ratio = $tor->{'size'} / $avg{$episode};
			if ($tor->{'size'} >= $avg{$episode}) {
				$tor->{'adj_count'} *= $SIZE_BONUS * $size_ratio;
			} else {
				$tor->{'adj_count'} *= (1 / $SIZE_PENALTY) * $size_ratio;
			}
		}

		# Adjust based on title contents
		if ($tor->{'title'} =~ /Subtitulado/i) {
			$tor->{'adj_count'} *= 1 / $TITLE_PENALTY;
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
		if (!$tor->{'hash'} || $EXCLUDES{ $tor->{'hash'} }) {
			print STDERR 'Double-skipping file: Excluded hash (' . $tor->{'hash'} . '): ' . $tor->{'title'} . "\n";
			next;
		}
		if (!defined($max) || $tor->{'adj_count'} > $max) {
			if ($urls{$episode} = resolveSecondary($tor)) {
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
		if ($DEBUG) {
			print STDERR 'Final URL: ' . $urls{$episode} . "\n";
		}
	} elsif ($DEBUG) {
		print STDERR 'No URL for: ' . $episode . "\n";
	}
}

# Cleanup
unlink($cookies);
exit(0);

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

	# Extract the BTIH hash, if available
	my $hash = undef();
	if ($url =~ /\bxt\=urn\:btih\:(\w+)/i) {
		$hash = lc($1);
	}

	# Save back to the tor, if provided
	if (defined($tor)) {
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
		if ($DEBUG) {
			print STDERR 'Secondary fetch with URL: ' . $tor->{'url'} . "\n";
			$fetch->file('/tmp/findTorrent-secondary.html');
		}
		sleep($DELAY * (rand(2) + 0.5));
		$fetch->url($tor->{'url'});
		$fetch->fetch();
		if ($fetch->status_code() != 200) {
			print STDERR 'Error fetching secondary URL: ' . $tor->{'url'} . "\n";
			goto OUT;
		}
		my ($magnet) = $fetch->content() =~ /\<a\s+href\=\"(magnet\:\?[^\"]+)\"/i;
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
	if (!$tor->{'hash'} || $EXCLUDES{ $tor->{'hash'} }) {
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
		foreach my $tracker (@TRACKERS) {
			my $arg = '&tr=' . uri_encode($tracker, { 'encode_reserved' => 1 });
			my $match = quotemeta($arg);
			if (!($url =~ /${match}/)) {
				$url .= $arg;
			}
		}
	}

	# Fetch a dynamic tracker list for any hashinfo from TorrentZ
	if ($TRACKER_LOOKUP && defined($SOURCES->{'Z'}) && $url =~ /^magnet\:/ && $url =~ /\bxt\=urn\:btih\:(\w+)/i) {
		my $hash    = lc($1);
		my $baseURL = $SOURCES->{'Z'}->{'protocol'} . '://' . $SOURCES->{'Z'}->{'host'};
		my $hashURL = $baseURL . '/' . $hash;
		if ($DEBUG) {
			print STDERR 'Hashinfo fetch with URL: ' . $hashURL . "\n";
			$fetch->file('/tmp/findTorrent-hashinfo.html');
		}
		sleep($DELAY * (rand(2) + 0.5));
		$fetch->url($hashURL);
		$fetch->fetch();
		if ($fetch->status_code() != 200) {
			print STDERR 'Error fetching hashinfo URL: ' . $hashURL . "\n";
			return $url;
		}

		# Parse out and fetch the tracker list URL
		my ($list) = $fetch->content() =~ /\<a rel\=\"nofollow\" href\=\"(\/announcelist_\d+)\"\>/;
		if (!defined($list)) {
			if ($DEBUG) {
				print STDERR 'Unable to find tracker list link at: ' . $hashURL . "\n";
			}
			return $url;
		}
		my $listURL = $baseURL . $list;
		if ($DEBUG) {
			print STDERR 'Tracker list fetch with URL: ' . $listURL . "\n";
			$fetch->file('/tmp/findTorrent-tracker.html');
		}
		sleep($DELAY * (rand(2) + 0.5));
		$fetch->url($listURL);
		$fetch->fetch();
		if ($fetch->status_code() != 200) {
			print STDERR 'Error fetching tracker list URL: ' . $listURL . "\n";
			return $url;
		}

		# Parse the tracker list and append our URL
		foreach my $line ($fetch->content()) {
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

sub splitTags($$$) {
	my ($content, $tag, $header) = @_;

	# Find each tag element
	my @out = ();
	my @parts = split(/\<${tag}(?:\s+[^\>]*)?\>/i, $content);
	foreach my $part (@parts) {

		# Trim trailing tags and skip things that aren't complete tags
		if (!($part =~ s/\<\/${tag}\>.*$//is)) {
			if ($DEBUG > 1) {
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
		$season = int($season);
		$episode = int($episode);
	}
	return ($season, $episode);
}

sub initSources() {

	my %sources = ();

	# The Pirate Bay
	if ($ENABLE_SOURCE{'TPB'}) {
		my @proxies = ('thepiratebay.org/search/', 'pirateproxy.la/search/', 'tpb.unblocked.co/search/');
		my $source = findProxy(\@proxies, '\bPirate Search\b');
		if ($source) {
			$source->{'weight'}        = 1.00;
			$source->{'quote'}         = 0;
			$source->{'search_suffix'} = '/0/7/0';
			$sources{'TPB'}            = $source;
		}
	}

	# ISOhunt
	if ($ENABLE_SOURCE{'ISO'}) {
		my @proxies = ('http://isohunters.net/torrents/?ihq=', 'isohunt.to/torrents/?ihq=');
		my $source = findProxy(\@proxies, 'Last\s+\d+\s+files\s+indexed');
		if ($source) {
			$source->{'weight'}        = 0.25;
			$source->{'quote'}         = 1;
			$source->{'search_suffix'} = '';
			$sources{'ISO'}            = $source;
		}
	}

	# Kickass
	if ($ENABLE_SOURCE{'KICK'}) {
		my @proxies = ('kat.cr/usearch/', 'kickass.unblocked.pw/usearch/', 'kickass.to/usearch/');
		my $source = findProxy(\@proxies, '/usearch/');
		if ($source) {
			$source->{'weight'}        = 0.50;
			$source->{'quote'}         = 1;
			$source->{'search_suffix'} = '/';
			$sources{'KICK'}           = $source;
		}
	}

	# Torrentz
	if ($ENABLE_SOURCE{'Z'}) {
		my @proxies = ('torrentz.eu/search?q=', 'torrentz.me/search?q=', 'torrentz.ch/search?q=', 'torrentz.in/search?q=');
		my $source = findProxy(\@proxies, 'Indexing [\d\,]+ active torrents');
		if ($source) {
			$source->{'weight'}        = 0.75;
			$source->{'quote'}         = 1;
			$source->{'search_suffix'} = '';
			if (!$NO_QUALITY_CHECKS) {
				$source->{'search_suffix'} = '+peer+%3E+' . $MIN_COUNT,;
			}
			$sources{'Z'} = $source;
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
			$protocol = $PROTOCOL;
		}
		if (!$host) {
			print STDERR 'Could not parse proxy URL: ' . $url . "\n";
			next;
		}
		$fetch->url($protocol . '://' . $host);
		if ($fetch->fetch('nocheck' => 1) == 200 && $fetch->content() =~ m/${match}/i) {
			$search_url = $protocol . '://' . $host . $path;
			last;
		} elsif ($DEBUG) {
			print STDERR 'Proxy not available: ' . $host . "\n";
			if ($DEBUG > 1) {
				print STDERR $fetch->content() . "\n";
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
