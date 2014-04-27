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
my $CURL_BIN    = 'curl';
my @CURL_ARGS   = ('-4', '--insecure', '-C', '-');
my $BATCH_SIZE  = 50;
my $MAX_INDEX   = 500;
my $URL_PREFIX  = 'http://gdata.youtube.com/feeds/api/users/';
my $URL_SUFFIX  = '/uploads';
my %CHAN_PARAMS = (
	'strict' => 1,
	'v'      => 2,
	'alt'    => 'json',
);
my %LIST_PARAMS = (
	'strict' => 1,
	'v'      => 2,
	'alt'    => 'jsonc',
);

# Prototypes
sub findVideos($);
sub findFiles($);
sub ytURL($);
sub buildNFO($);
sub buildSeriesNFO($);
sub getChannel($);
sub fetchParse($);
sub buildURL($$);
sub saveString($$);

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

# Environmental parameters
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
$LIST_PARAMS{'max-results'} = $BATCH_SIZE;
if (!$DEBUG) {
	push(@CURL_ARGS, '--silent');
}

# Grab the channel data
my $channel = getChannel($user);

# Create the channel NFO and poster, if needed
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

# Find all the user's videos on YT
my $videos = findVideos($user);

# Find all existing YT files on disk
my $files = findFiles($dir);

# Fill in missing videos and NFOs
foreach my $id (keys(%{$videos})) {
	my $basePath = $dir . '/S01E' . sprintf('%02d', $videos->{$id}->{'number'}) . ' - ' . $id . '.';
	$nfo = $basePath . 'nfo';

	# Warn (and optionally rename) if the episode numbers drift
	if (exists($files->{$id}) && $files->{$id}->{'number'} != $videos->{$id}->{'number'}) {
		warn('Video ' . $id . ' had episode number ' . $files->{$id}->{'number'} . ' but now has episode number ' . $videos->{$id}->{'number'} . "\n");
		if ($RENAME) {
			print STDERR 'Renaming ' . $files->{$id}->{'path'} . ' => ' . $basePath . $files->{$id}->{'suffix'} . "\n";
			rename($files->{$id}->{'path'}, $basePath . $files->{$id}->{'suffix'});
			unlink($files->{$id}->{'nfo'});
			delete($files->{$id});
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
				print STDERR 'Not fetching: ' . join(' ', @cmd) . "\n";
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
		saveString($nfo, $xml);
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

	$elm = $doc->createElement('title');
	$elm->appendText($video->{'title'});
	$show->appendChild($elm);

	$elm = $doc->createElement('aired');
	$elm->appendText(time2str('%Y-%m-%d', $video->{'date'}));
	$show->appendChild($elm);

	$elm = $doc->createElement('plot');
	$elm->appendText($video->{'description'});
	$show->appendChild($elm);

	$elm = $doc->createElement('runtime');
	$elm->appendText($video->{'duration'});
	$show->appendChild($elm);

	$elm = $doc->createElement('rating');
	$elm->appendText($video->{'rating'});
	$show->appendChild($elm);

	$elm = $doc->createElement('director');
	$elm->appendText($video->{'creator'});
	$show->appendChild($elm);

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

	# Read the output directory
	my $fh = undef();
	opendir($fh, $dir)
	  or die('Unable to open output directory: ' . $! . "\n");
	while (my $file = readdir($fh)) {
		my ($num, $id, $suffix) = $file =~ /S\d+E(\d+) - ([\w\-]+)\.(\w\w\w)$/i;
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
					print STDERR 'Deleting duplicate: ' . $files{$id}->{'path'} . "\n";
					unlink($files{$id}->{'path'});
					unlink($files{$id}->{'nfo'});
					delete($files{$id});
				}
			}
			$files{$id} = \%tmp;
		}
	}
	close($fh);

	if ($DEBUG) {
		print STDERR "\nFound " . scalar(keys(%files)) . " files:\n\t" . join("\n\t", keys(%files)) . "\n";
		if ($DEBUG > 1) {
			print STDERR prettyPrint(\%files, "\t") . "\n";
		}
	}

	return \%files;
}

sub buildURL($$) {
	my ($base, $params) = @_;
	my $url = $base . '?';
	foreach my $name (keys(%{$params})) {
		$url .= '&' . uri_escape($name) . '=' . uri_escape($params->{$name});
	}
	return $url;
}

sub fetchParse($) {
	my ($url) = @_;

	# Fetch
	if ($DEBUG) {
		print STDERR 'Fetching list URL: ' . $url . "\n";
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

sub getChannel($) {
	my ($user) = @_;

	# Build, fetch, parse
	my $url = buildURL($URL_PREFIX . $user, \%CHAN_PARAMS);
	my $data = fetchParse($url);

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

sub findVideos($) {
	my ($user) = @_;
	my %videos = ();

	# Prepare the static URL elements
	my $baseURL = $URL_PREFIX . $user . $URL_SUFFIX;
	my %params  = %LIST_PARAMS;

	# Loop through until we have all the entries
	my $index     = 1;
	my $itemCount = undef();
	LOOP:
	{

		# Build, fetch, parse
		$params{'start-index'} = $index;
		my $url = buildURL($baseURL, \%params);
		my $data = fetchParse($url);

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
			my %tmp = (
				'number'      => ($itemCount - $index - $offset + 1),
				'title'       => $item->{'title'},
				'date'        => str2time($item->{'uploaded'}),
				'description' => $item->{'description'},
				'duration'    => $item->{'duration'},
				'rating'      => $item->{'rating'},
				'creator'     => $item->{'uploader'},
			);
			$videos{ $item->{'id'} } = \%tmp;
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
		print STDERR "\nFound " . scalar(keys(%videos)) . ' videos for YouTube user ' . $user . ":\n\t" . join("\n\t", keys(%videos)) . "\n";
		if ($DEBUG > 1) {
			print STDERR prettyPrint(\%videos, "\t") . "\n";
		}
	}

	return \%videos;
}
