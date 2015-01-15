#!/usr/bin/perl
use strict;
use warnings;

# Includes
use File::Basename;

# Parameters
my @BASE_DIRS = ();
my @skipped   = ();
my @monitored = ();
my @done      = ();

# Command-line parameters
my ($prg, $base_dir) = @ARGV;

# TV path(s)
{
	my $base = undef();
	if (defined($base_dir) && -d $base_dir) {
		$base = $base_dir;
	} else {
		my $cmd = $ENV{'HOME'} . '/bin/video/mediaPath';
		if (-x $cmd) {
			$base = `${cmd}`;
		}
	}

	if (!defined($base)) {
		die("No base directory available\n");
	}

	foreach my $dir ('TV', 'Downloads') {
		my $path = $base . '/' . $dir;
		if (-d $path) {
			push(@BASE_DIRS, $path);
		}
	}
}

# For each directory
for my $BASE_DIR (@BASE_DIRS) {

	# For each show
	opendir(BASE_DIR, $BASE_DIR)
	  or die("Unable to open input directory: ${!}\n");
	while (my $dir = readdir(BASE_DIR)) {

		# Skip the stock entries
		if (!$dir || $dir eq '.' || $dir eq '..') {
			next;
		}

		# Construct the path
		my $path = $BASE_DIR . '/' . $dir;

		# Skip non-folders
		if (!-d $path) {
			next;
		}

		# Look for "skip" files
		if (-e $path . '/skip') {
			push(@skipped, $dir);
			next;
		}

		# Look for season folders
		opendir(SUB_DIR, $path)
		  or die('Unable to open subfolder "' . $path . '": ' . $! . "\n");
		while (my $subdir = readdir(SUB_DIR)) {

			# Skip the stock entries
			if (!$dir || $dir eq '.' || $dir eq '..') {
				next;
			}

			# Construct the path
			my $subpath = $path . '/' . $subdir;

			# Skip non-folders
			if (!-d $subpath) {
				next;
			}

			# Skip symlinks
			if (-l $subpath) {
				next;
			}

			# Look for "season" folders
			if ($subdir =~ /^Season\s+(\d+)$/i) {
				my $season_num = $1;

				# Construct a name
				my $name = '';
				if ($prg) {
					$name = $subpath;
				} else {
					$name = $dir . ' - ' . $subdir;
				}

				# Check if the season is done
				if (-e $subpath . '/season_done') {
					push(@done, $name);

					# Season 0 is always done
				} elsif ($season_num == 0) {
					push(@done, $name);

					# Otherwise record the season
				} else {
					push(@monitored, $name);
				}
			}
		}
		close(SUB_DIR);
	}
	close(BASE_DIR);
}

# Sort
@done = sort(@done);
@skipped = sort(@skipped);
@monitored = sort(@monitored);

# Print results
if ($prg && $prg =~ /NULL/i) {
	foreach my $show (@monitored) {
		print $show . "\0";
	}
} elsif ($prg && $prg =~ /STORE/i) {
	my %shows = ();
	foreach my $show (@monitored) {
		$shows{ basename(dirname($show)) } = 1;
	}
	foreach my $key (keys(%shows)) {
		print $key . "\n";
	}
} else {
	if (scalar(@done) > 0) {
		print "\nDone:\n";
		foreach my $show (@done) {
			print $show . "\n";
		}
	} else {
		print "\nNo seasons done\n";
	}
	if (scalar(@skipped) > 0) {
		print "\nSkipped:\n";
		foreach my $show (@skipped) {
			print $show . "\n";
		}
	} else {
		print "\nNo shows skipped\n";
	}
	if (scalar(@monitored) > 0) {
		print "\nMonitored:\n";
		foreach my $show (@monitored) {
			print $show . "\n";
		}
	} else {
		print "\nNo shows monitored\n";
	}
}

# Cleanup
exit(0);
