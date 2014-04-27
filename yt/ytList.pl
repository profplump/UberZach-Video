#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use LWP::Simple;
use URI::Escape;
use JSON;
use Date::Parse;

# Paramters
my $BATCH_SIZE = 50;
my $MAX_INDEX  = 500;
my $URL_PREFIX = 'http://gdata.youtube.com/feeds/api/users/';
my $URL_SUFFIX = '/uploads';
my %API_PARAMS = (
	'strict'      => 1,
	'v'           => 2,
	'alt'         => 'jsonc',
	'orderby'     => 'published',
	'max-results' => $BATCH_SIZE,
);

# Prototypes
sub findVideos($);
sub findFiles($);

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
			print STDERR 'Fetching video: ' . $basePath . "\n";
		}
	}

	if (!exists($files->{$id}) || !-e $files->{$id}->{'nfo'}) {
		if ($DEBUG) {
			print STDERR 'Creating NFO: ' . $basePath . "nfo\n";
		}
	}
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
