package PrettyPrint;
use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION   = 1.00;
@ISA       = qw(Exporter);
@EXPORT    = qw(&prettyPrint);
@EXPORT_OK = qw(prettyPrint printArray printHash);

sub prettyPrint($$);
sub printArray($$);
sub printHash($$);

sub prettyPrint($$) {
	my ($data, $prefix) = @_;
	if (!defined($data)) {
		warn('No data provided');
		return undef();
	}

	my $str = undef();
	if (ref($data) eq 'HASH') {
		$str = printHash($data, $prefix);
	} elsif (ref($data) eq 'ARRAY') {
		$str = printArray($data, $prefix);
	} elsif (ref($data) eq '') {
		$str = $data;
	} else {
		warn('Unknown data type: ' . ref($data));
	}

	return $str;
}

sub printArray($$) {
	my ($array, $prefix) = @_;
	my $str = "\n";

	foreach my $item (@{$array}) {
		if (ref($item) eq 'HASH') {
			$str .= printHash($item, $prefix . substr($prefix, 0, 1));
		} elsif (ref($item) eq 'ARRAY') {
			$str .= printArray($item, $prefix . substr($prefix, 0, 1));
		} else {
			$str .= $item . "\n";
		}
	}

	return $str;
}

sub printHash($$) {
	my ($hash, $prefix) = @_;
	my $str = '';

	foreach my $key (keys %{$hash}) {
		$str .= $prefix . $key . ' => ';
		if (ref($hash->{$key}) eq 'HASH') {
			$str .= "\n" . printHash($hash->{$key}, $prefix . substr($prefix, 0, 1));
		} elsif (ref($hash->{$key}) eq 'ARRAY') {
			$str .= printArray($hash->{$key}, $prefix . substr($prefix, 0, 1));
		} else {
			$str .= $hash->{$key} . "\n";
		}
	}

	return $str;
}

# Modules must return true
return 1;
