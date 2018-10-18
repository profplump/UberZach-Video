#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use MP3::Tag;
use Audio::M4P::QuickTime;
use XML::Feed;
use LWP::Simple;
use HTML::Strip;
use Date::Parse;
use Date::Format;
use File::Basename;

# Command-line
my $OUT_DIR = undef();
if (defined($ARGV[0])) {
	$OUT_DIR = abs_path($ARGV[0]);
}
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
my $ua = LWP::UserAgent->new();
$ua->agent('UberZach-RSS/1.0');

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
				if ($enc->{'type'} =~ /audio\/mp4/i || $enc->{'type'} =~ /audio\/x-m4a/i) {
					$ext = 'm4a';
				} elsif ($enc->{'type'} =~ /audio\/mpeg/i) {
					$ext = 'mp3';
				} elsif ($enc->{'type'} =~ /video\//i) {
					if ($DEBUG > 1) {
						warn('Skipping video file: ' . time2str('%Y-%m-%d', $time) . "\n");
					}
				} else {
					if ($DEBUG) {
						warn('Unknown MIME type: ' . $enc->{'type'} . "\n");
					}
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
			if ($itunes->{'duration'} =~ /(\d+)\:(\d\d)\:(\d\d)/) {
				$duration = (3600 * int($1)) + (60 * int($2)) + int($3);
			} elsif ($itunes->{'duration'} =~ /(\d+)\:(\d\d)/) {
				$duration = (60 * int($1)) + int($2);
			} elsif ($itunes->{'duration'} =~ /(\d+)/) {
				$duration = int($1);
			} elsif ($DEBUG) {
				print STDERR 'Unknown duration format: ' . $itunes->{'duration'} . "\n";
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
	if ($title && $time && $url && $ext && $desc) {
		my %tmp = (
			'title'       => $title,
			'time'        => $time,
			'url'         => $url,
			'ext'         => $ext,
			'description' => $desc,
			'size'        => $size,
			'duration'    => $duration,
			'author'      => $author,
		);
		$episodes{$time} = \%tmp;
	} elsif ($DEBUG) {
		print STDERR "Skipping incomplete entry:\n";
		print STDERR "\tTitle: ";
		if ($title) {
			print STDERR $title . "\n";
		} else {
			print STDERR "<missing>\n";
		}
		print STDERR "\tTime: ";
		if ($time) {
			print STDERR time2str('%Y-%m-%d', $time) . "\n";
		} else {
			print STDERR "<missing>\n";
		}
		print STDERR "\tURL: ";
		if ($url) {
			print STDERR $url . "\n";
		} else {
			print STDERR "<missing>\n";
		}
		print STDERR "\tExtension: ";
		if ($ext) {
			print STDERR $ext . "\n";
		} else {
			print STDERR "<missing>\n";
		}
		print STDERR "\tDescription: ";
		if ($desc) {
			print STDERR substr($desc, 0, 20) . "\n";
		} else {
			print STDERR "<missing>\n";
		}
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
				my $ratio = 1;
				if ($episodes{$time}->{'size'} =~ /^\d$/) {
					$ratio = ($size / $episodes{$time}->{'size'});
				} elsif ($DEBUG) {
					warn('Invalid episode size: ' . $episodes{$time}->{'size'});
				}
				if ($ratio < (1 - $ERR_RATIO) && $DEBUG) {
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
			print STDERR 'Will fetch: ' . time2str('%Y-%m-%d', $time) . "\n";
		}
	}
}
if ($DEBUG) {
	print STDERR 'Need/Total: ' . scalar(@need) . '/' . scalar(keys(%episodes)) . "\n";
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
		$episodes{$time}->{'title'} = time2str('%Y-%m-%d', $time) . ' - ' . $episodes{$time}->{'title'};
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
		print STDERR 'Fetching (' . time2str('%Y-%m-%d', $time) . '): ' . $ep->{'title'} . ' => ' . $ep->{'url'} . "\n";
	}

	# Fetch
	my $response = $ua->get($ep->{'url'});
	my $code     = $response->code();
	$dlCount++;

	# Validate HTTP
	my $err = undef();
	if ($code != 200) {
		$err = 'Invalid HTTP response: ' . $code;
		goto OUT;
	}

	# Save
	{
		my $fh;
		if (!open($fh, '>', $file)) {
			$err = 'Unable to open output file: ' . $file;
			goto OUT;
		}
		print {$fh} $response->decoded_content();
		close($fh);
	}

	# Validate file
	if (!-e $file) {
		$err = 'No output file: ' . $file;
		goto OUT;
	}
	if ($ep->{'size'}) {
		(undef(), undef(), undef(), undef(), undef(), undef(), undef(), my $size) = stat($file);
		my $ratio = $size / $ep->{'size'};
		if ($ratio < (1 - $ERR_RATIO)) {
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
		$tags->track(1);
		$tags->album($SERIES);
		$tags->artist($SERIES);
		$tags->genre($GENRE);

		# Save
		if (!$tags->write_tag()) {
			$err = 'Unable to update MP3 tags in: ' . $file . "\n";
			goto OUT;
		}
		$mp3->close();

	} elsif ($ep->{'ext'} eq 'm4a') {

		# Parse the MP3=4
		my $m4a = Audio::M4P::QuickTime->new(file => $file);
		if (!$m4a) {
			$err = 'Unable to parse MP4 tags in: ' . $file . "\n";
			goto OUT;
		}

		# Update tags
		$m4a->title($ep->{'title'});
		$m4a->year(time2str('%Y', $ep->{'time'}));
		$m4a->comment($ep->{'description'});
		$m4a->track(1);
		$m4a->album($SERIES);
		$m4a->artist($SERIES);
		$m4a->genre_as_text($GENRE);

		# Save
		if (!$m4a->WriteFile($file)) {
			$err = 'Unable to update M4A tags in: ' . $file . "\n";
			goto OUT;
		}

	} else {
		print STDERR 'Tag munging not available for ' . $ep->{'ext'} . ' files: ' . $file . "\n";
	}
  OUT:

	# Cleanup
	if (defined($err)) {
		if ($DEBUG || !($err =~ /\b40[34]$/)) {
			print STDERR 'Unable to download ' . $ep->{'url'} . ': ' . $err . "\n";
		}
		if (-e $file) {
			unlink($file);
		}
	}
}
