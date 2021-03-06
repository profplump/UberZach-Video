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
use Cwd qw( abs_path );
use PrettyPrint;

# Paramters
my %USERS         = ('profplump' => 'UCkj-Ob6eYHvzo-P0UWfnQzA', 'shanda' => 'UChfwMHzkPXOOFDce5hyQkTA');
my $EXTRAS_FILE   = 'extra_videos.ini';
my $EXCLUDES_FILE = 'exclude_videos.ini';
my $YTDL_BIN      = $ENV{'HOME'} . '/bin/video/yt/youtube-dl';
my @YTDL_ARGS     = ('--force-ipv4', '--socket-timeout', '10', '--retries', '1', 
			'--no-playlist', '--max-downloads', '1', '--age-limit', '99');
my @YTDL_QUIET    = ('--quiet', '--no-warnings');
my @YTDL_DEBUG    = ('--verbose');
my $CHATTR        = '/usr/bin/chattr';
my $BATCH_SIZE    = int(rand(32));
my $MAX_INDEX     = 25000;
my $FETCH_LIMIT   = 50;
my $DELAY         = 5;
my $MIN_DELAY     = 0.75;
my $FORK_DELAY    = 5;
my $HTTP_TIMEOUT  = 12;
my $HTTP_UA       = 'ZachBot/1.1 (Firewall)';
my $HTTP_VERIFY   = 0;
my $API_HTML      = $ENV{'API_HTML'};
my $API_URL       = 'https://www.googleapis.com/youtube/v3/';
my $API_KEY       = $ENV{'YT_API_KEY'};
my $API_ST_REL    = 0.50;
my $API_ST_ABS    = 5;
my %VIDEO_FIELDS  = (
	'id'          => '',
	'title'       => '',
	'description' => '',
	'creator'     => '',
	'publishedAt' => '',
	'channelId'   => '',
	'rawDuration' => '',
	'date',       => 0,
	'season'      => 0,
	'duration'    => 0,
);
my %API = (

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
			'type'       => 'video',
			'order'      => 'date',
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
sub localMetadata($$);
sub findVideos($);
sub findFiles($);
sub buildNFO($);
sub buildSeriesNFO($);
sub getSubscriptions($);
sub saveSubscriptions($$);
sub saveChannel($);
sub getChannel($);
sub fetchParse($$);
sub saveString($$);
sub readExcludes();
sub readExtras();
sub parseVideoData($);
sub calcVideoData($);
sub dropExcludes($);
sub addExtras($);
sub updateNFOData($$$);
sub videoNumberStr($$);
sub videoSE($$);
sub videoPath($$$$);
sub renameVideo($$$$$$);
sub parseFilename($);
sub fetch($$);
sub delay(;$);

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	if ($ENV{'DEBUG'} =~ /(\d+)/) {
		$DEBUG = $1;
	} else {
		$DEBUG = 1;
	}
	$DELAY = 0;
}

# Sanity check
if (scalar(@ARGV) < 1) {
	die('Usage: ' . basename($0) . " output_directory\n");
}
if (!defined($API_KEY) || length($API_KEY) < 1) {
	die("No API key provided\n");
}
my $SUBSCRIPTIONS = 0;
if ($0 =~ /subscription/i) {
	$SUBSCRIPTIONS = 1;
}

# Command-line parameters
our ($DIR) = @ARGV;
$DIR = Cwd::abs_path($DIR);
$DIR =~ s/\/+$//;
if (!-d $DIR) {
	die('Invalid output directory: ' . $DIR . "\n");
}
our $NAME = basename($DIR);
our $ID   = $NAME;
if ($NAME =~ /^(.*)\s\(([\w\-]+)\)$/) {
	$NAME = $1;
	$ID   = $2;
	if (length($ID) < 1 || !($ID =~ /^[\w\-]+$/)) {
		die('Invalid channel ID: ' . $ID . "\n");
	}
} elsif (!$SUBSCRIPTIONS) {
	die('Invalid folder: ' . $DIR . "\n");
}

# Allow folders to disable themselves
if (-e "${DIR}/season_done") {
	if ($DEBUG) {
		print STDERR "Folder disabled. Exiting...\n";
	}
	exit(0);
}

# Move to the target directory so we can use relative paths later
chdir($DIR) or die('Unable to chdir to: ' . $DIR . "\n");

# Environmental parameters (debug)
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
if ($ENV{'NO_CHATTR'} || !can_run('sudo') || !can_run($CHATTR)) {
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
if ($SUBSCRIPTIONS) {
	my %subs = ();
	foreach my $user (keys(%USERS)) {
		my $tmp = getSubscriptions($USERS{$user});
		foreach my $sub (keys(%{$tmp})) {
			$subs{$sub} = $tmp->{$sub};
		}
	}
	saveSubscriptions($DIR, \%subs);
	exit(0);
}

# Disable channel fetching if the ID channel is "None"
if ($ID =~ /^\s*None\s*$/i) {
	if ($DEBUG) {
		print STDERR 'Channel features disabled for: ' . $NAME . "\n";
	}
	$NO_CHANNEL = 1;
	$NO_SEARCH  = 1;
}

# Run the local "update" script if any
{
	my @update = ('./update', $DIR);
	if (can_run($update[0])) {
		if ($DEBUG) {
			print STDERR "Executing local update script...\n";
		}
		system(@update);
	}
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

# Find all existing YT files on disk
my $files = {};
if (!$NO_FILES) {
	$files = findFiles($videos);
}

# Deal with unknown videos
foreach my $id (keys(%{$files})) {
	if ((!exists($videos->{$id}) || !$videos->{$id}->{'date'}) && $files->{$id}->{'season'} > 0) {

		# Check the ID specifically to find things the APIv3 fuzzy search misses
		if ($DEBUG) {
			print STDERR 'Validating local video by ID: ' . $id . "\n";
		}
		my $video = getVideoData([$id]);
		if ($video->[0] && $video->[0]->{'season'} > 0 && $video->[0]->{'channelId'} eq $ID) {
			$videos->{$id} = $video->[0];
			next;
		}

		# Whine when videos do go away
		if ($DEBUG) {
			warn('Local video not known to YT channel (' . $NAME . '): ' . $id . "\n");
		}
		renameVideo($files->{$id}->{'path'}, $files->{$id}->{'suffix'}, $files->{$id}->{'nfo'}, $id, 0, $files->{$id}->{'season'} . $files->{$id}->{'number'});
	}
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

# HTML output
if ($API_HTML) {
	my $html = undef();
	my $hdate = time() - (86400 * 28);
	open($html, '>', $API_HTML) or warn('Could not open file "' . $API_HTML . '": ' . $!);
	if (!$html) {
		goto END_HTML;
	}

	print $html '<html><head><title>' . $NAME . '(' . $ID . ')' . '</title></head>' . "\n";
	print $html '<body><form method="post" action="https://firewall.local/yt/update.py">' . "\n";
	print $html '<h1>' . $NAME . '</h1><table>' . "\n";

	my @byDate = sort { $videos->{$b}->{'date'} <=> $videos->{$a}->{'date'} || $a cmp $b } keys %{$videos};
	foreach my $id (@byDate) {
		my $val = 'Block';
		if ($videos->{$id}->{'date'} > $hdate) {
			$val = 'Allow';
		}
		print $html '<tr>';
		print $html '<td>' . time2str('%Y-%m-%d', $videos->{$id}->{'date'}) . '</td>';
		print $html '<td><a target="_blank" rel="noopener" href="https://www.youtube.com/watch?v='
			. $id . '">' . $videos->{$id}->{'title'} . '</a></td>';
		print $html '<td><input type="submit" name="ytid|' . $id . '" value="' . $val . '" /></td>';
		print $html "</tr>\n";
	}

	print $html '</table></form></body></html>' . "\n";
	close($html);
	END_HTML:
}

# Fill in missing videos and NFOs
my $fetched = 0;
FETCH_LOOP: foreach my $id (keys(%{$videos})) {
	if ($DEBUG > 1) {
		print STDERR 'Checking remote video: ' . $id . "\n";
		if (!exists($files->{$id})) {
			print STDERR "\tLocal file: <missing>\n";
		} else {
			print STDERR "\tLocal media: " . $files->{$id}->{'path'} . "\n";
			print STDERR "\tLocal NFO: ";
			if ($files->{$id}->{'nfo'}) {
				print STDERR $files->{$id}->{'nfo'} . "\n";
			} else {
				print STDERR "<none>\n";
			}
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
		if ($DEBUG) {
			warn('Video ' . $id . ' had number ' . $files->{$id}->{'number'} . ' but now has number ' . $videos->{$id}->{'number'} . "\n");
		}
		renameVideo($files->{$id}->{'path'}, $files->{$id}->{'suffix'}, $files->{$id}->{'nfo'}, $id, $videos->{$id}->{'season'}, $videos->{$id}->{'number'});
	}

	# If we haven't heard of the file, or don't have an NFO for it
	# Checking for the NFO allows us to resume in-process failures
	if (!exists($files->{$id}) || !-e $nfo) {
		if ($DEBUG) {
			print STDERR 'Fetching video: ' . $id . "\n";
		}

		# Mark the video as reviewed
		{
			my $reviewed = videoSE($videos->{$id}->{'season'}, $videos->{$id}->{'number'}) . $id . '.reviewed';
			touch($reviewed);
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
					print STDERR 'Reached fetch limit (' . $FETCH_LIMIT . ') for: ' . $NAME . "\n";
					if ($DEBUG) {
						print STDERR "\tLocal/Remote videos at start:" . scalar(keys(%{$files})) . '/' . scalar(keys(%{$videos})) . "\n";
					}
					exit 1;
				}

				# Find the output file name
				if ($DEBUG > 1) {
					print STDERR join(' ', @name) . "\n";
				}
				delay();
				my $file = capture(EXIT_ANY, @name);
				if ($EXITVAL != 0) {
					warn('Error executing youtube-dl for name: ' . $NAME . '/' . $id . ' (' . $EXITVAL . ")\n");
					next FETCH_LOOP;
				}
				if ($file =~ /\n\S/) {
					$file =~ s/^.*\n//;
				}
				$file =~ s/^\s+//;
				$file =~ s/\s+$//;

				# Sanity check
				if (!$file) {
					warn('No file name available for video: ' . $NAME . '/' . $id . "\n");
					next FETCH_LOOP;
				} elsif ($DEBUG > 0) {
					print STDERR 'Output video file: ' . $file . "\n";
				}

				# Download
				if ($DEBUG > 1) {
					print STDERR join(' ', @fetch) . "\n";
				}
				delay();
				my $exit = run(EXIT_ANY, @fetch);
				if ($exit != 0) {
					if ($DEBUG) {
						warn('Error executing youtube-dl for video: ' . $NAME . '/' . $id . "\n");
					}
					next FETCH_LOOP;
				}

				# Ensure we found something useful
				if (-e $file . '.part') {
					warn('Partial download detected: ' . $NAME . '/' . $file . "\n");
					next FETCH_LOOP;
				}
				# Sometimes the downloader lies about file extensions
				if (!-s $file) {
					$file =~ s/\.webm$/.mp4/;
				}
				if (!-s $file) {
					$file =~ s/\.mp4$/.webm/;
				}
				# But we still need *a* file
				if (!-s $file) {
					warn('No output video file: ' . $NAME . '/' . $file . "\n");
					next FETCH_LOOP;
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
	our $NAME;

	# Allow complete bypass
	if ($NO_FILES) {
		return \%files;
	}

	# Read the output directory
	my $fh = undef();
	opendir($fh, '.')
	  or die($NAME . ': Unable to open files directory: ' . $! . "\n");
	while (my $file = readdir($fh)) {
		my ($season, $number, $id, $suffix) = parseFilename($file);
		if (defined($id) && length($id) > 0) {

			# Determine if there is another video with the same season/number
			my $exists = 0;
			if (   exists($videos->{$id})
				&& exists($videos->{$id}->{'season'})
				&& exists($videos->{$id}->{'number'})
				&& $season == $videos->{$id}->{'season'}
				&& $number == $videos->{$id}->{'number'})
			{
				$exists = 1;
			}

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
						if ($exists) {
							$del = $files{$id}->{'nfo'};
						}
						warn("\tDeleting: " . $file . "\n");
						if ($SUDO_CHATTR) {
							system('sudo', $CHATTR, '-i', Cwd::abs_path($file));
						}
						unlink($file);
						next;
					}
				} else {
					warn('Duplicate video: ' . $id . "\n\t" . $files{$id}->{'path'} . "\n\t" . $file . "\n");
					if (!$NO_RENAME) {
						my $del = $file;
						if ($exists) {
							$del = $files{$id}->{'path'};
						} elsif ($suffix ne 'mp4' && $files{$id}->{'suffix'} eq 'mp4') {
							$del = $files{$id}->{'path'};
						} elsif ($suffix ne 'webm' && $files{$id}->{'suffix'} eq 'webm') {
							$del = $files{$id}->{'path'};
						}
						warn("\tDeleting: " . $del . "\n");
						if ($SUDO_CHATTR) {
							system('sudo', $CHATTR, '-i', Cwd::abs_path($del));
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
	our $NAME;

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
	if ($DEBUG > 1) {
		print STDERR 'Fetching ' . $name . ' API URL: ' . $url . "\n";
	}
	delay();
	my $content;
	my $code = fetch($url, \$content);
	if ($code != 200 || !defined($content) || length($content) < 10) {
		my $msg = $NAME . ': Invalid content from URL (' . $code . '): ' . $url . "\n" . $content . "\n";
		if ($code >= 500 && $code < 600) {
			if ($DEBUG) {
				print STDERR $msg;
			}
			exit(0);
		}

		if ($code >= 400 && $code < 500) {
			if ($DEBUG) {
				print STDERR "Waiting 30 seconds after 400 error\n";
			}
			delay(30);
		}
		die($msg);
	}

	# Parse
	if ($DEBUG > 2) {
		print STDERR "Raw JSON data:\n" . $content . "\n";
	}
	my $data = decode_json($content);
	if (!defined($data) || ref($data) ne 'HASH') {
		die($NAME . ': Invalid JSON: ' . $content . "\n");
	}

	return $data;
}

sub getSubscriptions($) {
	my ($id) = @_;
	our $NAME;

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
			die($NAME . ": Invalid subscription data\n");
		}

		foreach my $item (@{$data}) {
			if (  !exists($item->{'snippet'})
				|| ref($item->{'snippet'}) ne 'HASH'
				|| !exists($item->{'snippet'}->{'title'})
				|| !exists($item->{'snippet'}->{'resourceId'})
				|| ref($item->{'snippet'}->{'resourceId'}) ne 'HASH'
				|| !exists($item->{'snippet'}->{'resourceId'}->{'channelId'}))
			{
				if ($DEBUG > 2) {
					warn($NAME . ": Skipping invalid subscription\n");
					print STDERR prettyPrint($item, "\t") . "\n";
				}
				next;
			}
			if ($DEBUG) {
				print STDERR $item->{'snippet'}->{'title'} . ' => ' . $item->{'snippet'}->{'resourceId'}->{'channelId'} . "\n";
			}
			$subs{ $item->{'snippet'}->{'resourceId'}->{'channelId'} } = $item->{'snippet'}->{'title'};
		}

		# Loop if there are results left to fetch
		if ($pageToken) {
			redo SUBS_LOOP;
		}
	}

	# Return the list of subscribed channel IDs
	return \%subs;
}

sub saveSubscriptions($$) {
	my ($folder, $subs) = @_;
	our $NAME;

	# Check for local subscriptions missing from YT
	my %locals = ();
	my $fh     = undef();
	opendir($fh, '.')
	  or die($NAME . ': Unable to open subscriptions directory: ' . $folder . ': ' . $! . "\n");
	while (my $file = readdir($fh)) {

		# Skip dotfiles
		if ($file =~ /^\./) {
			next;
		}

		# Skip non-directories
		if (!-d $file) {
			next;
		}

		# Extract the YTID
		my ($id) = $file =~ /\(([\w\-]+)\)$/;
		if (!$id) {
			warn('Skipping invalid local subscription: ' . $file . "\n");
			next;
		}

		# Skip "None" directories (i.e. non-channel subscriptions)
		if ($id eq 'None') {
			if ($DEBUG) {
				print STDERR 'Ignoring non-channel subscription: ' . $file . "\n";
			}
			next;
		}

		# Skip the weird dual Ask a Ninja thing, which vascilates
		if ($id eq 'UCpYQ53cR1p2VzFijrXYz4WQ') {
			if ($DEBUG) {
				print STDERR 'Ignoring weird Ask a Ninja subscription: ' . $file . "\n";
			}
			next;
		}

		# Anything else should be in the list
		if (!$subs->{$id}) {
			my (undef(), undef(), $hour) = localtime(time);
			if ($hour == 0 || $DEBUG) {
				print STDERR 'Missing YT subscription for: ' . $file . "\n";
			}
		}

		# Note local subscriptions
		$locals{$id} = 1;
	}
	closedir($fh);

	# Check for YT subscriptions missing locally
	foreach my $id (keys(%{$subs})) {
		if (!exists($locals{$id})) {
			my $dir = $subs->{$id} . ' (' . $id . ')';
			print STDERR 'Adding local subscription for: ' . $dir . "\n";
			mkdir($folder . '/' . $dir);
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
	our $NAME;

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
		die($NAME . ": Invalid channel data\n");
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
	our $NAME;

	# Read and parse the excludes videos file, if it exists
	if (-e $EXCLUDES_FILE) {
		my $fh;
		open($fh, $EXCLUDES_FILE)
		  or die($NAME . ': Unable to open excludes videos file: ' . $! . "\n");
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
	our $NAME;

	# Read and parse the extra videos file, if it exists
	if (-e $EXTRAS_FILE) {
		my $fh;
		open($fh, $EXTRAS_FILE)
		  or die($NAME . ': Unable to open extra videos file: ' . $! . "\n");
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
	my %video = %VIDEO_FIELDS;

	# Sanity check
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

	# Direct extraction
	$video{'id'}          = $data->{'id'};
	$video{'title'}       = $data->{'snippet'}->{'title'};
	$video{'description'} = $data->{'snippet'}->{'description'};
	$video{'creator'}     = $data->{'snippet'}->{'channelTitle'};
	$video{'publishedAt'} = $data->{'snippet'}->{'publishedAt'};
	$video{'channelId'}   = $data->{'snippet'}->{'channelId'};
	$video{'rawDuration'} = $data->{'contentDetails'}->{'duration'};

	# Convert dates and whatnot
	calcVideoData(\%video);

	return \%video;
}

sub calcVideoData($) {
	my ($video) = @_;

	if ($video->{'publishedAt'} && !$video->{'date'}) {
		$video->{'date'} = str2time($video->{'publishedAt'});
	}
	if ($video->{'date'}) {
		$video->{'season'} = time2str('%Y', $video->{'date'});
	} else {
		$video->{'season'} = 0;
	}
	if ($video->{'rawDuration'} =~ /PT(\d+)H(\d+)M(\d+)S/) {
		$video->{'duration'} = ($1 * 3600) + ($2 * 60) + $2;
	} elsif ($video->{'rawDuration'} =~ /PT(\d+)M(\d+)S/) {
		$video->{'duration'} = ($1 * 60) + $2;
	} elsif ($video->{'rawDuration'} =~ /PT(\d+)S/) {
		$video->{'duration'} = $1;
	}
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

		my $video = getVideoData([$id]);
		$videos->{$id} = $video->[0];
	}
	return $extras;
}

sub getVideoData($) {
	my ($ids) = @_;
	my @videos = ();
	our $NAME;
	my %found = ();

	# Do a batch request for the entire batch of video data
	my $data = fetchParse('video', { 'id' => join(',', @{$ids}) });
	if (   exists($data->{'pageInfo'})
		&& ref($data->{'pageInfo'}) eq 'HASH'
		&& exists($data->{'pageInfo'}->{'totalResults'})
		&& exists($data->{'items'})
		&& ref($data->{'items'}) eq 'ARRAY')
	{
		if (scalar(@{$ids}) > 1 && $data->{'pageInfo'}->{'totalResults'} != scalar(@{$ids})) {
			if ($DEBUG) {
				die($NAME . ': Video/metadata search count mismatch: ' . $data->{'pageInfo'}->{'totalResults'} . '/' . scalar(@{$ids}) . "\n");
			}
			exit(0);
		}
		$data = $data->{'items'};
	} else {
		die($NAME . ": Invalid search video data\n" . prettyPrint($data, "\t") . "\n");
	}

	# Build each metadata record
	foreach my $item (@{$data}) {
		if (!exists($item->{'snippet'}) || ref($item->{'snippet'}) ne 'HASH') {
			warn($NAME . ": Skipping invalid metadata item\n");
			if ($DEBUG > 2) {
				print STDERR prettyPrint($item, "\t") . "\n";
			}
			next;
		}
		my $video = parseVideoData($item);
		if (!$video) {
			die($NAME . ": Unable to parse video data\n");
		}

		# Allow local metadata overrides
		localMetadata($video->{'id'}, $video);

		# Save
		$found{ $video->{'id'} } = 1;
		push(@videos, $video);
	}

	# Load local metadata even for videos YT doesn't know anything about
	foreach my $id (@{$ids}) {
		if ($found{$id}) {
			next;
		}

		my %video = %VIDEO_FIELDS;
		$video{'id'} = $id;
		localMetadata($id, \%video);

		# Save
		$found{$id} = 1;
		push(@videos, \%video);
	}

	# Parse the video data
	return \@videos;
}

sub localMetadata($$) {
	my ($id, $video) = @_;
	my $meta = $id . '.meta';
	if (!-r $meta) {
		return;
	}
	my $fh = undef();
	open($fh, '<', $meta)
	  or warn('Unable to open local metadata file: ' . $meta . ': ' . $! . ". Skipping...\n");
	while (<$fh>) {
		if (/^\s*#/ || /^\s*$/) {
			next;
		}
		if (/^\s*([^\s\=][^\=]*[^\s\=])\s*=\>?\s*(\S.*\S)\s*$/) {
			if (exists($video->{$1})) {
				if ($DEBUG) {
					print STDERR 'Using local metadata line (' . $id . '): ' . $1 . ' => ' . $2 . "\n";
				}
				$video->{$1} = $2;
			} else {
				die('Invalid local metadata attribute (' . $1 . '): ' . $meta . "\n");
			}
		} else {
			die('Invalid local metdata line (' . $meta . '): ' . chomp($_) . "\n");
		}
	}
	close($fh);
	calcVideoData($video);
}

sub findVideos($) {
	my ($id) = @_;
	my %videos = ();
	our $NAME;

	# Allow complete bypass
	if ($NO_SEARCH) {
		return \%videos;
	}

	# Loop through until we have all the entries
	my $totalCount = 0;
	my %params = ('channelId' => $id);
	LOOP:
	{
		# Loop status
		my $count = scalar(keys(%videos));
		if ($DEBUG && $totalCount) {
			my $date = $params{'publishedBefore'};
			$date =~ s/T.*$//;
			print STDERR 'Fetching ' . $count . ' of ' . $totalCount .
				"\t" . $date .
				"\t(" . int(100 * $count / $totalCount) . "%)\n";
		}

		# Build, fetch, parse, check
		my $data = fetchParse('search', \%params);
		delete($params{'pageToken'});
		if (   exists($data->{'pageInfo'})
			&& ref($data->{'pageInfo'}) eq 'HASH'
			&& exists($data->{'pageInfo'}->{'totalResults'})
			&& exists($data->{'pageInfo'}->{'resultsPerPage'})
			&& exists($data->{'items'})
			&& ref($data->{'items'}) eq 'ARRAY')
		{
			if (!$totalCount) {
				$totalCount = $data->{'pageInfo'}->{'totalResults'};
			}
			$data = $data->{'items'};
		} else {
			die($NAME . ": Invalid search data\n");
		}

		# Sanity check
		if (scalar(@{$data}) < 1) {
			last LOOP;
		}

		# Grab each video ID
		my @ids = ();
		foreach my $item (@{$data}) {
			if (!exists($item->{'id'}) || ref($item->{'id'}) ne 'HASH' || !exists($item->{'id'}->{'videoId'})) {
				warn($NAME . ": Skipping invalid video item\n");
				if ($DEBUG > 2) {
					print STDERR prettyPrint($data, "\t") . "\n";
				}
				next;
			}
			push(@ids, $item->{'id'}->{'videoId'});
		}

		# Do a batch request for the entire batch of video data
		my $more    = 0;
		my $records = getVideoData(\@ids);
		foreach my $rec (@{$records}) {
			if (exists($rec->{'duration'}) && $rec->{'duration'} == 0) {
				if ($DEBUG > 1) {
					print STDERR 'Skipping 0-length video: ' . $rec->{'id'} . "\n";
				}
				next;
			}
			$videos{ $rec->{'id'} } = $rec;
			if (!defined($params{'publishedBefore'}) || (defined($rec->{'publishedAt'}) && ($rec->{'publishedAt'} cmp $params{'publishedBefore'}) < 0)) {
				$params{'publishedBefore'} = $rec->{'publishedAt'};
				$more = 1;
			}
		}

		# Loop if there are results left to fetch
		if ($DEBUG > 1) {
			print STDERR "more \t => ${more}\n";
			print STDERR "count \t => ${count}\n";
		}
		if ($more && $params{'publishedBefore'} && $count <= $MAX_INDEX) {
			redo LOOP;
		}
	}

	# Sanity check/debug
	{
		my $count = scalar(keys(%videos));
		if ($DEBUG) {
			print STDERR 'Found ' . $count . " remote videos\n";
			if (abs(1 - ($count / $totalCount)) > $API_ST_REL && abs($totalCount - $count) > $API_ST_ABS) {
				print STDERR 'Found only ' . $count . ' of ' . $totalCount . ' (' . int(100 * $count / $totalCount) . "%) channel-API-reported remote videos.\n";
			}
			if ($DEBUG > 1) {
				print STDERR prettyPrint(\%videos, "\t") . "\n";
			}
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
	our $NAME;

	# Bail if disabled
	if ($NO_RENAME) {
		print STDERR 'Not renaming: ' . $video . "\n";
		return;
	}

	# General sanity checks
	if (!defined($id) || !defined($season) || !defined($episode)) {
		die($NAME . ": Invalid call to renameVideo()\n\t" . $video . "\n\t" . $suffix . "\n\t" . $nfo . "\n\t" . $id . "\n\t" . $season . "\n\t" . $episode . "\n");
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
			die($NAME . ': Invalid video source in rename: ' . $video . "\n");
		}
		if ($video ne $videoNew) {
			if ($DEBUG) {
				warn('Renaming ' . $NAME . '/' . $video . ' => ' . $videoNew . "\n");
			}
			if (-e $videoNew) {
				die($NAME . ': Rename: Target exists: ' . $videoNew . "\n");
			}
			if ($SUDO_CHATTR) {
				system('sudo', $CHATTR, '-i', Cwd::abs_path($video));
			}
			rename($video, $videoNew)
			  or die($NAME . ': Unable to rename: ' . $video . ': ' . $! . "\n");
		}
	}

	# NFO
	if (defined($nfo)) {
		my $nfoNew = videoPath($season, $episode, $id, 'nfo');

		# Sanity checks, as we do dangerous work here
		if (!-r $nfo) {
			die($NAME . ': Invalid NFO source in rename: ' . $nfo . "\n");
		}

		# Parse old NFO data
		my $nfoData = updateNFOData($nfo, $season, $episode)
		  or die($NAME . ': No NFO data found, refusing to rename: ' . $id . "\n");

		# Write a new NFO and unlink the old one
		if ($SUDO_CHATTR) {
			system('sudo', $CHATTR, '-i', Cwd::abs_path($nfo));
		}
		saveString($nfoNew, $nfoData);
		if ($nfo ne $nfoNew) {
			if ($DEBUG) {
				warn('Renaming ' . $NAME . '/' . $nfo . ' => ' . $nfoNew . "\n");
			}
			unlink($nfo)
			  or warn('Unable to delete NFO during rename: ' . $! . "\n");
		}
	}
}

sub parseFilename($) {
	my ($file) = @_;
	return $file =~ /^S(\d+)+E(\d+) - ([\w\-]+)(?:\-recode)?\.(\w\w\w)$/i;
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

# Inter-operation delay
sub delay(;$) {
	my $retval = 0;
	my ($extra) = ($@);
	if (!Scalar::Util::looks_like_number($extra)) {
		$extra = 0;
	}

	my $sleep = rand($DELAY) + $MIN_DELAY + $extra;
	if ($sleep > $FORK_DELAY) {
		# Fork, signal the loop to exit in the child, and resume the parent
		$retval = 1;
	}

	sleep($sleep);
	return($retval);
}
