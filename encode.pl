#!/usr/bin/perl
use strict;
use warnings;

# Includes
use IPC::Open3;
use File::Basename;

# Default configuration
my $FORMAT              = 'mp4';
my $AUDIO_BITRATE       = 192;
my $QUALITY             = 20;
my $HD_QUALITY          = 22;
my $AUDIO_COPY          = 0;
my $STEREO_ONLY         = 0;
my $HEIGHT              = undef();
my $WIDTH               = undef();
my $AUDIO_EXCLUDE_REGEX = '\b(?:Chinese|Espanol|Francais|Japanese|Korean|Portugues|Thai)\b';
my $SUB_INCLUDE_REGEX   = '\b(?:English|Unknown|Closed\s+Captions)\b';
my $FORCE_MP4           = 0;

# Applicaton configuration
my $HD_WIDTH         = 1350;
my $MIN_VIDEO_WIDTH  = 100;
my $MAX_CROP_DIFF    = .1;
my $MAX_DURA_DIFF    = 5;
my @CODEC_ORDER      = ('DTS-HD', 'DTS', 'PCM', 'AC3', 'AAC', 'OTHER');
my %LANG_INCLUDE_ISO = ('639-1' => 1);
my $HB_EXEC          = $ENV{'HOME'} . '/bin/video/HandBrakeCLI';
my $DEBUG            = 0;

# General parameters for HandBrake
my @video_params = ('--markers', '--large-file', '--optimize', '--encoder', 'x264', '--detelecine', '--decomb', '--loose-anamorphic', '--modulus', '16', '--encopts', 'b-adapt=2:rc-lookahead=50');
my @audio_params = ('--audio-copy-mask', 'dtshd,dts,ac3,aac', '--audio-fallback', 'ffac3', '--mixdown', 'dpl2');

# Runtime debug mode
if (defined($ENV{'DEBUG'}) && $ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Shortcut config
if ($ENV{'MOBILE'}) {
	$ENV{'QUALITY'}       = 25;
	$ENV{'HEIGHT'}        = 720;
	$ENV{'WIDTH'}         = 1280;
	$ENV{'AUDIO_BITRATE'} = 128;
	$ENV{'STEREO_ONLY'}   = 1;
	$ENV{'FORCE_MP4'}     = 1;
}

# Additional arguments for HandBrake
# Split on spaces; if you need spaces you'll have to work out something else
if ($ENV{'HANDBRAKE_ARGS'}) {
	my @args = split(/\s+/, $ENV{'HANDBRAKE_ARGS'});
	push(@video_params, @args);
}

# Allow overrides for audio languages
if ($ENV{'AUDIO_EXCLUDE_REGEX'}) {
	$AUDIO_EXCLUDE_REGEX = $ENV{'AUDIO_EXCLUDE_REGEX'};
}

# Allow overrides for subtitle languages
if ($ENV{'SUB_INCLUDE_REGEX'}) {
	$SUB_INCLUDE_REGEX = $ENV{'SUB_INCLUDE_REGEX'};
}

# Allow copy-only audio transfers (for use in re-encoding)
if ($ENV{'AUDIO_COPY'}) {
	$AUDIO_COPY = 1;
}

# Allow AAC-only audio transfers (for use in mobile encoding)
if ($ENV{'STEREO_ONLY'}) {
	$STEREO_ONLY = 1;
}

# Allow MP4-only output format (for use in mobile encoding)
if ($ENV{'FORCE_MP4'}) {
	$FORCE_MP4 = 1;
}

# Allow overrides for video quality
if ($ENV{'QUALITY'}) {
	$QUALITY    = $ENV{'QUALITY'};
	$HD_QUALITY = $ENV{'QUALITY'};
}

# Allow overrides for audio bitrate
if ($ENV{'AUDIO_BITRATE'}) {
	$AUDIO_BITRATE = $ENV{'AUDIO_BITRATE'};
}

# Allow overrides for video height and width. The default is "same as source".
if ($ENV{'HEIGHT'}) {
	$HEIGHT = $ENV{'HEIGHT'};
}
if ($ENV{'WIDTH'}) {
	$WIDTH = $ENV{'WIDTH'};
}

# Command-line parameters
my ($in_file, $out_file, $title) = @ARGV;
if (!defined($in_file) || length($in_file) < 1 || !-r $in_file) {
	die('Usage: ' . basename($0) . " in_file [out_file] [title]\n");
}

# Scan for title/track info
my %titles = &scan($in_file);

# Allow external subtitles for single-title files
if (scalar(keys(%titles)) == 1) {
	my $srt_file = $in_file;
	$srt_file =~ s/\.\w{2,4}$/.srt/;
	if (!-r $srt_file) {
		$srt_file =~ s/\.\w{2,4}$/.ssa/;
	}
	if (-r $srt_file) {
		if ($DEBUG) {
			print STDERR 'Adding subtitles from: ' . $srt_file . "\n";
		}
		push(@video_params, '--srt-file', $srt_file);
	}
}

# Allow encoding of a specific title
if ($title) {
	if ($title =~ /^\d+$/ && $title > 0) {
		if (!defined($titles{$title})) {
			die(basename($0) . ': Invalid title number: ' . $title . "\n");
		}
		my $selected_title = $titles{$title};
		%titles = ();
		$titles{$title} = $selected_title;
	} elsif ($title =~ /main/i) {
		my $max_title    = 0;
		my $max_duration = 0;
		foreach my $title (keys(%titles)) {
			if (!$titles{$title}{'duration'}) {
				warn(basename($0) . ': Unknown duration for title: ' . $title . "\n");
				next;
			}
			my $new_max = 0;
			if (abs($titles{$title}{'duration'} - $max_duration) < $MAX_DURA_DIFF) {
				if ($titles{$title}{'aspect'} > $titles{$max_title}{'aspect'}) {
					$new_max = 1;
				} elsif ($titles{$title}{'size'}[0] > $titles{$max_title}{'size'}[0] || $titles{$title}{'size'}[1] > $titles{$max_title}{'size'}[1]) {
					$new_max = 1;
				}
			} elsif ($titles{$title}{'duration'} > $max_duration) {
				$new_max = 1;
			}
			if ($new_max) {
				$max_duration = $titles{$title}{'duration'};
				$max_title    = $title;
			}
		}
		my $selected_title = $titles{$max_title};
		%titles = ();
		$titles{$max_title} = $selected_title;
	}
}

# Ensure we have an output file name
# Force MKV output if the output file name is provided and ends in .MKV
if (!defined($out_file) || length($out_file) < 1) {
	$out_file = $in_file;
} else {
	my ($force_format) = $out_file =~ /\.(\w{2,4})$/;
	if (defined($force_format) && lc($force_format) eq 'mkv') {
		$FORMAT = 'mkv';
	}
}

# Keep the original format around so we can reset between tracks
my $FORMAT_ORIG = $FORMAT;

# Encode each title
foreach my $title (keys(%titles)) {
	if ($DEBUG) {
		print STDERR 'Setting options for title: ' . $title . "\n";
	}

	# Reset
	$FORMAT = $FORMAT_ORIG;

	# Parse the title's audio and subtitle tracks
	my $scan  = $titles{$title};
	my @audio = &audioOptions($scan);
	my @subs  = &subOptions($scan);

	# Skip tracks that have no video
	if (scalar(@{ $scan->{'size'} }) < 2 || $scan->{'size'}[0] < $MIN_VIDEO_WIDTH) {
		print STDERR basename($0) . ': No video detected in: ' . $in_file . ':' . $title . ". Skipping title...\n";
		next;
	}

	# Skip tracks that have no audio
	if (scalar(@{ $scan->{'audio'} }) < 1 || scalar(@audio) < 1) {
		print STDERR basename($0) . ': No audio detected in: ' . $in_file . ':' . $title . ". Skipping title...\n";
		next;
	}

	# Set the audio quality for re-encoded tracks
	push(@audio, '--ab', $AUDIO_BITRATE);

	# Set the video quality, using $HD_QUALITY for images larger than $HD_WIDTH (to allow lower quality on HD streams)
	my $title_quality = $QUALITY;
	if ($scan->{'size'}[0] > $HD_WIDTH) {
		$title_quality = $HD_QUALITY;
	}

	# Override unlikely autocrop values
	if (   abs($scan->{'crop'}[0] - $scan->{'crop'}[1]) > $scan->{'size'}[0] * $MAX_CROP_DIFF
		|| abs($scan->{'crop'}[2] - $scan->{'crop'}[3]) > $scan->{'size'}[0] * $MAX_CROP_DIFF)
	{
		print STDERR basename($0) . ': Overriding unlikely autocrop values: ' . join(':', @{ $scan->{'crop'} }) . "\n";
		my @crop = (0, 0, 0, 0);
		$scan->{'crop'} = \@crop;
	}

	# Force MKV muxing if the output contains PGS subtitles (there's no support in the MP4 muxer)
	foreach my $track (values(%{ $scan->{'subtitle_selected'} })) {
		if ($track->{'type'} eq 'PGS') {
			$FORMAT = 'mkv';
			last;
		}
	}

	# Force MKV muxing if the output contains DTS audio (technically MP4 is supported buy QuickTime hates it)
	foreach my $track (values(%{ $scan->{'audio_selected'} })) {
		if ($track->{'codec'} =~ /DTS/i) {
			$FORMAT = 'mkv';
			last;
		}
	}

	# Select a file name extension that matches the format
	my $title_out_file = $out_file;
	$title_out_file =~ s/\.(?:\w{2,4}|dvdmedia)$//i;
	if ($FORMAT eq 'mkv') {
		$title_out_file .= '.mkv';
	} else {
		$title_out_file .= '.m4v';
	}

	# Force the title number into the output file name if there are multiple titles to be encoded
	if (scalar(keys(%titles)) > 1) {
		my $title_text = sprintf('%02d', $title);
		$title_out_file =~ s/(\.\w{2,4})$/\-${title_text}${1}/;
	}

	# Limit the maximum height and width, if any is specified
	if ($HEIGHT) {
		push(@video_params, '--maxHeight', $HEIGHT);
	}
	if ($WIDTH) {
		push(@video_params, '--maxWidth', $WIDTH);
	}

	# Output file
	if (uc($title_out_file) eq uc($in_file)) {
		$title_out_file =~ s/(\.\w{2,4})$/-recode${1}/;
	}

	# Build the arugment list
	my @args = ($HB_EXEC);
	push(@args, '--title',   $title);
	push(@args, '--input',   $in_file);
	push(@args, '--output',  $title_out_file);
	push(@args, '--format',  $FORMAT);
	push(@args, '--quality', $title_quality);
	push(@args, '--crop',    join(':', @{ $scan->{'crop'} }));
	push(@args, @video_params);
	push(@args, @audio_params);
	push(@args, @audio);
	push(@args, @subs);

	if ($DEBUG) {
		print STDERR "\n" . join(' ', @args) . "\n\n";
	}

	# Sanity check
	if (-e $title_out_file) {
		print STDERR basename($0) . ': Output file exists: ' . $title_out_file . ". Skipping...\n";
		next;
	}

	# Run it
	my $child_out = '';
	my $child_in  = '';
	my $pid       = open3($child_in, $child_out, $child_out, @args);
	close($child_in);
	while (<$child_out>) {
		if ($DEBUG) {
			print STDERR $_;
		}
	}
	waitpid($pid, 0);
	close($child_out);

	# Provide the new file name if requested
	if ($ENV{'RECODE_OUTFILE'}) {
		print $title_out_file;
	}
}

# Cleanup
exit(0);

sub subOptions($) {
	my ($scan) = @_;

	my %tracks = ();
	foreach my $track (@{ $scan->{'subtitle'} }) {
		my ($language, $note, $iso, $text, $type) = $track->{'description'} =~ /^([^\(]+)(?:\s+\(([^\)]+)\))?\s+\(iso(\d+\-\d+)\:\s+\w\w\w\)\s+\((Text|Bitmap)\)\((CC|VOBSUB|PGS|SSA|TX3G|UTF\-\d+)\)/i;
		if (!defined($iso)) {
			print STDERR 'Could not parse subtitle description: ' . $track->{'description'} . "\n";
			next;
		}

		# Map text/bitmap into a boolean
		if ($text =~ /TEXT/i) {
			$text = 1;
		} else {
			$text = 0;
		}

		# Standardize the codes
		$iso  = uc($iso);
		$type = uc($type);

		# Push all parsed data into an array
		my %data = ('language' => $language, 'note' => $note, 'iso' => $iso, 'text' => $text, 'type' => $type);
		$tracks{ $track->{'index'} } = \%data;

		# Print what we found
		if ($DEBUG) {
			print STDERR 'Found subtitle track: ';
			printHash(\%data);
		}
	}

	# Push the parsed data back up the chain
	$scan->{'subtitle_parsed'} = \%tracks;

	# Select the subtitle tracks we want to keep
	my @keep = ();
	foreach my $index (keys(%tracks)) {

		# Skip PGS tracks when we're forcing MP4 output (they're not allowed by the muxer)
		if ($FORCE_MP4 && $tracks{$index}->{'type'} eq 'PGS') {
			next;
		}

		# Keep tracks in our prefered language, and all text-based subtitles (they're small)
		if (isValidSubLanguage($tracks{$index}->{'language'}, $tracks{$index}->{'iso'})) {
			push(@keep, $index);
		} elsif ($tracks{$index}->{'text'}) {
			push(@keep, $index);
		} else {
			if ($DEBUG) {
				print STDERR 'Skipping subtitle ' . $index . ' due to language: ' . $tracks{$index}->{'language'} . "\n";
			}
		}
	}

	# Push the selected tracks back up the chain
	my %tmp = ();
	foreach my $num (@keep) {
		$tmp{$num} = $tracks{$num};
	}
	$scan->{'subtitle_selected'} = \%tmp;

	# Send back the argument string (if any)
	if (scalar(@keep) < 1) {
		return '';
	}
	return ('--subtitle', join(',', @keep));
}

sub audioOptions($) {
	my ($scan) = @_;

	# Type the audio tracks
	my %tracks = ();
	foreach my $track (@{ $scan->{'audio'} }) {
		my ($language, $codec, $note, $channels, $iso) = $track->{'description'} =~ /^([^\(]+)\s+\(([^\)]+)\)\s+(?:\(([^\)]*Commentary[^\)]*)\)\s+)?\((\d+\.\d+\s+ch|Dolby\s+Surround)\)(?:\s+\(iso(\d+\-\d+)\:\s+\w\w\w\))?/;
		if (!defined($channels)) {
			print STDERR 'Could not parse audio description: ' . $track->{'description'} . "\n";
			next;
		}

		# Decode the channels string to a number
		if ($channels =~ /(\d+\.\d+)\s+ch/i) {
			$channels = $1;
		} elsif ($channels =~ /Dolby\s+Surround/i) {
			$channels = 3.1;
		}

		# Standardize the codec
		foreach my $code (@CODEC_ORDER) {
			my $metacode = quotemeta($code);
			if ($codec =~ /${metacode}/i) {
				$codec = $code;
				last;
			} elsif ($code eq 'OTHER') {
				if ($codec =~ /MP3/i || $codec =~ /MPEG/i) {
					$codec = $code;
				} elsif ($codec eq 'truehd' || $codec eq 'dca') {
					print STDERR 'Found incompatible audio (' . $track->{'description'} . ')  in track ' . $track->{'index'} . "\n";
					$codec = undef();
				} else {
					print STDERR 'Found unknown audio (' . $track->{'description'} . ') in track ' . $track->{'index'} . "\n";
					$codec = $code;
				}
			}
		}

		# Push all parsed data into the array
		my %data = ('language' => $language, 'codec' => $codec, 'channels' => $channels, 'iso' => $iso, 'note' => $note);
		$tracks{ $track->{'index'} } = \%data;

		# Print what we found
		if ($DEBUG) {
			print STDERR 'Found audio track: ';
			printHash(\%data);
		}
	}

	# Push the parsed data back up the chain
	$scan->{'audio_parsed'} = \%tracks;

	# Find the track with the most channels for each codec, and the highest number of channels among all types of tracks
	# Then choose the most desired codec among the set of codecs that contain the highest number of channels
	# This chooses the track with the most channels for the mixdown, and resolves ties using CODEC_ORDER
	my $mixdown      = undef();
	my %bestByCodec  = ();
	my $bestCodec    = undef();
	my $mostChannels = 0;
	foreach my $codec (@CODEC_ORDER) {
		$bestByCodec{$codec} = findBestAudioTrack(\%tracks, $codec);
		if (defined($bestByCodec{$codec}) && (!defined($bestCodec) || $mostChannels < $tracks{ $bestByCodec{$codec} }->{'channels'})) {
			$bestCodec    = $codec;
			$mostChannels = $tracks{ $bestByCodec{$codec} }->{'channels'};
		}
	}
	foreach my $codec (@CODEC_ORDER) {
		if (defined($bestByCodec{$codec}) && $tracks{ $bestByCodec{$codec} }->{'channels'} == $mostChannels) {
			$mixdown = $bestByCodec{$codec};
			last;
		}
	}

	# Sanity check
	if (!defined($mixdown) || $mixdown < 1) {
		print STDERR basename($0) . ": No usable audio tracks in title\n";
		return;
	}

	# Clear the mixdown selection if we're copying audio
	if ($AUDIO_COPY) {
		$mixdown = undef();
	}

	# Mixdown track first
	my @audio_tracks = ();
	if (defined($mixdown) && $mixdown > 0) {
		if ($DEBUG) {
			print STDERR 'Using track ' . $mixdown . " as default AAC audio\n";
			if ($tracks{$mixdown}->{'channels'} > 2) {
				print STDERR "\tMixing down with Dolby Pro Logic II encoding\n";
			}
		}
		my %track = ('index' => $mixdown, 'encoder' => 'ca_aac');
		push(@audio_tracks, \%track);
	}

	# Keep all other audio tracks, unless STEREO_ONLY is set
	if (!$STEREO_ONLY) {

		# Passthru DTS-MA, DTS, AC3, and AAC
		# Keep other audio tracks, but recode to AAC (using Handbrake's audio-copy-mask/audio-fallback feature)
		foreach my $index (keys(%tracks)) {
			if ($mixdown == $index && $tracks{$index}->{'codec'} eq 'OTHER' && $tracks{$index}->{'channels'} <= 2) {
				if ($DEBUG) {
					print STDERR 'Skipping recode of track ' . $index . ' since it is already used as the default track and contains only ' . $tracks{$index}->{'channels'} . " channels\n";
				}
				next;
			} elsif (!$tracks{$index}->{'codec'}) {
				if ($DEBUG) {
					print STDERR 'Skipping track ' . $index . " due to invalid codec\n";
				}
				next;
			} elsif (!isValidAudioLanguage($tracks{$index}->{'language'}, $tracks{$index}->{'iso'})) {
				if ($DEBUG) {
					print STDERR 'Skipping track ' . $index . ' due to language: ' . $tracks{$index}->{'language'} . "\n";
				}
				next;
			} else {
				my %track = ('index' => $index, 'encoder' => 'copy');
				push(@audio_tracks, \%track);
			}
		}
	}

	# Push the selected tracks back up the chain
	my %tmp = ();
	foreach my $track (@audio_tracks) {
		$tmp{ $track->{'index'} } = $track;
	}
	$scan->{'audio_selected'} = \%tmp;

	# Consolidate from the hashes
	my @output_tracks   = ();
	my @output_encoders = ();
	foreach my $track (@audio_tracks) {
		push(@output_tracks,   $track->{'index'});
		push(@output_encoders, $track->{'encoder'});
	}

	# Send back the argument strings
	return ('--audio', join(',', @output_tracks), '--aencoder', join(',', @output_encoders));
}

sub scan($) {
	my ($in_file) = @_;

	# Fork to scan the file
	my $child_out = '';
	my $pid = open3('<&STDIN', $child_out, $child_out, $HB_EXEC, '--title', '0', '--input', $in_file);

	# Loop through the output
	my $scan;
	my %titles  = ();
	my $inTitle = 0;
	my $zone    = '';
	while (<$child_out>) {

		if (!$inTitle && m/scan thread found (\d+) valid title/i) {
			if ($DEBUG) {
				print STDERR 'Found ' . $1 . " titles in source\n";
			}
		} elsif (m/^\s+Stream \#0\.(\d+)\(\w+\)\:\s+(.*)/) {
			my $stream = $1;
			my $desc   = $2;
		} elsif (m/^\s*\+\s+title\s+(\d+)\:/) {

			# Save the current title (if any)
			if ($inTitle) {
				$titles{$inTitle} = $scan;
			}

			# Grab the new title number
			$inTitle = $1;

			# Init the data collectors
			my @audio    = ();
			my @crop     = ();
			my @subtitle = ();
			my @size     = ();
			my %tmp      = (
				'audio'    => \@audio,
				'crop'     => \@crop,
				'subtitle' => \@subtitle,
				'size'     => \@size,
				'duration' => 0,
				'aspect'   => 0
			);
			$scan = \%tmp;

			if ($DEBUG) {
				print STDERR 'Found data for title ' . $1 . "\n";
			}
		} elsif ($inTitle) {
			if (/^\s*\+\s+size: (\d+)x(\d+)/) {
				push(@{ $scan->{'size'} }, $1, $2);
				if ($DEBUG) {
					print STDERR 'Size: ' . join('x', @{ $scan->{'size'} }) . "\n";
				}
				if (/\s+display aspect\: (\d*\.\d+)/) {
					$scan->{'aspect'} = $1;
					if ($DEBUG) {
						print STDERR 'Aspect: ' . $scan->{'aspect'} . "\n";
					}
				}
			} elsif (/^\s*\+\s+duration\:\s+(\d+)\:(\d+)\:(\d+)/) {
				$scan->{'duration'} = ($1 * 3600) + ($2 * 60) + $3;
				if ($DEBUG) {
					print STDERR 'Duration: ' . $scan->{'duration'} . "\n";
				}
			} elsif (/^\s*\+\s+autocrop\:\s+(\d+)\/(\d+)\/(\d+)\/(\d+)/) {
				push(@{ $scan->{'crop'} }, $1, $2, $3, $4);
				if ($DEBUG) {
					print STDERR 'Crop: ' . join('/', @{ $scan->{'crop'} }) . "\n";
				}
			} elsif ($zone ne 'audio' && /^\s*\+\s+audio\s+tracks\:\s*$/) {
				$zone = 'audio';
			} elsif ($zone eq 'audio' && /^\s*\+\s+(\d+)\,\s+(.*)/) {
				my %track = ('index' => $1, 'description' => $2);
				push(@{ $scan->{'audio'} }, \%track);
				if ($DEBUG) {
					print STDERR 'Audio Track #' . $track{'index'} . ': ' . $track{'description'} . "\n";
				}
			} elsif ($zone ne 'subtitle' && /^\s*\+\s+subtitle\s+tracks\:\s*$/) {
				$zone = 'subtitle';
			} elsif ($zone eq 'subtitle' && m/^\s*\+\s+(\d+)\,\s+(.*)$/) {
				my %track = ('index' => $1, 'description' => $2);
				push(@{ $scan->{'subtitle'} }, \%track);
				if ($DEBUG) {
					print STDERR 'Subtitle Track #' . $track{'index'} . ': ' . $track{'description'} . "\n";
				}
			}
		}
	}

	# Save the last title (if any)
	if ($inTitle) {
		$titles{$inTitle} = $scan;
	}

	# Cleanup the scan process
	waitpid($pid, 0);
	close($child_out);

	# Sanity check
	if (scalar(keys(%titles)) < 1) {
		die(basename($0) . ': Did not find any titles in file: ' . $in_file . "\n");
	}

	# Return
	return %titles;
}

sub findBestAudioTrack($$) {
	my ($tracks, $codec) = @_;
	my $best     = undef();
	my $channels = 0;

	for my $index (keys(%{$tracks})) {
		my $track = $tracks->{$index};

		# Skip tracks not in the specified codec
		if (!$track->{'codec'} || $track->{'codec'} ne $codec) {
			next;
		}

		# Skip foreign language tracks
		if (!isValidAudioLanguage($track->{'language'}, $track->{'iso'})) {
			next;
		}

		# Find the track with the most channels (Ófirst wins)
		if (!defined($best) || $track->{'channels'} > $channels) {
			$best     = $index;
			$channels = $track->{'channels'};
		}
	}

	return $best;
}

sub isValidSubLanguage($) {
	my ($lang, $iso) = @_;

	if (scalar(keys(%LANG_INCLUDE_ISO)) && $LANG_INCLUDE_ISO{$iso}) {
		return 1;
	} elsif ($SUB_INCLUDE_REGEX && $lang =~ /${SUB_INCLUDE_REGEX}/i) {
		return 1;
	}

	return 0;
}

sub isValidAudioLanguage($) {
	my ($lang, $iso) = @_;

	if (scalar(keys(%LANG_INCLUDE_ISO)) && $LANG_INCLUDE_ISO{$iso}) {
		return 1;
	} elsif ($AUDIO_EXCLUDE_REGEX && $lang =~ /${AUDIO_EXCLUDE_REGEX}/i) {
		return 0;
	}

	return 1;
}

sub printHash($) {
	my ($data) = @_;

	my $first = 1;
	foreach my $key (keys(%{$data})) {
		if (defined($data->{$key})) {
			if ($first) {
				$first = 0;
			} else {
				print STDERR ', ';
			}
			print STDERR $key . ' => ' . $data->{$key};
		}
	}
	print STDERR "\n";
}
