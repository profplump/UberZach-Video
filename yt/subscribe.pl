#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/";

use File::Basename;
use Date::Parse;
use Date::Format;
use LWP::Simple;
use URI::Escape;
use JSON;
use XML::LibXML;
use IPC::System::Simple qw( system );
use WWW::YouTube::Download;
use PrettyPrint;

# Paramters
my $EXTRAS_FILE     = 'extra_videos.ini';
my $EXCLUDES_FILE   = 'exclude_videos.ini';
my $CURL_BIN        = 'curl';
my @CURL_ARGS       = ('-4', '--insecure', '-C', '-', '--connect-timeout', '10', '--max-time', '600');
my $BATCH_SIZE      = 50;
my $MAX_INDEX       = 2500;
my $DRIFT_TOLERANCE = 2;
my $DRIFT_FACTOR    = 100.0;
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
sub findFiles($);
sub findVideo($);
sub ytURL($);
sub buildNFO($);
sub buildSeriesNFO($);
sub getChannel($);
sub fetchParse($$);
sub saveString($$);
sub readExcludes($);
sub readExtras($);
sub parseVideoData($);
sub dropExcludes($$);
sub addExtras($$);
sub saveChannel($$);

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

# Environmental parameters (functional)
my $RENAME = 0;
if ($ENV{'RENAME'}) {
	$RENAME = 1;
}
if ($ENV{'MAX_INDEX'} && $ENV{'MAX_INDEX'} =~ /(\d+)/) {
	$MAX_INDEX = $1;
}
if ($ENV{'BATCH_SIZE'} && $ENV{'BATCH_SIZE'} =~ /(\d+)/) {
	$BATCH_SIZE = $1;
}

# Construct globals
$API{'search'}{'params'}{'max-results'} = $BATCH_SIZE;
if (!$DEBUG) {
	push(@CURL_ARGS, '--silent');
}

# Grab the channel data
my $channel = {};
if (!$NO_CHANNEL) {
	$channel = getChannel($user);
	saveChannel($dir, $channel);
}

# Find all the user's videos on YT
my $videos = {};
if (!$NO_SEARCH) {
	$videos = findVideos($user);
}

# Find any requested "extra" videos
my $extras = {};
if (!$NO_EXTRAS) {
	$extras = addExtras($dir, $videos);
}

# Drop any "excludes" videos
my $excludes = {};
if (!$NO_EXCLUDES) {
	$excludes = dropExcludes($dir, $videos);
}

# Find all existing YT files on disk
my $files = {};
if (!$NO_FILES) {
	$files = findFiles($dir);
}

# Fill in missing videos and NFOs
foreach my $id (keys(%{$videos})) {
	my $basePath = $dir . '/S01E' . sprintf('%02d', $videos->{$id}->{'number'}) . ' - ' . $id . '.';
	my $nfo = $basePath . 'nfo';

	# Warn (and optionally rename) if the video numbers drift
	if (exists($files->{$id}) && $files->{$id}->{'number'} != $videos->{$id}->{'number'}) {
		if ($RENAME) {
			print STDERR 'Renaming ' . $files->{$id}->{'path'} . ' => ' . $basePath . $files->{$id}->{'suffix'} . "\n";
			rename($files->{$id}->{'path'}, $basePath . $files->{$id}->{'suffix'});
			rename($files->{$id}->{'nfo'},  $nfo);
		} else {

			# Find the old NFO to avoid re-fetching
			$nfo = $files->{$id}->{'nfo'};

			# Ignore small changes
			my $delta     = abs($files->{$id}->{'number'} - $videos->{$id}->{'number'});
			my $tolerance = $files->{$id}->{'number'} / $DRIFT_FACTOR;
			if ($tolerance < $DRIFT_TOLERANCE) {
				$tolerance = $DRIFT_TOLERANCE;
			}
			if ($delta > $tolerance || $DEBUG) {
				print STDERR 'Video ' . $id . ' had video number ' . $files->{$id}->{'number'} . ' but now has video number ' . $videos->{$id}->{'number'} . "\n";
			}
		}
	}

	# If we haven't heard of the file, or don't have an NFO for it
	# Checking for the NFO allows use to resume failed downloads
	if (!exists($files->{$id}) || !-e $nfo) {
		if ($DEBUG) {
			print STDERR 'Fetching video: ' . $id . "\n";
		}

		# Find the download URL and file suffix
		my ($url, $suffix) = ytURL($id);
		if (!defined($url) || length($url) < 5) {
			warn('Could not determine URL for video: ' . $id . "\n");
			$url = undef();
		}

		# Fetch with cURL
		# I know LWP exists (and is even loaded) but cURL makes my life easier
		if ($url) {
			my @cmd = ($CURL_BIN);
			push(@cmd, @CURL_ARGS);
			push(@cmd, '-o', $basePath . $suffix, $url);
			if ($NO_FETCH) {
				print STDERR 'Not running: ' . join(' ', @cmd) . "\n";
			} else {
				if ($DEBUG > 1) {
					print STDERR join(' ', @cmd) . "\n";
				}
				system(@cmd);
			}
		}

		# Build and save the XML document
		my $xml = buildNFO($videos->{$id});
		if ($DEBUG > 1) {
			print STDERR 'Saving NFO: ' . $xml . "\n";
		}
		if ($NO_FETCH) {
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
		warn('Cannot open file for writing: ' . $! . "\n");
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
	my $elm;

	# Add data
	$elm = $doc->createElement('season');
	$elm->appendText('1');
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

sub ytURL($) {
	my ($id) = @_;

	# Init the YT object
	my $tube = WWW::YouTube::Download->new;

	# Fetch metadata
	my $meta = eval { $tube->prepare_download($id); };
	if (!defined($meta) || ref($meta) ne 'HASH' || !exists($meta->{'video_url_map'}) || ref($meta->{'video_url_map'}) ne 'HASH') {
		if ($@ =~ /age gate/i) {
			print STDERR "Video not available due to age gate restrictions\n";
		}
		return undef();
	}

	# Find the best stream (i.e. highest resolution, prefer mp4)
	my $bestStream     = undef();
	my $bestResolution = 0;
	foreach my $streamID (keys(%{ $meta->{'video_url_map'} })) {
		my $stream = $meta->{'video_url_map'}->{$streamID};
		my ($res) = $stream->{'resolution'} =~ /^\s*(\d+)/;
		if ($DEBUG > 1) {
			print STDERR $streamID . ' (' . $stream->{'suffix'} . ')' . ' => ' . $stream->{'resolution'} . ' : ' . $stream->{'url'} . "\n";
		}
		if (   ($res > $bestResolution)
			|| ($res == $bestResolution && defined($bestStream) && $bestStream->{'suffix'} ne 'mp4'))
		{
			$bestStream     = $stream;
			$bestResolution = $res;
		}
	}

	if (!exists($bestStream->{'suffix'}) || length($bestStream->{'suffix'}) < 2) {
		$bestStream->{'suffix'} = 'mp4';
	}

	return ($bestStream->{'url'}, $bestStream->{'suffix'});
}

sub findFiles($) {
	my ($dir) = @_;
	my %files = ();

	# Allow complete bypass
	if ($NO_FILES) {
		return \%files;
	}

	# Read the output directory
	my $fh = undef();
	opendir($fh, $dir)
	  or die('Unable to open output directory: ' . $! . "\n");
	while (my $file = readdir($fh)) {
		my ($num, $id, $suffix) = $file =~ /^S\d+E(\d+) - ([\w\-]+)\.(\w\w\w)$/i;
		if (defined($id) && length($id) > 0) {
			if ($suffix eq 'nfo') {
				next;
			}

			my %tmp = (
				'number' => $num,
				'suffix' => $suffix,
				'path'   => $dir . '/' . $file,
			);
			$tmp{'nfo'} = $tmp{'path'};
			$tmp{'nfo'} =~ s/\.\w\w\w$/\.nfo/;

			if (exists($files{$id})) {
				warn('Duplicate ID: ' . $id . "\n\t" . $files{$id}->{'path'} . "\n\t" . $tmp{'path'} . "\n");
				if ($RENAME) {

					# Prefer to delete MP4 files, if the suffixes differ
					my $del = $files{$id};
					if ($tmp{'suffix'} eq 'mp4' && $del->{'suffix'} ne 'mp4') {
						$del = \%tmp;
						%tmp = %{ $files{$id} };
					}

					print STDERR 'Deleting duplicate: ' . $del->{'path'} . "\n";
					unlink($del->{'path'});
					unlink($del->{'nfo'});
				}
			}
			$files{$id} = \%tmp;
		}
	}
	close($fh);

	if ($DEBUG) {
		print STDERR "\nFound " . scalar(keys(%files)) . " files:\n\t" . join(', ', keys(%files)) . "\n";
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

sub saveChannel($$) {
	my ($dir, $channel) = @_;

	my $nfo = $dir . '/tvshow.nfo';
	if (!-e $nfo) {
		if ($DEBUG) {
			print STDERR 'Saving series data for: ' . $channel->{'title'} . "\n";
		}

		# Save the poster
		if (exists($channel->{'thumbnail'}) && length($channel->{'thumbnail'}) > 5) {
			my $poster = $dir . '/poster.jpg';
			my $jpg    = get($channel->{'thumbnail'});
			saveString($poster, $jpg);
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

sub readExcludes($) {
	my ($dir) = @_;
	my %excludes = ();

	# Read and parse the excludes videos file, if it exists
	my $file = $dir . '/' . $EXCLUDES_FILE;
	if (-e $file) {
		my $fh;
		open($fh, $file)
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

sub readExtras($) {
	my ($dir) = @_;
	my %extras = ();

	# Read and parse the extra videos file, if it exists
	my $file = $dir . '/' . $EXTRAS_FILE;
	if (-e $file) {
		my $fh;
		open($fh, $file)
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

sub dropExcludes($$) {
	my ($dir, $videos) = @_;
	my $excludes = readExcludes($dir);
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

sub addExtras($$) {
	my ($dir, $videos) = @_;
	my $extras = readExtras($dir);
	foreach my $id (keys(%{$extras})) {
		if (exists($videos->{$id})) {
			if ($DEBUG > 1) {
				print STDERR 'Skipping known extra video: ' . $id . "\n";
			}
			next;
		}

		my $video = findVideo($id);
		$video->{'number'} = $extras->{$id};
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
			$video->{'number'} = $itemCount - $index - $offset + 1;
			$videos{ $item->{'id'} } = $video;
			$offset++;
		}

		# Loop if there are results left to fetch
		$index += $BATCH_SIZE;
		if (defined($itemCount) && $itemCount > $index) {

			# But don't go past the max supported index
			if ($index <= $MAX_INDEX) {
				redo LOOP;
			}
		}
	}

	if ($DEBUG) {
		print STDERR "\nFound " . scalar(keys(%videos)) . ' videos for YouTube user ' . $user . ":\n\t" . join(', ', keys(%videos)) . "\n";
		if ($DEBUG > 1) {
			print STDERR prettyPrint(\%videos, "\t") . "\n";
		}
	}

	return \%videos;
}
