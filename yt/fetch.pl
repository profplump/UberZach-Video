#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/";

use File::Touch;
use File::Basename;
use IPC::System::Simple qw( system run capture EXIT_ANY $EXITVAL );
use IPC::Cmd qw( can_run );
use Cwd qw( abs_path );

# Paramters
my $YTDL_BIN      = $ENV{'HOME'} . '/bin/video/yt/youtube-dl';
my @YTDL_ARGS     = ('--force-ipv4', '--socket-timeout', '10', '--retries', '1', 
			'--no-playlist', '--max-downloads', '1', '--age-limit', '99');
my @YTDL_QUIET    = ('--quiet', '--no-warnings');
my @YTDL_DEBUG    = ('--verbose');

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	if ($ENV{'DEBUG'} =~ /(\d+)/) {
		$DEBUG = $1;
	} else {
		$DEBUG = 1;
	}
}

# Sanity check
if (scalar(@ARGV) < 1) {
	die('Usage: ' . basename($0) . " output_directory\n");
}

if ($DEBUG) {
	print STDERR 'Fetching video: ' . $id . "\n";
}

my $reviewed = videoSE($videos->{$id}->{'season'}, $videos->{$id}->{'number'}) . $id . '.reviewed';
touch($reviewed);
my @args = ('--output', videoSE($videos->{$id}->{'season'}, $videos->{$id}->{'number'}) . '%(id)s.%(ext)s', '--', $id);
my @name = ($YTDL_BIN);
push(@name, @YTDL_ARGS);
my @fetch = @name;
push(@name,  '--get-filename');
push(@fetch, @args);
push(@name,  @args);

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

