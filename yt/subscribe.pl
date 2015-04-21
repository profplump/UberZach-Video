#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/";

use File::Touch;
use File::Basename;
use Date::Parse;
use Date::Format;
use LWP::UserAgent;
use URI::Escape;
use JSON;
use XML::LibXML;
use IPC::System::Simple qw( system run capture EXIT_ANY $EXITVAL );
use IPC::Cmd qw( can_run );
use PrettyPrint;

# Paramters
#my %USERS = ('profplump' => 'UCkj-Ob6eYHvzo-P0UWfnQzA', 'shanda' => 'hfwMHzkPXOOFDce5hyQkTA');
my %USERS         = ('profplump' => 'UCkj-Ob6eYHvzo-P0UWfnQzA');
my $EXTRAS_FILE   = 'extra_videos.ini';
my $EXCLUDES_FILE = 'exclude_videos.ini';
my $YTDL_BIN      = $ENV{'HOME'} . '/bin/video/yt/youtube-dl';
my @YTDL_ARGS     = ('--force-ipv4', '--socket-timeout', '10', '--no-playlist', '--max-downloads', '1', '--age-limit', '99');
my @YTDL_QUIET    = ('--quiet', '--no-warnings');
my @YTDL_DEBUG    = ('--verbose');
my $BATCH_SIZE    = 50;
my $MAX_INDEX     = 25000;
my $FETCH_LIMIT   = 50;
my $DELAY         = 1.1;
my $HTTP_TIMEOUT  = 10;
my $HTTP_UA       = 'ZachBot/1.0 (Plex)';
my $HTTP_VERIFY   = 0;
my $API_URL       = 'https://www.googleapis.com/youtube/v3/';
my $API_KEY       = $ENV{'YT_API_KEY'};
my %API           = (

	#https://www.googleapis.com/youtube/v3/channels?part=id&forUsername={channelName}&key={YOUR_API_KEY}
	'channelID' => {
		'url'    => $API_URL . 'channels',
		'params' => {
			'part' => 'id',
			'key'  => $API_KEY,
		},
	},

	#https://www.googleapis.com/youtube/v3/channels?part=snippet&id={channelID}&key={YOUR_API_KEY}
	'channel' => {
		'url'    => $API_URL . 'channels',
		'params' => {
			'part' => 'snippet',
			'key'  => $API_KEY,
		},
	},

	#https://www.googleapis.com/youtube/v3/search?part=snippet&channelId={channelID}&maxResults={maxResults}&pageToken={foo}&safeSearch=none&type=video&key={YOUR_API_KEY}
	'search' => {
		'url'    => $API_URL . 'search',
		'params' => {
			'part'       => 'id',
			'key'        => $API_KEY,
			'maxResults' => 5,
			'safeSearch' => 'none',
			'type'       => 'video'
		},
	},

	#https://www.googleapis.com/youtube/v3/videos?part=snippet&id={videoID}&key={YOUR_API_KEY}
	'video' => {
		'url'    => $API_URL . 'videos',
		'params' => {
			'part' => 'snippet,contentDetails',
			'key'  => $API_KEY,
		},
	},

	#https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&channelId={channelID}&key={YOUR_API_KEY}
	'subscriptions' => {
		'url'    => $API_URL . 'subscriptions',
		'params' => {
			'part'       => 'snippet',
			'key'        => $API_KEY,
			'maxResults' => 5,
		},
	},
);

# Prototypes
sub getVideoData($);
sub findVideos($);
sub findFiles($);
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
sub videoNumberStr($$);
sub videoSE($$);
sub videoPath($$$$);
sub renameVideo($$$$$$);
sub parseFilename($);
sub fetch($$);

# Sanity check
if (scalar(@ARGV) < 1) {
	die('Usage: ' . basename($0) . " output_directory\n");
}

# Command-line parameters
my ($DIR) = @ARGV;
$DIR =~ s/\/+$//;
if (!-d $DIR) {
	die('Invalid output directory: ' . $DIR . "\n");
}
my $ID = basename($DIR);
if ($ID =~ /\s\((\w+)\)$/) {
	$ID = $1;
} else {
	die('Invalid folder: ' . $DIR . "\n");
}
if (length($ID) < 1 || !($ID =~ /^\w+$/)) {
	die('Invalid channel ID: ' . $ID . "\n");
}

# Move to the target directory so we can use relative paths later
chdir($DIR);

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
my $LWP = undef();
foreach my $key (keys(%API)) {
	if (exists($API{$key}{'params'}{'maxResults'})) {
		$API{$key}{'params'}{'maxResults'} = $BATCH_SIZE;
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
	saveSubscriptions($DIR, \%subs);
	exit(0);
}

# Grab the channel data
my $channel = {};
if (!$NO_CHANNEL) {
	$channel = getChannel($ID);
	saveChannel($channel);
}

# Find all the user's videos on YT
my $videos = {};
if (!$NO_SEARCH) {
	$videos = findVideos($ID);
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
	$files = findFiles($videos);
}

# Whine about unknown videos
foreach my $id (keys(%{$files})) {
	if (!exists($videos->{$id}) && $files->{$id}->{'season'} > 0) {
		print STDERR 'Local video not known to YT channel (' . $ID . '): ' . $id . "\n";
		renameVideo($files->{$id}->{'path'}, $files->{$id}->{'suffix'}, $files->{$id}->{'nfo'}, $id, 0, $files->{$id}->{'season'} . $files->{$id}->{'number'});
	}
}

# Fill in missing videos and NFOs
my $fetched = 0;
foreach my $id (keys(%{$videos})) {
	if ($DEBUG > 1) {
		print STDERR 'Checking remote video: ' . $id . "\n";
		if (!exists($files->{$id})) {
			print STDERR "\tLocal file: <missing>\n";
		} else {
			print STDERR "\tLocal media: " . $files->{$id}->{'path'} . "\n";
			print STDERR "\tLocal NFO: " . $files->{$id}->{'nfo'} . "\n";
		}
	}
	my $nfo = videoPath($videos->{$id}->{'season'}, $videos->{$id}->{'number'}, $id, 'nfo');

	# Determine if we may or must rename
	my $rename = 0;
	if (exists($files->{$id})) {

		# Rename if we drift
		if (!$rename && $files->{$id}->{'path'}) {
			if (   $files->{$id}->{'number'} != $videos->{$id}->{'number'}
				|| $files->{$id}->{'season'} != $videos->{$id}->{'season'})
			{
				if ($DEBUG) {
					print STDERR "Rename due to drift\n";
				}
				$rename = 1;
			}
		}

		# Always rename if the NFO does not match the media
		if (!$rename && $files->{$id}->{'path'} && $files->{$id}->{'nfo'}) {
			my ($season, $number) = parseFilename($files->{$id}->{'nfo'});
			if ($files->{$id}->{'season'} != $season || $files->{$id}->{'number'} != $number) {
				if ($DEBUG) {
					print STDERR "Rename due to media-metadata mismatch\n";
				}
				$rename = 1;
			}
		}
	}

	# Warn (and optionally rename) as selected
	if ($rename) {
		print STDERR 'Video ' . $id . ' had number ' . $files->{$id}->{'number'} . ' but now has number ' . $videos->{$id}->{'number'} . "\n";
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
					print STDERR 'Reached fetch limit (' . $FETCH_LIMIT . ') for: ' . $ID . "\n";
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
					warn('Error executing youtube-dl for name: ' . $id . ' (' . $EXITVAL . ")\n");
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
	$elm->appendText(videoNumberStr($video->{'season'}, $video->{'number'}));
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

	if (defined($video->{'creator'})) {
		$elm = $doc->createElement('director');
		$elm->appendText($video->{'creator'});
		$show->appendChild($elm);
	}

	# Return the string
	return $doc->toString();
}

sub findFiles($) {
	my ($videos) = @_;
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
		my ($season, $number, $id, $suffix) = parseFilename($file);
		if (defined($id) && length($id) > 0) {

			# Create the record as needed
			if (!exists($files{$id})) {
				my %tmp = (
					'season' => $season,
					'number' => $number,
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
						my $del = $file;
						if (   exists($videos->{$id})
							&& $season == $videos->{$id}->{'season'}
							&& $number == $videos->{$id}->{'number'})
						{
							$del = $files{$id}->{'nfo'};
						}
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
						if (   exists($videos->{$id})
							&& $season == $videos->{$id}->{'season'}
							&& $number == $videos->{$id}->{'number'})
						{
							$del = $files{$id}->{'path'};
						} elsif ($suffix ne 'mp4' && $files{$id}->{'suffix'} eq 'mp4') {
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
	my ($name, $params) = @_;

	my $url = $API{$name}{'url'} . '?';
	foreach my $key (keys(%{ $API{$name}{'params'} }), keys(%{$params})) {
		$url .= '&' . uri_escape($key) . '=';
		if (exists($params->{$key})) {
			$url .= uri_escape($params->{$key});
		} else {
			$url .= uri_escape($API{$name}{'params'}{$key});
		}
	}

	# Fetch
	if ($DEBUG) {
		print STDERR 'Fetching ' . $name . ' API URL: ' . $url . "\n";
	}
	sleep($DELAY);
	my $content;
	if (fetch($url, \$content) != 200 || !defined($content) || length($content) < 10) {
		die('Invalid content from URL: ' . $url . "\n" . $content . "\n");
	}

	# Parse
	if ($DEBUG > 2) {
		print STDERR "Raw JSON data:\n" . $content . "\n";
	}
	my $data = decode_json($content);
	if (!defined($data) || ref($data) ne 'HASH') {
		die('Invalid JSON: ' . $content . "\n");
	}

	return $data;
}

sub getSubscriptions($$) {
	my ($user, $id) = @_;

	# Loop through until we have all the entries
	my $pageToken = '';
	my %subs      = ();
	SUBS_LOOP:
	{
		# Build, fetch, parse, check
		my $data = fetchParse('subscriptions', { 'channelId' => $id, 'pageToken' => $pageToken });
		$pageToken = '';
		if (   exists($data->{'pageInfo'})
			&& ref($data->{'pageInfo'}) eq 'HASH'
			&& exists($data->{'pageInfo'}->{'totalResults'})
			&& $data->{'pageInfo'}->{'totalResults'} > 0
			&& exists($data->{'pageInfo'}->{'resultsPerPage'})
			&& exists($data->{'items'})
			&& ref($data->{'items'}) eq 'ARRAY')
		{
			if (exists($data->{'nextPageToken'})) {
				$pageToken = $data->{'nextPageToken'};
			}
			$data = $data->{'items'};
		} else {
			die("Invalid subscription data\n");
		}

		foreach my $item (@{$data}) {
			if (  !exists($item->{'snippet'})
				|| ref($item->{'snippet'}) ne 'HASH'
				|| !exists($item->{'snippet'}->{'title'})
				|| !exists($item->{'snippet'}->{'resourceId'})
				|| ref($item->{'snippet'}->{'resourceId'}) ne 'HASH'
				|| !exists($item->{'snippet'}->{'resourceId'}->{'channelId'}))
			{
				warn("Skipping invalid subscription\n");
				if ($DEBUG > 2) {
					print STDERR prettyPrint($item, "\t") . "\n";
				}
				next;
			}
			if ($DEBUG) {
				print STDERR $item->{'snippet'}->{'title'} . ' => ' . $item->{'snippet'}->{'resourceId'}->{'channelId'} . "\n";
			}
			$subs{ $item->{'snippet'}->{'title'} . ' (' . $item->{'snippet'}->{'resourceId'}->{'channelId'} . ')' } = $user;
		}

		# Loop if there are results left to fetch
		if ($pageToken) {
			redo SUBS_LOOP;
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
			print STDERR 'Adding local subscription for: ' . $sub . ' => ' . $subs->{$sub} . "\n";
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
			my $jpg;
			if (fetch($channel->{'thumbnail'}, \$jpg) == 200) {
				saveString('poster.jpg', $jpg);
			}
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
	my ($id) = @_;

	# Build, fetch, parse, check
	my $data = fetchParse('channel', { 'id' => $id });
	if (   exists($data->{'pageInfo'})
		&& ref($data->{'pageInfo'}) eq 'HASH'
		&& exists($data->{'pageInfo'}->{'totalResults'})
		&& $data->{'pageInfo'}->{'totalResults'} == 1
		&& exists($data->{'items'})
		&& ref($data->{'items'}) eq 'ARRAY'
		&& scalar(@{ $data->{'items'} }) > 0
		&& ref($data->{'items'}[0]) eq 'HASH'
		&& exists($data->{'items'}[0]->{'snippet'})
		&& ref($data->{'items'}[0]->{'snippet'}) eq 'HASH')
	{
		$data = $data->{'items'}[0]->{'snippet'};
	} else {
		die("Invalid channel data\n");
	}

	# Extract the data we want
	my %channel = (
		'id'          => $id,
		'title'       => $data->{'title'},
		'date'        => str2time($data->{'publishedAt'}),
		'description' => $data->{'description'},
		'thumbnail'   => $data->{'thumbnails'}->{'high'}->{'url'},
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
			if ($_ =~ /^\s*([\w\-]+)\s*$/) {
				if ($DEBUG > 1) {
					print STDERR 'Adding extra video: ' . $1 . "\n";
				}
				$extras{$1} = 1;
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
	if (   !exists($data->{'id'})
		|| !exists($data->{'snippet'})
		|| ref($data->{'snippet'}) ne 'HASH'
		|| !exists($data->{'contentDetails'})
		|| ref($data->{'contentDetails'}) ne 'HASH'
		|| !exists($data->{'contentDetails'}->{'duration'}))
	{
		if ($DEBUG > 2) {
			print STDERR "Unable to parse video data:\n" . prettyPrint($data, "\t") . "\n";
		}
		return undef();
	}

	my %video = (
		'id'          => $data->{'id'},
		'title'       => $data->{'snippet'}->{'title'},
		'description' => $data->{'snippet'}->{'description'},
		'creator'     => $data->{'snippet'}->{'channelTitle'},
		'duration'    => $data->{'contentDetails'}->{'duration'},
	);

	$video{'date'} = str2time($data->{'snippet'}->{'publishedAt'});
	$video{'season'} = time2str('%Y', $video{'date'});
	if ($data->{'contentDetails'}->{'duration'} =~ /PT(\d+)M(\d+)/) {
		$video{'duration'} = ($1 * 60) + $2;
	} else {
		$video{'duration'} = $data->{'contentDetails'}->{'duration'};
	}

	return \%video;
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

		my $video = getVideoData($id);
		$videos->{$id} = $video->[0];
	}
	return $extras;
}

sub getVideoData($) {
	my ($ids) = @_;
	my @videos = ();

	# Do a batch request for the entire batch of video data
	my $data = fetchParse('video', { 'id' => join(',', @{$ids}) });
	if (   exists($data->{'pageInfo'})
		&& ref($data->{'pageInfo'}) eq 'HASH'
		&& exists($data->{'pageInfo'}->{'totalResults'})
		&& $data->{'pageInfo'}->{'totalResults'} > 0
		&& exists($data->{'items'})
		&& ref($data->{'items'}) eq 'ARRAY')
	{
		if ($data->{'pageInfo'}->{'totalResults'} != scalar(@{$ids})) {
			die('Video/metadata search count mismatch: ' . $data->{'pageInfo'}->{'totalResults'} . '/' . scalar(@{$ids}) . "\n");
		}
		$data = $data->{'items'};
	} else {
		die("Invalid search video data\n");
	}

	# Build each metadata record
	foreach my $item (@{$data}) {
		if (!exists($item->{'snippet'}) || ref($item->{'snippet'}) ne 'HASH') {
			warn("Skipping invalid metadata item\n");
			if ($DEBUG > 2) {
				print STDERR prettyPrint($item, "\t") . "\n";
			}
			next;
		}
		my $video = parseVideoData($item);
		if (!$video) {
			die("Unable to parse video data\n");
		}
		push(@videos, $video);
	}

	# Parse the video data
	return \@videos;
}

sub findVideos($) {
	my ($id) = @_;
	my %videos = ();

	# Allow complete bypass
	if ($NO_SEARCH) {
		return \%videos;
	}

	# Loop through until we have all the entries
	my $pageToken  = '';
	my $count      = 0;
	my $totalCount = 0;
	LOOP:
	{

		# Build, fetch, parse, check
		my $data = fetchParse('search', { 'channelId' => $id, 'pageToken' => $pageToken });
		$pageToken = '';
		if (   exists($data->{'pageInfo'})
			&& ref($data->{'pageInfo'}) eq 'HASH'
			&& exists($data->{'pageInfo'}->{'totalResults'})
			&& $data->{'pageInfo'}->{'totalResults'} > 0
			&& exists($data->{'pageInfo'}->{'resultsPerPage'})
			&& exists($data->{'items'})
			&& ref($data->{'items'}) eq 'ARRAY')
		{
			if (exists($data->{'nextPageToken'})) {
				$pageToken = $data->{'nextPageToken'};
			}
			if (!$totalCount) {
				$totalCount = $data->{'pageInfo'}->{'totalResults'};
			}
			$data = $data->{'items'};
		} else {
			die("Invalid search data\n");
		}

		# Grab each video ID
		my @ids = ();
		foreach my $item (@{$data}) {
			if (!exists($item->{'id'}) || ref($item->{'id'}) ne 'HASH' || !exists($item->{'id'}->{'videoId'})) {
				warn("Skipping invalid video item\n");
				if ($DEBUG > 2) {
					print STDERR prettyPrint($data, "\t") . "\n";
				}
				next;
			}
			push(@ids, $item->{'id'}->{'videoId'});
		}

		# Do a batch request for the entire batch of video data
		my $records = getVideoData(\@ids);
		foreach my $rec (@{$records}) {
			$videos{ $rec->{'id'} } = $rec;
		}

		# Loop if there are results left to fetch
		if ($totalCount > $count && $count <= $MAX_INDEX && $pageToken) {
			redo LOOP;
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

sub videoNumberStr($$) {
	my ($season, $episode) = @_;
	my $str = '';

	if ($season == 0 && $episode =~ /^(20[012]\d)(\d{2,4})$/) {
		$str = sprintf('%04d%04d', $1, $2);
	} else {
		$str = sprintf('%02d', $episode);
	}

	return $str;
}

sub videoSE($$) {
	my ($season, $episode) = @_;
	return sprintf('S%0dE%s - ', $season, videoNumberStr($season, $episode));
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

# GET the requested URL, accepting encoded data and extracting the HTTP status code
sub fetch($$) {
	my ($url, $data) = @_;

	# Init the global LWP as needed
	if (!defined($LWP)) {
		$LWP = new LWP::UserAgent;
		$LWP->agent($HTTP_UA);
		$LWP->timeout($HTTP_TIMEOUT);
		$LWP->ssl_opts({ 'verify_hostname' => $HTTP_VERIFY });
	}

	# Make a request
	my $request = HTTP::Request->new('GET' => $url);
	$request->header('Accept-Encoding' => HTTP::Message::decodable);
	my $response = $LWP->request($request);

	# Do something useful with the response
	my $code = 400;
	if ($response->status_line =~ /^(\d+)\s/) {
		$code = $1;
	}
	${$data} = $response->decoded_content();
	return $code;
}
