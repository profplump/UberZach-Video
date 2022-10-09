#!/usr/bin/perl
use warnings;
use strict;

# Prototypes
sub run_mplayer(@);

# Includes and paramters
use IPC::Open3;
use File::Basename;
my @exec_args = ('mplayer', '-identify', '-vo', 'null', '-ao', 'null', '-frames', '1');
my $MAX_AUDIO = 10;

# Command line parameters
my ($infile, $MODE) = @ARGV;
if (!-r $infile) {
	die('Usage: ' . basename($0) . "input_file [mode]\n");
}
if ($MODE) {
	$MODE = uc($MODE);
}

# Run mplayer
my @args = @exec_args;
push(@args, $infile);
my $data = run_mplayer(@args);

# Sanity check
if (!defined($data->{'VIDEO_FORMAT'}) || length($data->{'VIDEO_FORMAT'}) < 1) {
	die(basename($0) . ': Unable to find video streams in: ' . $infile . "\n");
}

# Duplicate the audio data for track 0 with the appropriate index
foreach my $key (keys(%{$data})) {
	if ($key =~ /AUDIO/) {
		$data->{ $key . '_0' } = $data->{$key};
	}
}

# Run mplayer again for each audio track
if (!defined($data->{'AUDIO_ID'})) {
	$data->{'AUDIO_ID'} = -1;
}
for (my $i = 0 ; $i <= $data->{'AUDIO_ID'} && $i < $MAX_AUDIO ; $i++) {
	my @args = @exec_args;
	push(@args, '-aid', $i, $infile);
	my $audio = run_mplayer(@args);

	foreach my $key (keys(%{$audio})) {
		if ($key =~ /AUDIO/) {
			$data->{ $key . '_' . $i } = $audio->{$key};
		}
	}
}

# Output
if (defined($MODE) && length($MODE) > 0) {
	if (defined($data->{$MODE})) {
		print $data->{$MODE} . "\n";
	} else {
		die(basename($0) . ': No such data: ' . $MODE . "\n");
	}
} else {
	foreach my $key (keys(%{$data})) {
		print $key . '=' . $data->{$key} . "\n";
	}
}

# Cleanup
exit(0);

# Run mplayer and return a hash of all lines that start with ID_
# Timeout after 30 seconds or 100 non-matching lines
sub run_mplayer(@) {
	my %data = ();
	eval {
		my $child_in  = '';
		my $child_out = '';
		my $pid       = open3($child_in, $child_out, $child_out, @_);

		# Timeout after 30 seconds
		local $SIG{ALRM} = sub { kill(9, $pid); die("Timeout\n"); };
		alarm(30);

		# Read the output
		my $errcnt = 0;
		while (<$child_out>) {
			if (/^ID_(.+)\=(.*)/) {
				$data{$1} = $2;
			} else {
				$errcnt++;
			}
			if ($errcnt > 100) {
				kill(9, $pid);
				die("Too many errors\n");
			}
		}

		# Cleanup and cancel the alarm
		waitpid($pid, 0);
		close($child_out);
		alarm(0);
	};
	if ($@ ne "") {
		print(STDERR $@);
	}
	return \%data;
}
