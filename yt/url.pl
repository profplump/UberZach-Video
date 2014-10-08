#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use WWW::YouTube::Download;

# Sanity check
if (scalar(@ARGV) < 1) {
	die('Usage: ' . basename($0) . " url\n");
}

# Command-line parameters
my $url = $ARGV[0];

# Environmental parameters
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Init the YT object
my $tube = WWW::YouTube::Download->new;

# Parse the video ID
my $id = $tube->video_id($url);

# Fetch metadata
my $meta = $tube->prepare_download($id);

# Find the best stream (i.e. highest resolution, prefer mp4)
my $bestStream     = undef();
my $bestResolution = 0;
foreach my $streamID (keys(%{ $meta->{'video_url_map'} })) {
	my $stream = $meta->{'video_url_map'}->{$streamID};
	my ($res) = $stream->{'resolution'} =~ /^\s*(\d+)/;
	if ($DEBUG) {
		print STDERR $streamID . ' (' . $stream->{'suffix'} . ')' . ' => ' . $stream->{'resolution'} . ' : ' . $stream->{'url'} . "\n\n";
	}
	if (   ($res > $bestResolution)
		|| ($res == $bestResolution && defined($bestStream) && $bestStream->{'suffix'} ne 'mp4'))
	{
		$bestStream     = $stream;
		$bestResolution = $res;
	}
}

# Return the download URL
print STDOUT $bestStream->{'url'} . "\n";

# Cleanup
exit(0);
