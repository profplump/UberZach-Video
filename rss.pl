#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use MP3::Tag;
use XML::Feed;
use LWP::Simple;
use HTML::Strip;
use Date::Parse;
use Date::Format;
use File::Basename;

# Command-line
my $OUT_DIR = abs_path($ARGV[0]);
if (!$OUT_DIR || !-d $OUT_DIR) {
	die('Usage: ' . basename($0) . " output_directory\n");
}

# Parameters
my $GENRE     = 'Podcast';
my $SERIES    = basename($OUT_DIR);
my $URL_FILE  = $OUT_DIR . '/url';
my $RULE_FILE = $OUT_DIR . '/rules.pm';
my $ERR_RATIO = 0.05;
my $DL_LIMIT  = 50;

# Init
our $DEBUG = 0;
if (defined($ENV{'DEBUG'}) && $ENV{'DEBUG'} =~ /(\d+)/) {
	$DEBUG = $1;
}
my %episodes = ();
my %have     = ();
my @need     = ();
my $hs       = HTML::Strip->new();
MP3::Tag->config('write_v24' => 1);

# Skip if there is a season_done file
if (-e $OUT_DIR . '/season_done') {
	if ($DEBUG) {
		print STDERR 'Podcast disabled: ' . $SERIES . "\n";
	}
	exit(0);
}

# Fetch and analyize the feed
my $feed = undef();
{
	open(my $fh, '<', $URL_FILE)
	  or die('Unable to open feed file: ' . $URL_FILE . "\n");
	my $url = <$fh>;
	close($fh);
	if (!$url || length($url) < 5) {
		die('Invalid feed URL: ' . $url . "\n");
	}

	$feed = XML::Feed->parse(URI->new($url));
	if (!$feed) {
		die('Unable to parse feed (' . XML::Feed->errstr() . '): ' . $url . "\n");
	}
}

# Parse each episode from the feed
for my $entry ($feed->entries()) {
	my $ep = $entry->unwrap();

	# Title
	my $title = '';
	if (defined($ep->{'title'})) {
		$title = $ep->{'title'};
	}
	$title = $hs->parse($title);
	$hs->eof();
	$title =~ s/^\s+//;
	$title =~ s/\s+$//;

	# Description
	my $desc = '';
	if (defined($ep->{'description'})) {
		$desc = $ep->{'description'};
	}
	$desc = $hs->parse($desc);
	$hs->eof();
	$desc =~ s/^\s+//;
	$desc =~ s/\s+$//;

	# Timestamp
	my $time = str2time($ep->{'pubDate'});

	# Author
	my $author = undef();
	if (exists($ep->{'author'})) {
		$author = $ep->{'author'};
		$author =~ s/^\s+//;
		$author =~ s/\s+$//;
	}

	# Enclosure (i.e. attachment/file) data
	my ($url, $ext, $size) = undef();
	{
		my $enc = $ep->{'enclosure'};
		if ($enc && ref($enc) eq 'HASH' && exists($enc->{'url'})) {
			$url = $enc->{'url'};
			if (exists($enc->{'type'})) {
				if ($enc->{'type'} =~ /audio\/mp4/i) {
					$ext = 'm4a';
				} elsif ($enc->{'type'} =~ /audio\/mpeg/i) {
					$ext = 'mp3';
				} elsif ($enc->{'type'} =~ /video\//i) {
					if ($DEBUG > 1) {
						print STDERR 'Skipping video file: ' . $time . "\n";
					}
				} else {
					print STDERR 'Unknown MIME type: ' . $enc->{'type'} . "\n";
				}
			}
			if (exists($enc->{'length'})) {
				$size = $enc->{'length'};
			}
		}
	}

	# iTunes data, if available (and useful)
	my $duration = undef();
	if ($ep->{'http://www.itunes.com/dtds/podcast-1.0.dtd'}) {
		my $itunes = $ep->{'http://www.itunes.com/dtds/podcast-1.0.dtd'};

		if (exists($itunes->{'duration'})) {
			if ($itunes->{'duration'} =~ /(\d{1,2})\:(\d{1,2})\:(\d{1,2})/) {
				$duration = (3600 * int($1)) + (60 * int($2)) + int($3);
			} else {
				$duration = int($itunes->{'duration'});
			}
		}
		if (!$desc && exists($itunes->{'summary'})) {
			$desc = $itunes->{'summary'};
			$desc =~ s/^\s+//;
			$desc =~ s/\s+$//;
		}
		if (!$author && exists($itunes->{'author'})) {
			$author = $itunes->{'author'};
			$author =~ s/^\s+//;
			$author =~ s/\s+$//;
		}
	}

	# Collect extracted, cleaned data
	if ($title && $desc && $time && $url && $ext) {
		my %tmp = (
			'title'       => $title,
			'description' => $desc,
			'time'        => $time,
			'url'         => $url,
			'ext'         => $ext,
			'size'        => $size,
			'duration'    => $duration,
			'author'      => $author,
		);
		$episodes{$time} = \%tmp;
	} elsif ($DEBUG) {
		print STDERR 'Skipping incomplete entry: ' . $title . ': ' . $time . "\n";
	}
}

# Check for existing files
opendir(my $fh, $OUT_DIR)
  or die('Unable to open output directory (' . $! . '): ' . $OUT_DIR . "\n");
while (my $file = readdir($fh)) {
	my $path = $OUT_DIR . '/' . $file;
	if (-d $path) {
		next;
	}
	if ($file =~ /^(.*)\s+\((\d{7,})\)\.\w{3}$/) {
		my $title = $1;
		my $time  = $2;
		if (exists($episodes{$time})) {
			if (exists($episodes{$time}->{'size'}) && $episodes{$time}->{'size'}) {
				(undef(), undef(), undef(), undef(), undef(), undef(), undef(), my $size) = stat($path);
				my $ratio = ($size / $episodes{$time}->{'size'});
				if ($ratio < (1 - $ERR_RATIO) || $ratio > (1 + $ERR_RATIO)) {
					print STDERR 'Invalid output file size (' . $size . '/' . $episodes{$time}->{'size'} . '): ' . $file . "\n";
				}
			}
			$have{$time} = 1;
			$episodes{$time}->{'title'} = $title;
		}
		if ($DEBUG) {
			print STDERR 'Found file: ' . $file . "\n";
		}
	} elsif ($DEBUG > 1) {
		print STDERR 'Skipping file: ' . $file . "\n";
	}
}
closedir($fh);

# Decide what we want to download
foreach my $time (keys(%episodes)) {
	if (!exists($have{$time})) {
		push(@need, $time);
		if ($DEBUG > 1) {
			print STDERR 'Will fetch: ' . $time . "\n";
		}
	}
}

# Apply naming rules
if (-e $RULE_FILE) {
	if ($DEBUG > 1) {
		print STDERR 'Importing local rules from: ' . $RULE_FILE . "\n";
	}
	require $RULE_FILE;
	localRules(\%episodes);
} else {
	foreach my $time (sort(keys(%episodes))) {
		$episodes{$time}->{'title'} = time2str('%Y-%m-%d', $time) . ' - 1 - ' . $episodes{$time}->{'title'};
	}
}
foreach my $time (keys(%episodes)) {
	$episodes{$time}->{'title'} =~ s/\s*\:\s*/ - /g;
	$episodes{$time}->{'title'} =~ s/\s+/ /g;
	$episodes{$time}->{'title'} =~ s/\"/\'/g;
	$episodes{$time}->{'title'} =~ s/[^\w\s\,\-\.\!\'\(\)\#\&\@]//g;
}

# Fetch needed files, with basic validation
my $dlCount = 0;
foreach my $time (sort(@need)) {
	if ($dlCount >= $DL_LIMIT) {
		die('Download limit (' . $DL_LIMIT . ') reached: ' . $SERIES . "\n");
	}

	# Build a file path
	my $ep   = $episodes{$time};
	my $file = $OUT_DIR . '/' . $ep->{'title'} . ' (' . int($time) . ').' . $ep->{'ext'};
	if (-e $file) {
		die('Unexpected output file: ' . $file . "\n");
	}

	# Debug
	if ($DEBUG) {
		print STDERR 'Fetching (' . $time . '): ' . $ep->{'title'} . ' => ' . $ep->{'url'} . "\n";
	}

	# Fetch
	my $code = getstore($ep->{'url'}, $file);
	$dlCount++;

	# Validate
	my $err = undef();
	if ($code != 200) {
		$err = 'Invalid HTTP response: ' . $code;
		goto OUT;
	}
	if (!-e $file) {
		$err = 'No output file: ' . $file;
		goto OUT;
	}
	if ($ep->{'size'}) {
		(undef(), undef(), undef(), undef(), undef(), undef(), undef(), my $size) = stat($file);
		my $ratio = $size / $ep->{'size'};
		if ($ratio < (1 - $ERR_RATIO) || $ratio > (1 + $ERR_RATIO)) {
			$err = 'Invalid download size (' . $size . '/' . $ep->{'size'} . '): ' . $file;
			goto OUT;
		}
	}

	# Set MP3/M4A tags
	if ($ep->{'ext'} eq 'mp3') {

		# Parse the MP3
		my $mp3 = MP3::Tag->new($file);
		if (!$mp3) {
			$err = 'Unable to parse MP3 tags in: ' . $file . "\n";
			goto OUT;
		}

		# Delete any ID3v1 tags
		if (exists($mp3->{'ID3v1'})) {
			print STDERR "Removing ID3v1 tag\n";
			$mp3->{'ID3v1'}->remove_tag();
			print STDERR "Removed?\n";
		}

		# Find or create the ID3v2 tag
		my $tags = undef();
		if (exists($mp3->{'ID3v2'})) {
			$tags = $mp3->{'ID3v2'};
		} else {
			$tags = $mp3->new_tag('ID3v2');
		}

		# Update tags
		$tags->title($ep->{'title'});
		$tags->year(time2str('%Y', $ep->{'time'}));
		$tags->comment($ep->{'description'});
		$tags->album($SERIES);
		$tags->artist($SERIES);
		$tags->genre($GENRE);

		# Save
		if (!$tags->write_tag()) {
			$err = 'Unable to update MP3 tags in: ' . $file . "\n";
			goto OUT;
		}
		$mp3->close();
	} else {
		print STDERR 'Tag munging not available for ' . $ep->{'ext'} . ' files: ' . $file . "\n";
	}
	OUT:

	# Cleanup
	if (defined($err)) {
		print STDERR 'Unable to download ' . $ep->{'url'} . ': ' . $err . "\n";
		if (-e $file) {
			unlink($file);
		}
	}
}
