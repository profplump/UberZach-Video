#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;

# App config
my $HTTP_TIMEOUT = 10;
my $HTTP_UA      = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.75.14 (KHTML, like Gecko) Version/7.0.3 Safari/7046A194A';
my $HTTP_VERIFY  = 0;

# Globals
my $LWP;
my $QUALITY_URL;
my $STREAM_URL;

# Command-line parameters
if (scalar(@ARGV) < 1) {
	die('Usage: ' . $0 . "M3U8_URL\n");
}
$QUALITY_URL = $ARGV[0];

# Environmental parameters
my $DEBUG = 0;
if (defined($ENV{'DEBUG'}) && $ENV{'DEBUG'} =~ /(\d+)/) {
	$DEBUG = $1;
}

# Prototypes
sub fetch($$);

# Fetch and parse the quality playlist
{
	my $playlist;
	if (fetch($QUALITY_URL, \$playlist) == 200) {
		if ($DEBUG > 1) {
			print STDERR "Quality playist:\n" . $playlist . "\n";
		}

		my $baseURL = $QUALITY_URL;
		$baseURL =~ s/\?[^\?]*$//;
		$baseURL =~ s/\/[^\/]*$//;
		if ($DEBUG > 2) {
			print STDERR 'Quality playlist base URL: ' . $baseURL . "\n";
		}

		my $lastBandwidth  = 0;
		my $savedBandwidth = 0;
		foreach my $segment (split(/^/, $playlist)) {
			if ($segment =~ /^\s*$/) {
				next;
			}
			$segment =~ s/^\s+//;
			$segment =~ s/\s+$//;

			# Extract bandwidth data
			if ($segment =~ /^#/) {
				if ($segment =~ /^#EXT-X-STREAM-INF:.*\bBANDWIDTH=(\d+)\b/) {
					$lastBandwidth = $1;
				}
				next;
			}

			# Keep the best stream
			if ($DEBUG > 1) {
				print STDERR 'Considering stream URL (' . $lastBandwidth . '): ' . $segment . "\n";
			}
			if ($lastBandwidth > $savedBandwidth) {
				$savedBandwidth = $lastBandwidth;
				$STREAM_URL     = $segment;
			}
		}
	}
}
if (!defined($STREAM_URL)) {
	die("Unable to find stream URL\n");
}
if ($DEBUG) {
	print STDERR 'Keeping stream URL: ' . $STREAM_URL . "\n";
}

# Fetch and parse the stream playlist
my @stream_segments = ();
{
	my $playlist;
	if (fetch($STREAM_URL, \$playlist) == 200) {
		if ($DEBUG > 1) {
			print STDERR "Stream playlist:\n" . $playlist . "\n";
		}

		my $baseURL = $STREAM_URL;
		$baseURL =~ s/\?[^\?]*$//;
		$baseURL =~ s/\/[^\/]*$//;
		if ($DEBUG > 2) {
			print STDERR 'Playlist base URL: ' . $baseURL . "\n";
		}

		foreach my $segment (split(/^/, $playlist)) {
			if ($segment =~ /^#/ || $segment =~ /^\s*$/) {
				next;
			}
			$segment =~ s/^\s+//;
			$segment =~ s/\s+$//;
			push(@stream_segments, $baseURL . '/' . $segment);
		}
	}
}

# DEV-ONLY DEBUG
foreach my $segment (@stream_segments) {
	print STDERR $segment . "\n";
}

# Cleanup
exit(0);

# GET the requested URL, accepting encoded data and extracting the HTTP status code
sub fetch($$) {
	my ($url, $data) = @_;

	# Init the global LWP as needed
	if (!defined($LWP)) {
		$LWP = new LWP::UserAgent;
		$LWP->agent($HTTP_UA);
		$LWP->timeout($HTTP_TIMEOUT);
		$LWP->ssl_opts({ 'verify_hostname' => $HTTP_VERIFY });
	}

	# Make a request
	my $request = HTTP::Request->new('GET' => $url);
	$request->header('Accept-Encoding' => HTTP::Message::decodable);
	my $response = $LWP->request($request);

	# Do something useful with the response
	my $code = 400;
	if ($response->status_line =~ /^(\d+)\s/) {
		$code = $1;
	}
	${$data} = $response->decoded_content();
	return $code;
}
