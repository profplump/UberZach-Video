#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use Date::Parse;
use Date::Format;
use LWP::Simple;
use URI::Escape;
use JSON;
use XML::LibXML;
use IPC::System::Simple qw( system );
use WWW::YouTube::Download;

# Paramters
my $CURL_BIN   = 'curl';
my @CURL_ARGS  = ('--insecure', '-C', '-');
my $BATCH_SIZE = 50;
my $MAX_INDEX  = 500;
my $URL_PREFIX = 'http://gdata.youtube.com/feeds/api/users/';
my $URL_SUFFIX = '/uploads';
my %API_PARAMS = (
	'strict'  => 1,
	'v'       => 2,
	'alt'     => 'jsonc',
	'orderby' => 'published',
);

# Prototypes
sub findVideos($);
sub findFiles($);
sub ytURL($);
sub buildNFO($);

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
if ($ENV{'MAX_INDEX'} && $ENV{'MAX_INDEX'} =~ /(\d+)/) {
	$MAX_INDEX = $1;
}
if ($ENV{'BATCH_SIZE'} && $ENV{'BATCH_SIZE'} =~ /(\d+)/) {
	$BATCH_SIZE = $1;
}

# Construct globals
$API_PARAMS{'max-results'} = $BATCH_SIZE;
if (!$DEBUG) {
	push(@CURL_ARGS, '--silent');
}

# Find all the user's videos on YT
my $videos = findVideos($user);

# Find all existing YT files on disk
my $files = findFiles($dir);

# Fill in missing videos and NFOs
foreach my $id (keys(%{$videos})) {
	my $basePath;
	{
		my $safeTitle = $videos->{$id}->{'title'};
		$safeTitle =~ s/\:/ - /g;
		$safeTitle =~ s/\s+/ /g;
		$safeTitle =~ s/[^\w\-\.\?\!\&\,\; ]/_/g;
		$basePath = $dir . '/' . sprintf('%02d', $videos->{$id}->{'number'}) . ' - ' . $safeTitle . ' (' . $id . ').';
	}

	if (!exists($files->{$id})) {
		if ($DEBUG) {
			print STDERR 'Fetching video: ' . $id . "\n";
		}

		# Find the download URL and file suffix
		my ($url, $suffix) = ytURL($id);
		if (!defined($url) || length($url) < 5) {
			warn('Could not determine URL for video: ' . $id . "\n");
			next;
		}

		# Fetch with cURL
		# I know LWP exists (and is even loaded) but cURL makes my life easier
		{
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
	}

	if (!exists($files->{$id}) || !-e $files->{$id}->{'nfo'}) {
		my $nfo = $basePath . 'nfo';
		if ($DEBUG) {
			print STDERR 'Creating NFO: ' . $nfo . "\n";
		}

		# Build the XML document
		my $xml = buildNFO($videos->{$id});
		if ($DEBUG > 1) {
			print STDERR 'Saving NFO: ' . $xml . "\n";
		}

		# Save to disk
		my $fh = undef();
		if (!open($fh, '>', $nfo)) {
			warn('Cannot open NFO: ' . $! . "\n");
			next;
		}
		print $fh $xml;
		close($fh);
	}
}

sub buildNFO($) {
	my ($video) = @_;

	# Create an XML tree
	my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
	$doc->setStandalone(1);
	my $show = $doc->createElement('episodedetails');
	$doc->setDocumentElement($show);
	my $elm;

	# Generic elements (in case we get excited later)
	my $fileinfo = $doc->createElement('fileinfo');
	$show->appendChild($fileinfo);
	my $streamdetails = $doc->createElement('streamdetails');
	$fileinfo->appendChild($streamdetails);
	$elm = $doc->createElement('video');
	$streamdetails->appendChild($elm);

	$elm = $doc->createElement('playcount');
	$show->appendChild($elm);
	$elm = $doc->createElement('credits');
	$show->appendChild($elm);

	my $actor = $doc->createElement('actor');
	$show->appendChild($actor);
	$elm = $doc->createElement('name');
	$actor->appendChild($elm);
	$elm = $doc->createElement('role');
	$actor->appendChild($elm);

	# Static elements (per the nature of this process)
	$elm = $doc->createElement('season');
	$elm->appendText('1');
	$show->appendChild($elm);

	# Dynamic data
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
	my $meta = $tube->prepare_download($id);
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
			print STDERR $streamID . ' (' . $stream->{'suffix'} . ')' . ' => ' . $stream->{'resolution'} . ' : ' . $stream->{'url'} . "\n\n";
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
		my ($num, $title, $id, $suffix) = $file =~ /(\d+) - (.+) \(([\w\-]+)\)\.(\w\w\w)$/;
		if (defined($id) && length($id) > 0) {
			if ($suffix eq 'nfo') {
				next;
			}

			my %tmp = (
				'number' => $num,
				'title'  => $title,
				'suffix' => $suffix,
				'path'   => $dir . '/' . $file,
			);
			$tmp{'nfo'} = $tmp{'path'};
			$tmp{'nfo'} =~ s/\.\w\w\w$/\.nfo/;
			$files{$id} = \%tmp;
		}
	}
	close($fh);

	if ($DEBUG) {
		print STDERR "\n\nFound " . scalar(keys(%files)) . " files:\n\t" . join("\n\t", keys(%files)) . "\n\n";
		if ($DEBUG > 1) {
			use PrettyPrint;
			print STDERR prettyPrint(\%files, "\t") . "\n";
		}
	}

	return \%files;
}

sub findVideos($) {
	my ($user) = @_;
	my %videos = ();

	# Build the base URL
	my $baseURL = $URL_PREFIX . $user . $URL_SUFFIX;

	# And the static URL parameters
	my %params = %API_PARAMS;

	# Loop through until we have all the entries
	my $index     = 1;
	my $itemCount = undef();
	LOOP:
	{
		# Build the actual URL
		my $url = $baseURL . '?start-index=' . $index;
		foreach my $name (keys(%params)) {
			$url .= '&' . uri_escape($name) . '=' . uri_escape($params{$name});
		}

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
		if (!exists($data->{'data'})) {
			die('Invalid data set: ' . $content . "\n");
		}
		$data = $data->{'data'};

		# Grab the total count, so we know when to stop
		if (!defined($itemCount) && exists($data->{'totalItems'})) {
			$itemCount = $data->{'totalItems'};
		}

		# Process each item
		if (!exists($data->{'items'}) || ref($data->{'items'}) ne 'ARRAY') {
			die('Invalid item list: ' . $content . "\n");
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
		print STDERR "\n\nFound " . scalar(keys(%videos)) . ' videos for YouTube user ' . $user . ":\n\t" . join("\n\t", keys(%videos)) . "\n\n";
		if ($DEBUG > 1) {
			use PrettyPrint;
			print STDERR prettyPrint(\%videos, "\t") . "\n";
		}
	}

	return \%videos;
}
