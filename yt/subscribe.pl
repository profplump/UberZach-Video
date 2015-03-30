#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/";

use File::Touch;
use File::Basename;
use Date::Parse;
use Date::Format;
use LWP::Simple;
use URI::Escape;
use JSON;
use XML::LibXML;
use IPC::System::Simple qw( system run capture EXIT_ANY $EXITVAL );
use IPC::Cmd qw( can_run );
use PrettyPrint;

# Paramters
my %USERS           = ('profplump' => 'kj-Ob6eYHvzo-P0UWfnQzA', 'shanda' => 'hfwMHzkPXOOFDce5hyQkTA');
my $EXTRAS_FILE     = 'extra_videos.ini';
my $EXCLUDES_FILE   = 'exclude_videos.ini';
my $YTDL_BIN        = $ENV{'HOME'} . '/bin/video/yt/youtube-dl';
my @YTDL_ARGS       = ('--force-ipv4', '--socket-timeout', '10', '--no-playlist', '--max-downloads', '1', '--age-limit', '99');
my @YTDL_QUIET      = ('--quiet', '--no-warnings');
my @YTDL_DEBUG      = ('--verbose');
my $BATCH_SIZE      = 50;
my $MAX_INDEX       = 25000;
my $FETCH_LIMIT     = 50;
my $DRIFT_TOLERANCE = 2;
my $DRIFT_FACTOR    = 100.0;
my $DELAY           = 5;
my $API_URL         = 'https://gdata.youtube.com/feeds/api/';
my %API             = (
	'search' => {
		'prefix' => $API_URL . 'users/',
		'suffix' => '/uploads',
		'params' => {
			'start-index' => 1,
			'max-results' => 1,
			'strict'      => 1,
			'v'           => 2,
			'alt'         => 'jsonc',
		},
	},
	'subscriptions' => {
		'prefix' => $API_URL . 'users/',
		'suffix' => '/subscriptions',
		'params' => {
			'start-index' => 1,
			'max-results' => 1,
			'strict'      => 1,
			'v'           => 2,
			'alt'         => 'json',
		},
	},
	'video' => {
		'prefix' => $API_URL . 'videos/',
		'suffix' => '',
		'params' => {
			'strict' => 1,
			'v'      => 2,
			'alt'    => 'jsonc'
		},
	},
	'channel' => {
		'prefix' => $API_URL . 'users/',
		'suffix' => '',
		'params' => {
			'strict' => 1,
			'v'      => 2,
			'alt'    => 'json'
		},
	},
);

# Prototypes
sub findVideos($);
sub findFiles();
sub findVideo($);
sub buildNFO($);
sub buildSeriesNFO($);
sub getSubscriptions($$);
sub saveSubscriptions($$);
sub saveChannel($);
sub getChannel($);
sub fetchParse($$);
sub saveString($$);
sub readExcludes();
sub readExtras();
sub parseVideoData($);
sub dropExcludes($);
sub addExtras($);
sub updateNFOData($$$);
sub videoSE($$);
sub videoPath($$$$);
sub renameVideo($$$$$$);
sub parseFilename($);

# Sanity check
if (scalar(@ARGV) < 1) {
	die('Usage: ' . basename($0) . " output_directory\n");
}

# Command-line parameters
my ($dir) = @ARGV;
$dir =~ s/\/+$//;
if (!-d $dir) {
	die('Invalid output directory: ' . $dir . "\n");
}
my $user = basename($dir);
if (length($user) < 1 || !($user =~ /^\w+$/)) {
	die('Invalid user: ' . $user . "\n");
}

# Move to the target directory so we can use relative paths later
chdir($dir);

# Environmental parameters (debug)
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	if ($ENV{'DEBUG'} =~ /(\d+)/) {
		$DEBUG = $1;
	} else {
		$DEBUG = 1;
	}
}
my $NO_FETCH = 0;
if ($ENV{'NO_FETCH'}) {
	$NO_FETCH = 1;
}
my $NO_NFO = 0;
if ($ENV{'NO_NFO'}) {
	$NO_NFO = 1;
}
my $NO_SEARCH = 0;
if ($ENV{'NO_SEARCH'}) {
	$NO_SEARCH = 1;
}
my $NO_FILES = 0;
if ($ENV{'NO_FILES'}) {
	$NO_FILES = 1;
}
my $NO_CHANNEL = 0;
if ($ENV{'NO_CHANNEL'}) {
	$NO_CHANNEL = 1;
}
my $NO_EXTRAS = 0;
if ($ENV{'NO_EXTRAS'}) {
	$NO_EXTRAS = 1;
}
my $NO_EXCLUDES = 0;
if ($ENV{'NO_EXCLUDES'}) {
	$NO_EXCLUDES = 1;
}
my $NO_RENAME = 0;
if ($ENV{'NO_RENAME'}) {
	$NO_RENAME = 1;
}

# Environmental parameters (functional)
my $FORCE_RENAME = 0;
if ($ENV{'FORCE_RENAME'}) {
	$FORCE_RENAME = 1;
}
my $SUDO_CHATTR = 1;
if ($ENV{'NO_CHATTR'} || !can_run('sudo') || !can_run('chattr')) {
	$SUDO_CHATTR = 0;
}
if ($ENV{'MAX_INDEX'} && $ENV{'MAX_INDEX'} =~ /(\d+)/) {
	$MAX_INDEX = $1;
}
if ($ENV{'BATCH_SIZE'} && $ENV{'BATCH_SIZE'} =~ /(\d+)/) {
	$BATCH_SIZE = $1;
}
if (exists($ENV{'FETCH_LIMIT'}) && $ENV{'FETCH_LIMIT'} =~ /(\d+)/) {
	$FETCH_LIMIT = $1;
}

# Construct globals
foreach my $key (keys(%API)) {
	if (exists($API{$key}{'params'}{'max-results'})) {
		$API{$key}{'params'}{'max-results'} = $BATCH_SIZE;
	}
}
if ($DEBUG > 1) {
	push(@YTDL_ARGS, @YTDL_DEBUG);
} elsif (!$DEBUG) {
	push(@YTDL_ARGS, @YTDL_QUIET);
}

# Allow use as a subscription manager
if ($0 =~ /subscription/i) {
	my %subs = ();
	foreach my $user (keys(%USERS)) {
		my $tmp = getSubscriptions($user, $USERS{$user});
		foreach my $sub (keys(%{$tmp})) {
			if (exists($subs{$sub})) {
				$subs{$sub} .= ', ' . $tmp->{$sub};
			} else {
				$subs{$sub} = $tmp->{$sub};
			}
		}
	}
	saveSubscriptions($dir, \%subs);
	exit(0);
}

# Grab the channel data
my $channel = {};
if (!$NO_CHANNEL) {
	$channel = getChannel($user);
	saveChannel($channel);
}

# Find all the user's videos on YT
my $videos = {};
if (!$NO_SEARCH) {
	$videos = findVideos($user);
}

# Find any requested "extra" videos
my $extras = {};
if (!$NO_EXTRAS) {
	$extras = addExtras($videos);
}

# Drop any "excludes" videos
my $excludes = {};
if (!$NO_EXCLUDES) {
	$excludes = dropExcludes($videos);
}

# Calculate the episode number using the publish dates
{
	my @byDate     = sort { $videos->{$a}->{'date'} <=> $videos->{$b}->{'date'} || $a cmp $b } keys %{$videos};
	my $num        = undef();
	my $lastSeason = undef();
	foreach my $id (@byDate) {
		if (!$lastSeason || $lastSeason != $videos->{$id}->{'season'}) {
			$num        = 1;
			$lastSeason = $videos->{$id}->{'season'};
		}
		$videos->{$id}->{'number'} = $num++;
	}
}

# Find all existing YT files on disk
my $files = {};
if (!$NO_FILES) {
	$files = findFiles();
}

# Whine about unknown videos
foreach my $id (keys(%{$files})) {
	if (!exists($videos->{$id}) && $files->{$id}->{'season'} > 0) {
		print STDERR 'Local video not known to YT channel (' . $user . '): ' . $id . "\n";
		renameVideo($files->{$id}->{'path'}, $files->{$id}->{'suffix'}, $files->{$id}->{'nfo'}, $id, 0, $files->{$id}->{'season'} . $files->{$id}->{'number'});
	}
}

# Fill in missing videos and NFOs
my $fetched = 0;
foreach my $id (keys(%{$videos})) {
	my $nfo = videoPath($videos->{$id}->{'season'}, $videos->{$id}->{'number'}, $id, 'nfo');

	# Determine if we may or must rename
	my $rename = 0;
	if (exists($files->{$id})) {
		# Renumber if we drift a lot
		if ($files->{$id}->{'path'}) {
			my $delta     = abs($files->{$id}->{'number'} - $videos->{$id}->{'number'});
			my $tolerance = $files->{$id}->{'number'} / $DRIFT_FACTOR;
			if ($FORCE_RENAME) {
				$tolerance = 0;
			} elsif ($tolerance < $DRIFT_TOLERANCE) {
				$tolerance = $DRIFT_TOLERANCE;
			}
			if ($delta > $tolerance) {
				if ($DEBUG) {
					print STDERR 'Rename due to drift (' . $delta . '/' . $tolerance . ")\n"
				}
				$rename = 1;
			}
		}

		# Always rename if the NFO does not match the media
		if ($files->{$id}->{'path'} && $files->{$id}->{'nfo'}) {
			my ($mseason, $mnumber) = parseFilename($files->{$id}->{'path'});
			my ($nseason, $nnumber) = parseFilename($files->{$id}->{'nfo'});
			if ($mseason != $nseason || $mnumber != $nnumber) {
				if ($DEBUG) {
					print STDERR "Rename due to media-metadata mismatch\n"
				}
				$rename = 1;
			}
		}
	}

	# Warn (and optionally rename) as selected
	if ($rename) {
		print STDERR 'Video ' . $id . ' had video number ' . $files->{$id}->{'number'} . ' but now has video number ' . $videos->{$id}->{'number'} . "\n";
		renameVideo($files->{$id}->{'path'}, $files->{$id}->{'suffix'}, $files->{$id}->{'nfo'}, $id, $videos->{$id}->{'season'}, $videos->{$id}->{'number'});
	}

	# If we haven't heard of the file, or don't have an NFO for it
	# Checking for the NFO allows use to resume failed downloads
	if (!exists($files->{$id}) || !-e $nfo) {
		if ($DEBUG) {
			print STDERR 'Fetching video: ' . $id . "\n";
		}

		# Let youtube-dl handle the URLs and downloading
		{
			my @args = ('--output', videoSE($videos->{$id}->{'season'}, $videos->{$id}->{'number'}) . '%(id)s.%(ext)s', '--', $id);
			my @name = ($YTDL_BIN);
			push(@name, @YTDL_ARGS);
			my @fetch = @name;
			push(@name,  '--get-filename');
			push(@fetch, @args);
			push(@name,  @args);

			if ($NO_FETCH) {
				print STDERR 'Not running: ' . join(' ', @fetch) . "\n";
			} else {

				# Count fetch attempts (even if they fail later)
				$fetched++;
				if ($FETCH_LIMIT && $fetched > $FETCH_LIMIT) {
					print STDERR 'Reached fetch limit (' . $FETCH_LIMIT . ') for: ' . $user . "\n";
					if ($DEBUG) {
						print STDERR "\tLocal/Remote videos at start:" . scalar(keys(%{$files})) . '/' . scalar(keys(%{$videos})) . "\n";
					}
					exit 1;
				}

				# Find the output file name
				if ($DEBUG > 1) {
					print STDERR join(' ', @name) . "\n";
				}
				sleep($DELAY);
				my $file = capture(EXIT_ANY, @name);
				if ($EXITVAL != 0) {
					warn('Error executing youtube-dl (name): ' . $EXITVAL . "\n");
					next;
				}
				$file =~ s/^\s+//;
				$file =~ s/\s+$//;

				# Sanity check
				if (!$file) {
					warn('No file name available for video: ' . $id . "\n");
					next;
				}

				# Download
				if ($DEBUG > 1) {
					print STDERR join(' ', @fetch) . "\n";
				}
				sleep($DELAY);
				my $exit = run(EXIT_ANY, @fetch);
				if ($exit != 0) {
					warn('Error executing youtube-dl for video: ' . $file . "\n");
					next;
				}

				# Ensure we found something useful
				if (-e $file . '.part') {
					warn('Partial download detected: ' . $file . "\n");
					next;
				}
				if (!-s $file) {
					warn('No output video file: ' . $file . "\n");
					next;
				}

				# Touch the file to reflect the download time rather than the upload time
				touch($file);
			}
		}

		# Build and save the XML document
		my $xml = buildNFO($videos->{$id});
		if ($DEBUG > 1) {
			print STDERR 'Saving NFO: ' . $xml . "\n";
		}
		if ($NO_NFO) {
			print STDERR "Not saving NFO\n";
		} else {
			saveString($nfo, $xml);
		}
	}
}

sub saveString($$) {
	my ($path, $str) = @_;

	my $fh = undef();
	if (!open($fh, '>', $path)) {
		warn('Cannot open file for writing: ' . $path . ': ' . $! . "\n");
		return undef();
	}
	print $fh $str;
	close($fh);
	return 1;
}

sub buildSeriesNFO($) {
	my ($channel) = @_;

	# Create an XML tree
	my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
	$doc->setStandalone(1);
	my $show = $doc->createElement('tvshow');
	$doc->setDocumentElement($show);
	my $elm;

	# Add data
	$elm = $doc->createElement('title');
	$elm->appendText($channel->{'title'});
	$show->appendChild($elm);

	$elm = $doc->createElement('premiered');
	$elm->appendText(time2str('%Y-%m-%d', $channel->{'date'}));
	$show->appendChild($elm);

	$elm = $doc->createElement('plot');
	$elm->appendText($channel->{'description'});
	$show->appendChild($elm);

	# Return the string
	return $doc->toString();
}

sub buildNFO($) {
	my ($video) = @_;

	# Create an XML tree
	my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
	$doc->setStandalone(1);
	my $show = $doc->createElement('episodedetails');
	$doc->setDocumentElement($show);
	my $file = $doc->createElement('fileinfo');
	$show->appendChild($file);
	my $stream = $doc->createElement('streamdetails');
	$file->appendChild($stream);
	my $stream_video = $doc->createElement('video');
	$stream->appendChild($stream_video);
	my $elm;

	# Add data
	$elm = $doc->createElement('season');
	$elm->appendText($video->{'season'});
	$show->appendChild($elm);

	$elm = $doc->createElement('episode');
	$elm->appendText($video->{'number'});
	$show->appendChild($elm);

	if (!defined($video->{'title'})) {
		$video->{'title'} = 'Episode ' . $video->{'number'};
	}
	$elm = $doc->createElement('title');
	$elm->appendText($video->{'title'});
	$show->appendChild($elm);

	if (!defined($video->{'date'})) {
		$video->{'date'} = time();
	}
	$elm = $doc->createElement('aired');
	$elm->appendText(time2str('%Y-%m-%d', $video->{'date'}));
	$show->appendChild($elm);

	if (defined($video->{'description'})) {
		$elm = $doc->createElement('plot');
		$elm->appendText($video->{'description'});
		$show->appendChild($elm);
	}

	if (defined($video->{'duration'})) {
		$elm = $doc->createElement('runtime');
		$elm->appendText($video->{'duration'});
		$show->appendChild($elm);

		$elm = $doc->createElement('durationinseconds');
		$elm->appendText($video->{'duration'});
		$stream_video->appendChild($elm);
	}

	if (defined($video->{'rating'})) {
		$elm = $doc->createElement('rating');
		$elm->appendText($video->{'rating'});
		$show->appendChild($elm);
	}

	if (defined($video->{'creator'})) {
		$elm = $doc->createElement('director');
		$elm->appendText($video->{'creator'});
		$show->appendChild($elm);
	}

	# Return the string
	return $doc->toString();
}

sub findFiles() {
	my %files = ();

	# Allow complete bypass
	if ($NO_FILES) {
		return \%files;
	}

	# Read the output directory
	my $fh = undef();
	opendir($fh, '.')
	  or die('Unable to open files directory: ' . $! . "\n");
	while (my $file = readdir($fh)) {
		my ($season, $num, $id, $suffix) = parseFilename($file);
		if (defined($id) && length($id) > 0) {

			# Create the record as needed
			if (!exists($files{$id})) {
				my %tmp = (
					'season' => $season,
					'number' => $num,
				);
				$files{$id} = \%tmp;
			}

			# Video or NFO?
			my $type = 'path';
			if ($suffix eq 'nfo') {
				$type = 'nfo';
			}

			# Deal with duplicates
			if (exists($files{$id}->{$type})) {
				if ($type eq 'nfo') {
					warn('Duplicate NFO: ' . $id . "\n\t" . $files{$id}->{'nfo'} . "\n\t" . $file . "\n");
					if (!$NO_RENAME) {
						warn("\tDeleting: " . $file . "\n");
						if ($SUDO_CHATTR) {
							system('sudo', 'chattr', '-i', $file);
						}
						unlink($file);
						next;
					}
				} else {
					warn('Duplicate video: ' . $id . "\n\t" . $files{$id}->{'path'} . "\n\t" . $file . "\n");
					if (!$NO_RENAME) {
						my $del = $file;
						if ($suffix ne 'mp4' && $files{$id}->{'suffix'} eq 'mp4') {
							$del = $files{$id}->{'path'};
						}
						warn("\tDeleting: " . $del . "\n");
						if ($SUDO_CHATTR) {
							system('sudo', 'chattr', '-i', $del);
						}
						unlink($del);
						next;
					}
				}
			}

			# Assign the component paths
			$files{$id}->{$type} = $file;
			if ($type ne 'nfo') {
				$files{$id}->{'suffix'} = $suffix;
			}
		}
	}
	close($fh);

	if ($DEBUG) {
		print STDERR 'Found ' . scalar(keys(%files)) . " local videos\n";
		if ($DEBUG > 1) {
			print STDERR prettyPrint(\%files, "\t") . "\n";
		}
	}

	return \%files;
}

sub fetchParse($$) {
	my ($name, $id) = @_;

	my $url = $API{$name}{'prefix'} . $id . $API{$name}{'suffix'} . '?';
	foreach my $key (keys(%{ $API{$name}{'params'} })) {
		$url .= '&' . uri_escape($key) . '=' . uri_escape($API{$name}{'params'}{$key});
	}

	# Fetch
	if ($DEBUG) {
		print STDERR 'Fetching ' . $name . ' API URL: ' . $url . "\n";
	}
	sleep($DELAY);
	my $content = get($url);
	if (!defined($content) || length($content) < 10) {
		die('Invalid content from URL: ' . $url . "\n");
	}

	# Parse
	my $data = decode_json($content);
	if (!defined($data) || ref($data) ne 'HASH') {
		die('Invalid JSON: ' . $content . "\n");
	}
	if ($DEBUG > 2) {
		print STDERR "Raw JSON data:\n" . prettyPrint($data, '  ') . "\n";
	}

	return $data;
}

sub getSubscriptions($$) {
	my ($user, $id) = @_;

	my $index     = 1;
	my $itemCount = undef();
	my %subs      = ();
	SUBS_LOOP:
	{
		# Build, fetch, parse
		$API{'subscriptions'}{'params'}{'start-index'} = $index;
		my $data = fetchParse('subscriptions', $id);

		# It's all in the feed
		if (!exists($data->{'feed'}) || ref($data->{'feed'}) ne 'HASH') {
			die("Invalid subscription data\n");
		}
		$data = $data->{'feed'};

		# Grab the total count, so we know when to stop
		if (!defined($itemCount)) {
			if (  !exists($data->{'openSearch$totalResults'})
				|| ref($data->{'openSearch$totalResults'}) ne 'HASH'
				|| !exists($data->{'openSearch$totalResults'}->{'$t'}))
			{
				die("Invalid subscription feed metadata\n");
			}

			$itemCount = $data->{'openSearch$totalResults'}->{'$t'};
		}

		# Process each item
		if (!exists($data->{'entry'}) || ref($data->{'entry'}) ne 'ARRAY') {
			die("Invalid subscription entries\n");
		}
		my $items = $data->{'entry'};
		foreach my $item (@{$items}) {
			if (   ref($item) ne 'HASH'
				|| !exists($item->{'yt$username'})
				|| ref($item->{'yt$username'}) ne 'HASH'
				|| !exists($item->{'yt$username'}->{'$t'}))
			{
				next;
			}
			if ($DEBUG) {
				print STDERR prettyPrint($item->{'yt$username'}, "\t") . "\n";
			}
			$subs{ $item->{'yt$username'}->{'$t'} } = $user;
		}

		# Loop if there are results left to fetch
		$index += $BATCH_SIZE;
		if (defined($itemCount) && $itemCount >= $index) {

			# But don't go past the max supported index
			if ($index <= $MAX_INDEX) {
				redo SUBS_LOOP;
			}
		}
	}

	# Return the list of subscribed usernames
	return \%subs;
}

sub saveSubscriptions($$) {
	my ($folder, $subs) = @_;

	# Check for local subscriptions missing from YT
	my %locals = ();
	my $fh     = undef();
	opendir($fh, '.')
	  or die('Unable to open subscriptions directory: ' . $folder . ': ' . $! . "\n");
	while (my $file = readdir($fh)) {

		# Skip dotfiles
		if ($file =~ /^\./) {
			next;
		}

		# Skip non-directories
		if (!-d $file) {
			next;
		}

		# YT has some trouble with case
		my $lcFile = lc($file);

		# Anything else should be in the list
		if (!$subs->{$file} && !$subs->{$lcFile}) {
			print STDERR 'Missing YT subscription for: ' . $file . "\n";
		}

		# Note local subscriptions
		$locals{$lcFile} = 1;
	}
	closedir($fh);

	# Check for YT subscriptions missing locally
	foreach my $sub (keys(%{$subs})) {
		if (!exists($locals{ lc($sub) })) {
			print STDERR 'Adding local subscription for: ' . $sub . ' (' . $subs->{$sub} . ")\n";
			mkdir($folder . '/' . $sub);
		}
	}
}

sub saveChannel($) {
	my ($channel) = @_;

	my $nfo = 'tvshow.nfo';
	if (!-e $nfo) {
		if ($DEBUG) {
			print STDERR 'Saving series data for: ' . $channel->{'title'} . "\n";
		}

		# Save the poster
		if (exists($channel->{'thumbnail'}) && length($channel->{'thumbnail'}) > 5) {
			my $jpg = get($channel->{'thumbnail'});
			saveString('poster.jpg', $jpg);
		}

		# Save the series NFO
		my $xml = buildSeriesNFO($channel);
		if ($DEBUG > 1) {
			print STDERR 'Saving NFO: ' . $xml . "\n";
		}
		saveString($nfo, $xml);
	}
}

sub getChannel($) {
	my ($user) = @_;

	# Build, fetch, parse
	my $data = fetchParse('channel', $user);

	if (!exists($data->{'entry'}) || ref($data->{'entry'}) ne 'HASH') {
		die("Invalid channel data\n");
	}
	$data = $data->{'entry'};

	# Extract the data we want
	my %channel = (
		'id'          => $data->{'yt$channelId'}->{'$t'},
		'title'       => $data->{'title'}->{'$t'},
		'date'        => str2time($data->{'published'}->{'$t'}),
		'description' => $data->{'summary'}->{'$t'},
		'thumbnail'   => $data->{'media$thumbnail'}->{'url'},
	);
	return \%channel;
}

sub readExcludes() {
	my %excludes = ();

	# Read and parse the excludes videos file, if it exists
	if (-e $EXCLUDES_FILE) {
		my $fh;
		open($fh, $EXCLUDES_FILE)
		  or die('Unable to open excludes videos file: ' . $! . "\n");
		while (<$fh>) {

			# Skip blank lines and comments
			if ($_ =~ /^\s*#/ || $_ =~ /^\s*$/) {
				next;
			}

			# Match our specific format or whine
			if ($_ =~ /^\s*([\w\-]+)\s*$/) {
				if ($DEBUG > 1) {
					print STDERR 'Adding exclude video: ' . $1 . "\n";
				}
				$excludes{$1} = 1;
			} else {
				print STDERR 'Skipped exclude video line: ' . $_;
			}
		}
		close($fh);
	}

	return \%excludes;
}

sub readExtras() {
	my %extras = ();

	# Read and parse the extra videos file, if it exists
	if (-e $EXTRAS_FILE) {
		my $fh;
		open($fh, $EXTRAS_FILE)
		  or die('Unable to open extra videos file: ' . $! . "\n");
		while (<$fh>) {

			# Skip blank lines and comments
			if ($_ =~ /^\s*#/ || $_ =~ /^\s*$/) {
				next;
			}

			# Match our specific format or whine
			if ($_ =~ /^\s*(\d+)\s*[=:>]+\s*([\w\-]+)\s*$/) {
				if ($DEBUG > 1) {
					print STDERR 'Adding extra video: ' . $1 . ' => ' . $2 . "\n";
				}
				$extras{$2} = $1;
			} else {
				print STDERR 'Skipped extra video line: ' . $_;
			}
		}
		close($fh);
	}

	return \%extras;
}

sub parseVideoData($) {
	my ($data) = @_;
	my %video = (
		'title'       => $data->{'title'},
		'date'        => str2time($data->{'uploaded'}),
		'description' => $data->{'description'},
		'duration'    => $data->{'duration'},
		'rating'      => $data->{'rating'},
		'creator'     => $data->{'uploader'},
	);
	$video{'season'} = time2str('%Y', $video{'date'});
	return \%video;
}

sub findVideo($) {
	my ($id) = @_;

	# Build, fetch, parse
	my $data = fetchParse('video', $id);

	# Validate
	if (!exists($data->{'data'})) {
		die("Invalid video list\n");
	}
	$data = $data->{'data'};

	# Parse the video data
	return parseVideoData($data);
}

sub dropExcludes($) {
	my ($videos) = @_;
	my $excludes = readExcludes();
	foreach my $id (keys(%{$excludes})) {
		if (!exists($videos->{$id})) {
			if ($DEBUG > 1) {
				print STDERR 'Skipping unknown excludes video: ' . $id . "\n";
			}
			next;
		}
		delete($videos->{$id});
	}
	return $excludes;
}

sub addExtras($) {
	my ($videos) = @_;
	my $extras = readExtras();
	foreach my $id (keys(%{$extras})) {
		if (exists($videos->{$id})) {
			if ($DEBUG > 1) {
				print STDERR 'Skipping known extra video: ' . $id . "\n";
			}
			next;
		}

		my $video = findVideo($id);
		$videos->{$id} = $video;
	}
	return $extras;
}

sub findVideos($) {
	my ($user) = @_;
	my %videos = ();

	# Allow complete bypass
	if ($NO_SEARCH) {
		return \%videos;
	}

	# Loop through until we have all the entries
	my $index     = 1;
	my $itemCount = undef();
	LOOP:
	{

		# Build, fetch, parse
		$API{'search'}{'params'}{'start-index'} = $index;
		my $data = fetchParse('search', $user);

		# Grab the total count, so we know when to stop
		if (!exists($data->{'data'})) {
			die("Invalid video list\n");
		}
		$data = $data->{'data'};
		if (!defined($itemCount) && exists($data->{'totalItems'})) {
			$itemCount = $data->{'totalItems'};
		}

		# Process each item
		if (!exists($data->{'items'}) || ref($data->{'items'}) ne 'ARRAY') {
			die("Invalid video list\n");
		}
		my $items  = $data->{'items'};
		my $offset = 0;
		foreach my $item (@{$items}) {
			my $video = parseVideoData($item);
			$videos{ $item->{'id'} } = $video;
			$offset++;
		}

		# Loop if there are results left to fetch
		$index += $BATCH_SIZE;
		if (defined($itemCount) && $itemCount >= $index) {

			# But don't go past the max supported index
			if ($index <= $MAX_INDEX) {
				redo LOOP;
			}
		}
	}

	if ($DEBUG) {
		print STDERR 'Found ' . scalar(keys(%videos)) . " remote videos\n";
		if ($DEBUG > 1) {
			print STDERR prettyPrint(\%videos, "\t") . "\n";
		}
	}

	return \%videos;
}

sub updateNFOData($$$) {
	my ($file, $season, $episode) = @_;

	my $nfoData = undef();
	{
		open(my $fh, '<', $file)
		  or warn('Unable to open NFO for renumber: ' . $file . ': ' . $! . "\n");
		$/       = undef;
		$nfoData = <$fh>;
		close($fh);
	}

	if ($nfoData) {
		$nfoData =~ s/<season>\d+<\/season>/<season>${season}<\/season>/;
		$nfoData =~ s/<episode>\d+<\/episode>/<episode>${episode}<\/episode>/;
	}

	return $nfoData;
}

sub videoSE($$) {
	my ($season, $episode) = @_;
	return sprintf('S%02dE%02d - ', $season, $episode);

}

sub videoPath($$$$) {
	my ($season, $episode, $id, $ext) = @_;
	return videoSE($season, $episode) . $id . '.' . $ext;
}

sub renameVideo($$$$$$) {
	my ($video, $suffix, $nfo, $id, $season, $episode) = @_;

	# Bail if disabled
	if ($NO_RENAME) {
		print STDERR 'Not renaming: ' . $video . "\n";
		return;
	}

	# General sanity checks
	if (!defined($id) || !defined($season) || !defined($episode)) {
		die("Invalid call to renameVideo()\n\t" . $video . "\n\t" . $suffix . "\n\t" . $nfo . "\n\t" . $id . "\n\t" . $season . "\n\t" . $episode . "\n");
	}

	# Warning about useless calls
	if (!defined($nfo) && (!defined($video) || !defined($suffix))) {
		warn("No NFO or video path provided in renameVideo()\n");
		return;
	}

	# Video
	if (defined($video) && defined($suffix)) {
		my $videoNew = videoPath($season, $episode, $id, $suffix);

		# Sanity checks, as we do dangerous work here
		if (!-r $video) {
			die('Invalid video source in rename: ' . $video . "\n");
		}
		if ($video ne $videoNew) {
			print STDERR 'Renaming ' . $video . ' => ' . $videoNew . "\n";
			if (-e $videoNew) {
				die('Rename: Target exists: ' . $videoNew . "\n");
			}
			if ($SUDO_CHATTR) {
				system('sudo', 'chattr', '-i', $video);
			}
			rename($video, $videoNew)
			  or die('Unable to rename: ' . $video . ': ' . $! . "\n");
		}
	}

	# NFO
	if (defined($nfo)) {
		my $nfoNew = videoPath($season, $episode, $id, 'nfo');

		# Sanity checks, as we do dangerous work here
		if (!-r $nfo) {
			die('Invalid NFO source in rename: ' . $nfo . "\n");
		}

		# Parse old NFO data
		my $nfoData = updateNFOData($nfo, $season, $episode)
		  or die('No NFO data found, refusing to rename: ' . $id . "\n");

		# Write a new NFO and unlink the old one
		if ($SUDO_CHATTR) {
			system('sudo', 'chattr', '-i', $nfo);
		}
		saveString($nfoNew, $nfoData);
		if ($nfo ne $nfoNew) {
			print STDERR 'Renaming ' . $nfo . ' => ' . $nfoNew . "\n";
			unlink($nfo)
			  or warn('Unable to delete NFO during rename: ' . $! . "\n");
		}
	}
}

sub parseFilename($) {
	my ($file) = @_;
	return $file =~ /^S(\d+)+E(\d+) - ([\w\-]+)\.(\w\w\w)$/i;
}
