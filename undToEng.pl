#!/usr/bin/perl
use strict;
use warnings;
use IPC::System::Simple qw(capturex $EXITVAL EXIT_ANY);

my $INFO_BIN  = 'mkvinfo';
my $LABEL_BIN = 'mkvpropedit';

# Sanity check
if (scalar(@ARGV) < 1 || !-r $ARGV[0]) {
	print STDERR 'Usage: ' . $0 . " input_file\n";
	exit(1);
}
if (!($ARGV[0] =~ /\.mkv$/i)) {
	print STDERR 'Error: This utility can only be used with MKV-format files: ' . $ARGV[0] . "\n";
	exit(2);
}

# Analyze the file
my @output = capturex($INFO_BIN, $ARGV[0]);

# Parse the output
my $inTracks = 0;
my $track    = undef();
my @tracks   = ();
foreach my $str (@output) {

	# End track
	if (defined($track) && $str =~ /^\| ?\+\s+/) {
		push(@tracks, $track);
		$track = undef();
	}

	# End tracks section
	if ($inTracks && $str =~ /^\|\+\s+/) {
		$inTracks = 0;
	}

	# Start tracks section
	if (!$inTracks && $str =~ /^\|\+\s+Segment tracks/) {
		$inTracks = 1;
		next;
	}

	# Skip lines not in the tracks section
	if (!$inTracks) {
		next;
	}

	# Start track
	if (!defined($track) && $str =~ /^\| \+\s+A track/) {
		my %tmp = ();
		$track = \%tmp;
		next;
	}

	# Skip lines not in a track section
	if (!defined($track)) {
		next;
	}

	# Parse
	if ($str =~ /^\|  \+\s+Track number\: \d+ \(track ID for mkvmerge \& mkvextract\: (\d+)\)/) {
		$track->{'id'} = $1;
	} elsif ($str =~ /\|  \+\s+Track UID\:\s+(\d+)/) {
		$track->{'uid'} = $1;
	} elsif ($str =~ /\|  \+\s+Track type\:\s+(\w+)/) {
		$track->{'type'} = $1;
	} elsif ($str =~ /\|  \+\s+Language\:\s+(\w+)/) {
		$track->{'lang'} = $1;
	} elsif ($str =~ /\|  \+\s+Codec ID\:\s+(\w+)/) {
		$track->{'codec'} = $1;
	} elsif (exists($track->{'type'}) && $track->{'type'} eq 'audio') {
		if ($str =~ /^\|   \+\s+Sampling frequency\:\s+(\d+)/) {
			$track->{'samples'} = $1;
		} elsif ($str =~ /^\|   \+\s+Channels\:\s+(\d+)/) {
			$track->{'channels'} = $1;
		}
	} elsif (exists($track->{'type'}) && $track->{'type'} eq 'video') {
		if ($str =~ /^\|   \+\s+Pixel width\:\s+(\d+)/) {
			$track->{'width_raw'} = $1;
		} elsif ($str =~ /^\|   \+\s+Pixel height\:\s+(\d+)/) {
			$track->{'height_raw'} = $1;
		} elsif ($str =~ /^\|   \+\s+Display width\:\s+(\d+)/) {
			$track->{'width'} = $1;
		} elsif ($str =~ /^\|   \+\s+Display height\:\s+(\d+)/) {
			$track->{'height'} = $1;
		}
	}
}

# We only care about valid audio tracks with langauges
my @audio = ();
foreach my $track (@tracks) {
	if (!exists($track->{'uid'})) {
		next;
	}
	if (!exists($track->{'lang'})) {
		next;
	}
	if (!exists($track->{'type'})) {
		next;
	}
	if ($track->{'type'} ne 'audio') {
		next;
	}
	push(@audio, $track);
}

# Release master tracks data
undef(@tracks);

# Determine if we have any English audio tracks
my $noEng = 1;
foreach my $track (@audio) {
	if ($track->{'lang'} eq 'eng') {
		$noEng = 0;
		last;
	}
}

# Nothing to do if there are already English tracks
if (!$noEng) {
	exit(0);
}

# Re-label any 'und' tracks to 'eng' (i.e. don't overwrite valid langauge labels)
my @relabel = ();
foreach my $track (@audio) {
	if ($track->{'lang'} eq 'und') {
		push(@relabel, $track->{'uid'});
	}
}

# Nothing to do if there aren't any tracks to re-label
if (scalar(@relabel) < 1) {
	exit(0);
}

# Execute
my @args = ($ARGV[0]);
foreach my $uid (@relabel) {
	push(@args, '--edit', 'track:=' . $uid, '--set', 'language=eng');
}
my $err = capturex(EXIT_ANY, $LABEL_BIN, @args);
if ($EXITVAL != 0) {
	print STDERR $0 . ': Error while processing ' . $ARGV[0] . "\n\n" . $err;
	exit(4);
}

# Debug
#print $LABEL_BIN . " '" . join("' '", @args) . "'\n";

# Cleanup
exit(0);
