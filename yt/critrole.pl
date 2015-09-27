#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use File::Basename;

# Parameters
my $TOP_URL  = 'http://geekandsundry.com/shows/critical-role/';
my $PG_MATCH = qr/\<link rel=\'next\' href=\'([^\']+\/page\/\d+\/)\'/;
my $EP_MATCH = qr/^https?\:\/\/[^\/]+\/critical\-role\-episode/i;
my $INI_PATH = `~/bin/video/mediaPath` . '/YouTube/Critical Role (None)/extra_videos.ini';
my $UA_STR   = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.75.14 (KHTML, like Gecko) Version/7.0.3 Safari/7046A194A';
my $TIMEOUT  = 10;

# Debug
our $DEBUG = 0;
if (defined($ENV{'DEBUG'}) && $ENV{'DEBUG'} =~ /(\d+)/) {
	$DEBUG = $1;
}

# Setup LWP
my $ua = LWP::UserAgent->new();
if (!$ua) {
	die('Unable to init UA: ' . $! . "\n");
}
$ua->agent($UA_STR);
$ua->timeout($TIMEOUT);
$ua->env_proxy();

# Read the existing INI file
my %old_ytids = ();
{
	my $fh = undef();
	open($fh, '<', $INI_PATH)
	  or die('Unable to read ini file: ' . $INI_PATH . ': ' . $! . "\n");
	my $url = undef();
	while (<$fh>) {
		if (/^\s*#\s*(https?\:\/\/[^\s]+)/i) {
			$url = $1;
		} elsif (/([\w\-]+)/) {
			if (!$url) {
				$url = 'Unknown';
			}
			$old_ytids{$1} = $url;
			$url = undef();
			if ($DEBUG > 1) {
				print STDERR 'Found existing YTID: ' . $1 . ' # ' . $old_ytids{$1} . "\n";
			}
		}
	}
	close($fh);
}

# Use the top-level page to find episode-specific pages
my @episodes = ();
{
	my $url = $TOP_URL;
	NEXT_PAGE: {
		if ($DEBUG) {
			print STDERR 'Loading top page: ' . $url . "\n";
		}
		my $response = $ua->get($url);
		if (!$response->is_success()) {
			die(basename($0) . ": Unable to fetch top-level page\n");
		}
		foreach my $link (split(/\<a\s+/, $response->decoded_content())) {
			if ($link =~ /\s+href=\"([^\"]+)\"/) {
				my $href = $1;
				if ($href =~ $EP_MATCH) {
					push(@episodes, $href);
				}
			}
		}
		if ($response->decoded_content() =~ $PG_MATCH) {
			$url = $1;
			redo NEXT_PAGE;
		}
	}
}
if ($DEBUG) {
	print STDERR 'Episode URLs (' . scalar(@episodes) . "):\n\t" . join("\n\t", @episodes) . "\n";
}

# Find each episode's YTID
my %ytids = ();
{
	foreach my $url (@episodes) {
		my $response = $ua->get($url);
		if (!$response->is_success()) {
			die(basename($0) . ': Unable to fetch episode page: ' . $url . "\n");
		}
		if ($response->decoded_content() =~ /data-ytid=\"([^\"]+)\"/) {
			$ytids{$1} = $url;
		} else {
			print STDERR 'No YTID found on: ' .$url . "\n";
			if ($DEBUG > 1) {
				print STDERR "\tPage content:\n" . $response->decoded_content() . "\n\n";
			}
		}
	}
}
if ($DEBUG) {
	print STDERR 'YouTube IDs (' . scalar(keys(%ytids)) . "):\n\t" . join("\n\t", keys(%ytids)) . "\n";
}

# Drop known episodes
{
	foreach my $id (keys(%ytids)) {
		if (exists($old_ytids{$id})) {
			if ($DEBUG > 1) {
				print 'Ignoring known episode: ' . $id . ' # ' . $old_ytids{$id} . "\n";
			}
			delete($ytids{$id});
		}
	}
}

# Update the INI file
{
	my $fh = undef();
	open($fh, '>>', $INI_PATH)
	  or die('Unable to write ini file: ' . $INI_PATH . ': ' . $! . "\n");
	foreach my $id (keys(%ytids)) {
		if ($DEBUG) {
			print 'Adding episode: ' . $id . ' # ' . $ytids{$id} . "\n";
		}
		print $fh "\n# " . $ytids{$id} . "\n" . $id . "\n";
	}
	close($fh);
}

# Cleanup
exit(0);
