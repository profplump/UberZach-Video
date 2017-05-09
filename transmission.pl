#!/usr/bin/perl
use warnings;
use strict;

# Includes
use JSON;
use Date::Parse;
use File::Copy;
use File::Touch;
use File::Temp 'mktemp';
use File::Path 'remove_tree';
use File::Basename;
use Image::ExifTool qw/ :Public/;
use FindBin qw($Bin);
use lib $Bin;
use Fetch;

# Prototypes
sub session($);
sub fetch($);
sub getSSE($);
sub getDest($$$$);
sub storeFiles($$$);
sub readNZB($$);
sub storeNZB($);
sub storeTor($);
sub delNZB($);
sub delTor($);
sub guessExt($);
sub processFile($$);
sub unrar($$);
sub seriesCleanupLocal($);
sub seriesCleanupCore($);
sub seriesCleanup($);
sub readDir($$);
sub findMediaFiles($$);
sub available($);

# Parameters
my $maxAge        = 2.5 * 86400;
my $tvDir         = `~/bin/video/mediaPath` . '/TV';
my $monitoredExec = $ENV{'HOME'} . '/bin/video/torrentMonitored.pl';
my $content =
    '{"method":"torrent-get","arguments":{"fields":["hashString","id","addedDate","comment","creator",'
  . '"dateCreated","isPrivate","name","totalSize","pieceCount","pieceSize","downloadedEver","error","errorString",'
  . '"eta","haveUnchecked","haveValid","leftUntilDone","metadataPercentComplete","peersConnected","peersGettingFromUs",'
  . '"peersSendingToUs","rateDownload","rateUpload","recheckProgress","sizeWhenDone","status","trackerStats",'
  . '"uploadedEver","uploadRatio","seedRatioLimit","seedRatioMode","downloadDir","files","fileStats"]}}';
my $delContent     = '{"method":"torrent-remove","arguments":{"ids":["#_ID_#"], "delete-local-data":"true"}';
my $history        = '{"method":"history","params":[]}';
my $delHistory     = '{"method":"editqueue","params":["historyFinalDelete","",[#_ID_#]]}';
my $delSleep       = 2;
my $RAR_MIN_FILES  = 4;
my $FIND_MAX_DEPTH = 5;
my $CONF_FILE      = $ENV{'HOME'} . '/.download.config';

# Environment
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	if ($ENV{'DEBUG'} =~ /(\d+)/) {
		$DEBUG = $1;
	} else {
		$DEBUG = 1;
	}
}

# Command-line parameters
my ($hash) = @ARGV;

# Config file
my %CONFIG = ();
if ($CONF_FILE && -r $CONF_FILE) {
	my $fh;
	open($fh, '<', $CONF_FILE)
	  or die('Unable to open config file: ' . $CONF_FILE . ': ' . $! . "\n");
	while (<$fh>) {

		# Skip blank lines and comments
		if (/^\s*#/ || /^\s*$/) {
			next;
		}

		# Assume everything else is bash variables
		if (my ($key, undef(), $val) = $_ =~ /^\s*(\S[^\=]+)\=([\'\"])(.*)\g{-2}\s*$/) {
			$CONFIG{$key} = $val;
			if ($DEBUG > 1) {
				print STDERR 'Adding config: ' . $key . ' => ' . $val . "\n";
			}
		} else {
			warn('Ignoring config line: ' . $_ . "\n");
		}
	}
	close($fh);
}

# Init
my $fetch = undef();

# Tranmission
if (available($CONFIG{'TRANS_URL'})) {

	# Fetch the list of paused (i.e. completed) torrents
	$fetch->url($CONFIG{'TRANS_URL'});
	$fetch->post_content($content);
	&fetch($fetch);
	my $torrents = decode_json(scalar($fetch->content()));
	$torrents = $torrents->{'arguments'}->{'torrents'};

	# Process
	if ($DEBUG) {
		print STDERR "Processing torrents...\n";
	}
	foreach my $tor (@{$torrents}) {

		# Skip torrents that aren't yet done
		if ($tor->{'leftUntilDone'} > 0 || $tor->{'metadataPercentComplete'} < 1) {
			next;
		}

		# If a hash is provided, process only that file
		if (defined($hash) && $tor->{'hashString'} ne $hash) {
			if ($DEBUG) {
				printf STDERR 'Skipping torrent with non-matching hash: ' . $tor->{'name'} . ' (' . $tor->{'hashString'} . ")\n";
			}
			next;
		}

		# Process this torrent
		if ($DEBUG) {
			print STDERR 'Processing completed torrent: ' . $tor->{'name'} . "\n";
		}
		if (storeTor($tor)) {
			delTor($tor);
		} else {
			print STDERR 'Unable to store torrent: ' . $tor->{'name'} . "\n";
		}
		next;
	}

	# NZB
	if (available($CONFIG{'NZB_URL'})) {

		# Fetch the list of historical (i.e. completed) NZBs
		$fetch->url($CONFIG{'NZB_URL'});
		$fetch->post_content($history);
		$fetch->fetch();
		my $resp = decode_json(scalar($fetch->content()));
		if (!defined($resp) || ref($resp) ne 'HASH' || !exists($resp->{'result'}) || ref($resp->{'result'}) ne 'ARRAY') {
			print STDERR 'Invalid NZB response: ' . $fetch->content() . "\n";
		}

		# Process
		if ($DEBUG) {
			print STDERR "Processing NZBs...\n";
		}
		foreach my $data (@{ $resp->{'result'} }) {
			my $nzb = undef();
			if (!readNZB(\$nzb, $data)) {
				warn("Unable to parse NZB\n");
				next;
			}

			# If a hash is provided, process only that file
			#if (defined($hash) && $nzb->{'has'} ne $hash) {
			#	if ($DEBUG) {
			#		printf STDERR 'Skipping NZB with non-matching hash: ' . $nzb->{'name'} . ' (' . $nzb->{'hash'} . ")\n";
			#	}
			#	next;
			#}

			# Delete failed NZBs
			if ($nzb->{'status'} eq 'FAILURE/HEALTH' || $nzb->{'status'} eq 'FAILURE/PAR' || $nzb->{'status'} eq 'FAILURE/UNPACK') {
				delNZB($nzb);
				next;
			}

			# Process sucessful NZBs
			if ($nzb->{'status'} eq 'SUCCESS/UNPACK') {
				if (storeNZB($nzb)) {
					delNZB($nzb);
				} else {
					print STDERR 'Unable to store NZB: ' . $nzb->{'name'} . "\n";
				}
				next;
			}
		}
	}
}

# Cleanup
exit(0);

# Grab the session ID
sub session($) {
	my ($fetch) = @_;
	my %headers = ();
	($headers{'X-Transmission-Session-Id'}) = $fetch->content() =~ /X\-Transmission\-Session\-Id\:\s+(\w+)/;
	$fetch->headers(\%headers);
}

sub fetch($) {
	my ($fetch) = @_;
	$fetch->fetch('nocheck' => 1);
	if ($fetch->status_code() != 200) {
		&session($fetch);
		$fetch->fetch();
		if ($fetch->status_code() != 200) {
			die('Unable to fetch: ' . $fetch->status_code() . "\n");
		}
	}
}

sub getSSE($) {
	my ($name) = @_;

	if ($DEBUG) {
		print STDERR 'Finding series/season/episode for: ' . $name . "\n";
	}

	my $season      = 0;
	my $episode     = 0;
	my $seasonBlock = '';
	if ($name =~ /(?:\b|_)(20\d\d(?:\.|\-)[01]?\d(?:\.|\-)[0-3]?\d)(?:\b|_)/) {
		$seasonBlock = $1;
		my ($month, $day);
		($season, $month, $day) = $seasonBlock =~ /(20\d\d)(?:\.|\-)([01]?\d)(?:\.|\-)([0-3]?\d)/;
		$season = int($season);
		$episode = sprintf('%04d-%02d-%02d', $season, $month, $day);
	} elsif ($name =~ /(?:\b|_)(S(?:eason)?[_\s\.\-]*\d{1,2}[_\s\.\-]*E(?:pisode)?[_\s\.]*\d{1,3}(?:E\d{1,3})?)(?:\b|_)/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /S(?:eason)?[_\s\.\-]*(\d{1,2})[_\s\.\-]*E(?:pisode)?[_\s\.\-]*(\d{1,3})/i;
		$season = int($season);
		$episode = sprintf('%02d', int($episode));
	} elsif ($name =~ /\b(\d{1,2}x\d{2,3})\b/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /(\d+)x(\d+)/i;
		$season = int($season);
		$episode = sprintf('%02d', int($episode));
	} elsif ($name =~ /(?:\b|_)([01]?\d[_\s\.]?[0-3]\d)(?:\b|_)/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /(?:\b|_)([01]?\d)[_\s\.]?([0-3]\d)/i;
		$season = int($season);
		$episode = sprintf('%02d', int($episode));
	}
	if (!defined($seasonBlock) || $season < 1 || length($episode) < 1 || $episode eq '0') {
		if ($DEBUG) {
			print STDERR 'Could not find seasonBlock in: ' . $name . "\n";
		}
		return;
	}

	# Assume the series titles comes before the season/episode block
	my $series = '';
	my $sIndex = index($name, $seasonBlock);
	if ($sIndex > 0) {
		$series = substr($name, 0, $sIndex - 1);
		$series = seriesCleanupCore($series);
	}

	if ($DEBUG) {
		print STDERR 'Series: ' . $series . ' Season: ' . $season . ' Episode: ' . $episode . "\n";
	}
	return ($series, $season, $episode);
}

sub getDest($$$$) {
	my ($series, $season, $episode, $ext) = @_;
	if ($DEBUG) {
		print STDERR 'Finding destination for: ' . $series . ' S' . $season . 'E' . $episode . "\n";
	}

	# Input cleanup
	$episode =~ s/^0+//;

	# Find all our existing TV series
	my @shows    = ();
	my %showsCan = ();
	open(SHOWS, '-|', $monitoredExec, 'STORE')
	  or die("Unable to fork: ${!}\n");
	while (<SHOWS>) {
		chomp;
		my $orig  = $_;
		my $clean = seriesCleanupLocal($_);
		push(@shows, $clean);
		$showsCan{$clean} = $orig;
	}
	close SHOWS or die("Unable to read monitored series list: ${!} ${?}\n");

	# See if we can find a unique series name match
	my $sClean     = seriesCleanup($series);
	my $sCleanCore = seriesCleanupCore($series);
	my $sMatch     = '\b' . $sClean . '\b';
	$series = '';

	foreach my $show (@shows) {

		# Match the folder name or the search_name
		my $coarse_match = 0;
		if ($show =~ /${sMatch}/i) {
			$coarse_match = 1;
		} else {
			my $search_name = '';
			my $file        = $tvDir . '/' . $showsCan{$show} . '/search_name';
			if (-e $file) {
				open(FH, $file)
				  or die('Unable to read search_name file: ' . $file . "\n");
				$search_name = <FH>;
				close(FH);
			}
			if ($search_name) {
				$search_name = seriesCleanup($search_name);
				if ($search_name =~ /${sMatch}/i) {
					$coarse_match = 1;
				}
			}
		}

		# If we got a course match, continue checking
		if ($coarse_match) {

			# Enforce any secondary matching rules (for ambiguous titles)
			my $detail_match = 1;
			{
				my @lines;
				my $file = $tvDir . '/' . $showsCan{$show} . '/must_match';
				if (-e $file) {
					local ($/, *FH);
					open(FH, $file)
					  or die('Unable to read must_match file: ' . $file . "\n");
					my @tmp = <FH>;
					close(FH);
					push(@lines, @tmp);
				}
				foreach my $line (@lines) {
					chomp($line);
					if (!eval('$sCleanCore =~ m' . $line)) {
						if ($DEBUG) {
							print STDERR 'Skipping ' . $show . ' due to must_match failure for: ' . $line . "\n";
						}
						$detail_match = 0;
						last;
					}
				}
			}
			if (!$detail_match) {
				next;
			}

			# If we find more than one matching series
			if (length($series) > 0) {

				# If the old match is a subset of the new match, prefer the new match
				# If the new match is a subet of the old match, prefer the old match
				# Bail if the matches do not overlap
				if ($show =~ m/^${series}\b/) {
					if ($DEBUG) {
						print STDERR 'Using longer match ('
						  . $showsCan{$show}
						  . ') in place of shorter match ('
						  . $showsCan{$series} . ")\n";
					}
					$series = $show;
				} elsif ($series =~ m/^${show}\b/) {
					if ($DEBUG) {
						print STDERR 'Using longer match ('
						  . $showsCan{$series}
						  . ') in place of shorter match ('
						  . $showsCan{$show} . ")\n";
					}
					$series = $series;
				} else {
					print STDERR 'Matched both ' . $showsCan{$series} . ' and ' . $showsCan{$show} . "\n";
					return;
				}
			} else {

				# If we're still around this is the first series title match
				$series = $show;
			}
		}
	}
	if (length($series) < 1) {
		if ($DEBUG) {
			print STDERR 'No series match for: ' . $sMatch . "\n";
		}
		return;
	}

	# Lookup the canonical name from the matched name
	$series = $showsCan{$series};

	# Make sure we have the right season folder
	my $seriesDir = $tvDir . '/' . $series;
	my $seasonDir = $seriesDir . '/' . 'Season ' . $season;
	if (!-d $seasonDir) {
		print STDERR 'No season folder for: ' . $series . ' S' . $season . "\n";
		return;
	}

	# Bail if we already have this episode
	my @episodes = readDir($seasonDir, 0);
	foreach my $ep (@episodes) {
		my ($epNum) = $ep =~ /^\s*([\d\-]+)\s*\-\s*/;
		if (!defined($epNum)) {
			next;
		}
		$epNum =~ s/^0+//;
		if ($epNum eq $episode) {
			print STDERR 'Existing episode for: ' . $series . ' S' . $season . 'E' . $episode . "\n";
			return;
		}
	}

	# Construct the final path
	if (!defined($ext) || length($ext) < 1) {
		$ext = 'avi';
	}
	if ($episode =~ /^\d+$/) {
		$episode = sprintf('%02d', $episode);
	}
	my $dest = sprintf('%s/%s - NoName.%s', $seasonDir, $episode, $ext);

	if ($DEBUG) {
		print STDERR 'Destination: ' . $dest . "\n";
	}
	return $dest;
}

sub storeFiles($$$) {
	my ($path, $files, $name) = @_;

	my $failure = 0;
	foreach my $file (@{$files}) {
		my $result = -1;
		if (defined($file) && length($file) > 0 && -r $file) {
			$result = &processFile($file, $path);
		}
		if (defined($result) && $result == 1) {
			if ($DEBUG) {
				print STDERR 'File stored successfully: ' . $name . "\n";
			}
		} elsif (defined($result) && $result == -1) {
			if ($DEBUG) {
				print STDERR 'Refusing to save bad download: ' . $name . "\n";
			}
			last;
		} else {
			print STDERR 'Error storing file "' . basename($file) . '" from: ' . $name . "\n";
			$failure = 1;
			last;
		}
	}

	return $failure ? 0 : 1;
}

sub readNZB($$) {
	my ($nzb, $data) = @_;
	my %tmp = ('id' => undef(), 'name' => undef(), 'status' => undef(), 'path' => undef());

	# Sanity
	if (ref($data) ne 'HASH') {
		print STDERR 'Invalid NZB item: ' . $data . "\n";
		return 0;
	}

	# ID
	if (exists($data->{'ID'})) {
		$tmp{'id'} = int($data->{'ID'});
	}

	# Name
	if (exists($data->{'Name'})) {
		$tmp{'name'} = $data->{'Name'};
	}
	if (!$tmp{'name'} && exists($data->{'NZBName'})) {
		$tmp{'name'} = $data->{'NZBName'};
	}
	if (!$tmp{'name'} && exists($data->{'NZBNicename'})) {
		$tmp{'name'} = $data->{'NZBNicename'};
	}
	if (!$tmp{'name'}) {
		print STDERR 'Unable to retrieve name for: ' . $tmp{'id'} . "\n";
		return 0;
	}

	# Status
	if (exists($data->{'Status'})) {
		$tmp{'status'} = $data->{'Status'};
	}
	if (!$tmp{'status'}) {
		print STDERR 'Unable to retrieve status for: ' . $tmp{'id'} . "\n";
		return 0;
	}

	# Path
	if (exists($data->{'DestDir'})) {
		$tmp{'path'} = $data->{'DestDir'};
	}
	if (!$tmp{'path'}) {
		print STDERR 'Unable to retrieve path for: ' . $tmp{'id'} . "\n";
		return 0;
	}

	# Debug
	if ($DEBUG > 1) {
		print STDERR "\n\n";
		foreach my $key (keys(%tmp)) {
			print STDERR $key . ' => ' . $tmp{$key} . "\n";
		}
	}

	# Store the NZB hash and return success
	${$nzb} = \%tmp;
	return 1;
}

sub storeTor($) {
	my ($tor) = @_;
	if ($DEBUG) {
		print STDERR 'Storing torrent: ' . $tor->{'name'} . "\n";
	}

	# Handle individual files and directories
	my @files    = ();
	my @newFiles = ();
	my $path     = $tor->{'downloadDir'} . '/' . $tor->{'name'};
	if (!-d $path) {
		push(@files, $path);
	} else {

		# State variables
		my $IS_RAR  = '';
		my $IS_FAKE = 0;

		# Look for RAR files
		foreach my $file (@{ $tor->{'files'} }) {
			if ($file->{'name'} =~ /\.rar$/i) {
				$IS_RAR = $tor->{'downloadDir'} . '/' . $file->{'name'};
				last;
			}
		}

		# Check for password files
		foreach my $file (@{ $tor->{'files'} }) {
			if ($file->{'name'} =~ /passw(?:or)?d/i) {
				print STDERR 'Password file detected in: ' . $tor->{'name'} . "\n";
				$IS_FAKE = 1;
				last;
			}
		}

		# Check for single-file RARs
		if ($IS_RAR && scalar(@{ $tor->{'files'} }) < $RAR_MIN_FILES) {
			print STDERR 'Single-file RAR detected in: ' . $tor->{'name'} . "\n";
			$IS_FAKE = 1;
		}

		# Delete fake torrents and bail
		if ($IS_FAKE) {
			if ($DEBUG) {
				print STDERR 'Deleting fake torrent: ' . $tor->{'name'} . "\n";
			}
			delTor($tor);
			next;
		}

		# Unrar if necessary
		if (defined($IS_RAR) && length($IS_RAR) > 0) {
			@newFiles = &unrar($IS_RAR, $path);
		}

		# Find all media files, recursively
		@files = findMediaFiles($path, 0);
	}

	# Process any files we found
	if (scalar(@files) < 1) {
		print STDERR 'No media files found in torrent: ' . $tor->{'name'} . "\n";
		return 0;
	}
	my $retval = storeFiles($path, \@files, $tor->{'name'});

	# Delete any files we added
	foreach my $file (@newFiles) {
		if ($DEBUG) {
			print STDERR 'Deleting new file: ' . basename($file) . "\n";
		}
		unlink($file);
	}

	# Return whatever storeFiles() said
	return $retval;
}

sub storeNZB($) {
	my ($nzb) = @_;
	if ($DEBUG) {
		print STDERR 'Storing NZB: ' . $nzb->{'name'} . "\n";
	}

	# Find all media files, recursively
	my @files = findMediaFiles($nzb->{'path'}, 0);

	# Process any files we found
	if (scalar(@files) < 1) {
		print STDERR 'No media files found in NZB: ' . $nzb->{'name'} . "\n";
		next;
	}
	return storeFiles($nzb->{'path'}, \@files, $nzb->{'name'});
}

sub delNZB($) {
	my ($nzb) = @_;
	if ($DEBUG) {
		print STDERR 'Deleting NZB: ' . $nzb->{'name'} . "\n";
	}

	# Remove the files, if any
	if (-e $nzb->{'path'} && -d $nzb->{'path'}) {
		if ($DEBUG) {
			print STDERR 'Removing NZB folder: ' . $nzb->{'path'} . "\n";
		}
		remove_tree($nzb->{'path'});

		# Check for deletion
		if (-e $nzb->{'path'}) {
			print STDERR 'Unable to remove NZB folder: ' . $nzb->{'path'} . "\n";
			return 0;
		}
	}

	# Send the command
	my $id      = $nzb->{'id'};
	my $content = $delHistory;
	$content =~ s/\#_ID_\#/${id}/;
	$fetch->post_content($content);
	$fetch->fetch();

	# Check the result
	if ($fetch->content() =~ /\"result\" \: true/i) {
		return 1;
	}
	return 0;
}

sub delTor($) {
	my ($tor) = @_;
	if ($DEBUG) {
		print STDERR 'Deleting torrent: ' . $tor->{'name'} . "\n";
	}

	# Sleep to avoid bugs in Transmission (i.e. multiple deletes fail)
	sleep($delSleep);

	# Construct the content
	my $id      = $tor->{'hashString'};
	my $content = $delContent;
	$content =~ s/\#_ID_\#/${id}/;

	# Send the command
	&session($fetch);
	$fetch->post_content($content);
	&fetch($fetch);
}

sub guessExt($) {
	my ($file) = @_;
	my $ext = '';

	# Believe most non-avi file extensions without checking
	# It's mostly "avi" that lies, and the checks are expensive
	{
		my $orig_ext = basename($file);
		$orig_ext =~ s/^.*\.(\w{2,3})$/$1/;
		$orig_ext = lc($orig_ext);
		if ($orig_ext eq 'mkv' || $orig_ext eq 'ts') {
			$ext = $orig_ext;
		}
	}

	# Deal with the weird case of text files labeled as .txt.mp4
	if ($file =~ /\.txt\.mp4$/i) {
		$ext = 'txt';
	}

	# Guess the file type if we don't have one yet
	if (!$ext) {

		my $mime  = '';
		my $demux = '';

		# Try ExifTool for MIME and demuxer types
		if (!$mime || !$demux) {
			my $exif = ImageInfo($file);
			if (defined($exif) && ref($exif) eq 'HASH') {
				if ($exif->{'MIMEType'}) {
					$mime = $exif->{'MIMEType'};
				}
				if ($exif->{'FileType'}) {
					$demux = $exif->{'FileType'};
				}
			}
		}

		# Try file(1) for MIME types
		if (!$mime) {
			open(FILE, '-|', 'file', '-b', $file);
			while (<FILE>) {
				$mime .= $_;
			}
			close(FILE);
		}

		# Cleanup the demuxer and MIME types
		$demux =~ s/^\s+//;
		$demux =~ s/\s+$//;
		$mime =~ s/^\s+//;
		$mime =~ s/\s+$//;
		$mime =~ s/\;.*$//;
		$mime =~ s/^video\///i;

		# Try to pick an extension we understand
		if ($demux =~ /MKV/i || $mime =~ /Matroska/i) {
			$ext = 'mkv';
		} elsif ($demux =~ /ASF/i || $mime =~ /\bASF\b/i) {
			$ext = 'wmv';
		} elsif ($demux =~ /MP4/i || $mime =~ /\bMP4\b/i) {
			$ext = 'mp4';
		} elsif ($mime =~ /\bZIP/i) {
			$ext = 'zip';
		} elsif ($demux =~ /MPEGTS/i) {
			$ext = 'ts';
		} else {
			$ext = 'avi';
		}
	}

	return $ext;
}

sub processFile($$) {
	my ($file, $path) = @_;
	if ($DEBUG) {
		print STDERR 'Attempting to process file: ' . basename($file) . "\n";
	}

	# Skip known packaging files files with success code
	if ($file =~ /\/RARBG\.com\.(?:mp4|avi|mkv|txt)$/i || $file =~ /\.txt\.(?:mp4|avi|mkv)$/) {
		if ($DEBUG) {
			print STDERR 'Declining to save packaging file: ' . $file . "\n";
		}
		return 1;
	}

	# Guess a file extension and basename
	my $ext      = &guessExt($file);
	my $filename = basename($file);

	# Delete WMV files -- mostly viruses/fake
	if ($ext =~ /wmv/i) {
		if ($DEBUG) {
			print STDERR 'Declining to save WMV file: ' . $filename . "\n";
		}
		return -1;
	}

	# Delete ZIP files -- mostly fake
	if ($ext =~ /zip/i) {
		if ($DEBUG) {
			print STDERR 'Declining to save ZIP file: ' . $filename . "\n";
		}
		return -1;
	}

	# Allow multiple guesses at the series/season/episode
	my $dest = '';
  LOOP: {

		# Determine the series, season, and episode number
		my ($series, $season, $episode) = &getSSE($filename);
		if (   defined($series)
			&& length($series) > 0
			&& defined($season)
			&& $season > 0
			&& defined($episode)
			&& length($episode) > 0
			&& $episode ne '0')
		{

			# Find the proper destination for this torrent, if any
			$dest = &getDest($series, $season, $episode, $ext);
		}

		# Sanity/loop check
		if (!defined($dest) || length($dest) < 1) {

			# If there is no match but the torrent is a folder
			# retry the guess using the torrent path
			if ($file ne $path) {
				my $newName = basename($path);
				if ($newName ne $filename) {
					$filename = basename($path);
					redo LOOP;
				}
			}

			# Otherwise we just fail
			print STDERR 'No destination for: ' . basename($file) . "\n";
			return;
		}
	}

	# Copy (to let Transmission deal with local cleanup) and rename into place
	my $tmp = mktemp($dest . '.XXXXXXXX');
	copy($file, $tmp);
	rename($tmp, $dest);

	# Touch to avoid carrying dates set in the download process
	touch($dest);

	# Return success
	return 1;
}

sub unrar($$) {
	my ($file, $path) = @_;
	if ($DEBUG) {
		print STDERR 'UnRARing: ' . basename($file) . "\n";
	}

	# Keep a list of old files, so we can find/delete the output
	my @beforeFiles = readDir($path, 1);

	# Run the unrar utility
	my $pid = fork();
	if (!defined($pid)) {
		print STDERR "Unable to fork for RAR\n";
		return;
	} elsif ($pid == 0) {

		# Child
		close(STDOUT);
		close(STDERR);
		chdir($path);
		my @args = ('unrar', 'e', '-p-', '-y', $file);
		exec { $args[0] } @args;
	}

	# Wait for the child
	waitpid($pid, 0);

	# Compare the old file list to the new one
	my @newFiles = ();
	my @afterFiles = readDir($path, 1);
	foreach my $file (@afterFiles) {
		my $found = 0;
		foreach my $file2 (@beforeFiles) {
			if ($file eq $file2) {
				$found = 1;
				last;
			}
		}
		if (!$found) {
			push(@newFiles, $file);
		}
	}

	# Return the list of added files
	return @newFiles;
}

sub seriesCleanupLocal($) {
	my ($name) = @_;
	$name =~ s/\.//g;
	return seriesCleanupCore($name);
}

sub seriesCleanupCore($) {
	my ($name) = @_;
	$name =~ s/^.*\[[^\]]*\]\s+//;
	$name =~ s/\b(?:and|\&)\b/ /ig;
	$name =~ s/^\s*The\b//ig;
	$name =~ s/\[[^\]]*\]//g;
	$name =~ s/\{[^\}]*\}//g;
	$name =~ s/[\(\)]//g;
	$name =~ s/[\'\"]//g;
	$name =~ s/[^\w\s]+/ /g;
	$name =~ s/_+/ /g;
	$name =~ s/\s+/ /g;
	$name =~ s/^\s*//;
	$name =~ s/\s*$//;
	return $name;
}

sub seriesCleanup($) {
	my ($name) = @_;
	$name =~ s/\s*\(?US\)?\s*$//;
	$name =~ s/\s*\(?20[01][0-9]\)?\s*$//;
	return seriesCleanupCore($name);
}

sub readDir($$) {
	my ($indir, $long) = @_;

	# Clean up the input directory
	$indir =~ s/\/+$//;

	my @files = ();
	if (!opendir(DIR, $indir)) {
		warn('readDir: Unable to read directory: ' . $indir . ': ' . $! . "\n");
		return;
	}
	foreach my $file (readdir(DIR)) {
		my $keep = 0;

		# Skip junk
		if (   $file eq '.'
			|| $file eq '..'
			|| $file =~ /\._/)
		{
			next;
		}

		# Save the full path
		if ($long) {
			push(@files, $indir . '/' . $file);
		} else {
			push(@files, $file);
		}
	}
	closedir(DIR);

	# Sorts the files before returning to the caller
	my @orderedFiles = ();
	@orderedFiles = sort(@files);

	# Return the file list
	return (@orderedFiles);
}

sub findMediaFiles($$) {
	my ($path, $depth) = @_;
	my @files = ();

	# Recursion limit
	if ($depth > $FIND_MAX_DEPTH) {
		return ();
	}

	my @tmpFiles = readDir($path, 1);
	foreach my $file (@tmpFiles) {

		# Skip sample files
		if ($file =~ /sample/i) {
			next;
		}

		# Recurse on directories
		if (-d $file) {
			push(@files, findMediaFiles($file, $depth + 1));
			next;
		}

		# Save matching files
		if ($file =~ /\.(?:avi|mkv|m4v|mov|mp4|ts|wmv)$/i) {
			push(@files, $file);
			next;
		}
	}
	return @files;
}

# Check availability of web interface
sub available($) {
	my ($url) = @_;
	if ($DEBUG) {
		print STDERR "Checking for interface\n";
	}

	# Reset from the last host
	$fetch = Fetch->new();

	my ($host) = $url =~ /^(\w+\:\/\/[^\/]+\/?)/;
	$fetch->url($host);
	if ($fetch->fetch('nocheck' => 1) != 200) {
		if ($DEBUG) {
			print STDERR 'Code: ' . $fetch->status_code() . "\n";
			print STDERR 'Content: ' . $fetch->content() . "\n";
			warn('Interface not available: ' . $host . "\n");
		}
		return 0;
	}
	return 1;
}
