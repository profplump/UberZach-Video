#!/usr/bin/perl
use warnings;
use strict;

# Globals
my $DEBUG = 0;

#===============================================================
# Define a sub-class of LWP::UserAgent so we can catch redirects
#===============================================================
package ZACH_UA;
use base qw(LWP::UserAgent);

#----------------------------------------------------------------------
## @fn redirect_ok
#  @brief If a redirect to a different url is okay
#  @param request
#  @param response
#  @return 1 is successful, 0 if not
sub redirect_ok($$$) {
	my ($self, $request, $response) = @_;
	if ($DEBUG) {
		print STDERR "ZACH_UA::redirect_ok()\n";
	}

	$self->{'ZACH_redirect'} = $request->uri();
	if ($self->{'ZACH_redirect'} =~ /^file:\/\//i) {
		return 0;
	}
	return 1;
}

#----------------------------------------------------------------------
## @fn ZACH_clear_redirect
#  @brief Clears the ZACH_redirect value
#  @return void
sub ZACH_clear_redirect($) {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "ZACH_UA::clear_redirect()\n";
	}
	$self->{'ZACH_redirect'} = '';
}

#----------------------------------------------------------------------
## @fn ZACH_last_redirect
#  @brief Gets the ZACH_redirect value
#  @return ZACH_redirect
sub ZACH_last_redirect($) {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "ZACH_UA::last_redirect()\n";
	}
	return $self->{'ZACH_redirect'};
}

#===============================================================
# Main Fetch.pm pacakge
#===============================================================
package Fetch;
use URI::Escape;
use HTTP::Request;
use HTTP::Cookies;
use Scalar::Util qw(reftype);

#----------------------------------------------------------------------
## @fn new
#  @brief Constructor
#  @param class
#  @return self
sub new {

	# Grab the class name
	my ($class) = shift(@_);

	# Grab the named parameters
	my (%params) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::new()\n";
	}

	# Init self
	my $self = {};
	bless $self, $class;

	# Set the defaults
	$self->{'delay'}          = 5;
	$self->{'timeout'}        = 60;
	$self->{'redial'}         = 10;
	$self->{'cookiefile'}     = undef();
	$self->{'uas'}            = 'zachbot/2.0 <zach@kotlarek.com>';
	$self->{'content_type'}   = '';
	$self->{'post_content'}   = '';
	$self->{'headers'}        = {};
	$self->{'referer'}        = '';
	$self->{'url'}            = '';
	$self->{'file'}           = undef();
	$self->{'status_code'}    = 400;
	$self->{'content'}        = '';
	$self->{'cookies'}        = undef();
	$self->{'redirect_uri'}   = '';
	$self->{'ua'}             = undef();
	$self->{'print_comments'} = 1;

	# Saved any provided parameters
	$self->delay($params{'delay'});
	$self->timeout($params{'timeout'});
	$self->redial($params{'redial'});
	$self->cookiefile($params{'cookiefile'});
	$self->uas($params{'uas'});
	$self->headers($params{'headers'});

	# Print Comments is special
	if (defined($params{'print_comments'}) && !$params{'print_comments'}) {
		$self->{'print_comments'} = 0;
	}
	if (defined($params{'no_headers'}) && $params{'no_headers'}) {
		$self->{'print_comments'} = 0;
	}

	# Initialize an LWP object
	$self->Fetch::init_ua();

	# Redial less when debugging
	if ($DEBUG) {
		$self->redial(1);
	}

	# Return a reference to ourselves
	return $self;
}

#----------------------------------------------------------------------
## @fn init_ua
#  @brief Initialize an LWP object
#  @return void
sub init_ua() {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::init_ua()\n";
	}

	# Construct the agent
	$self->{'ua'} = ZACH_UA->new();
	if ($DEBUG) {
		eval {
			$self->{'ua'}->add_handler('request_send',  sub { shift->dump; print "\n\n"; return });
			$self->{'ua'}->add_handler('response_done', sub { shift->dump; print "\n\n"; return });
		};
	}
	$self->{'ua'}->agent($self->{'uas'});
	$self->{'ua'}->timeout($self->{'timeout'});
	push(@{ $self->{'ua'}->requests_redirectable }, 'POST');

	# Add a cookie jar, if requested
	if (defined($self->{'cookiefile'})) {
		$self->{'cookies'} = HTTP::Cookies->new(
			'file'           => $self->{'cookiefile'},
			'autosave'       => 1,
			'ignore_discard' => 1
		);
		$self->{'ua'}->cookie_jar($self->{'cookies'});
	}

	# Disable SSL hostname verification
	$self->{'ua'}->ssl_opts('verify_hostname' => 0);
}

#----------------------------------------------------------------------
## @fn delay
#  @brief Set or get the Delay
#  @param delay
#  @return delay
sub delay {
	my ($self, $delay) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::delay()\n";
	}

	if (defined($delay)) {
		$delay = int($delay);
		if ($delay >= 0) {
			$self->{'delay'} = $delay;
		}
	}
	return $self->{'delay'};
}

#----------------------------------------------------------------------
## @fn Timeout
#  @brief Set or get the Timeout
#  @return timeout
sub timeout {
	my ($self, $timeout) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::timeout()\n";
	}

	if (defined($timeout)) {
		$timeout = int($timeout);
		if ($timeout > 0) {
			$self->{'timeout'} = $timeout;
		}
	}
	return $self->{'timeout'};
}

#----------------------------------------------------------------------
## @fn redial
#  @brief Set or get the Redial
#  @param redial
#  @return redial
sub redial {
	my ($self, $redial) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::redial()\n";
	}

	if (defined($redial)) {
		$redial = int($redial);
		if ($redial > 0) {
			$self->{'redial'} = $redial;
		}
	}
	return $self->{'redial'};
}

#----------------------------------------------------------------------
## @fn cookiefile
#  @brief Set or get the Cookie File
#  @param cookiefile
#  @return cookiefile
sub cookiefile {
	my ($self, $cookiefile) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::cookiefile()\n";
	}

	if (defined($cookiefile) && (!defined($self->{'cookiefile'}) || $cookiefile ne $self->{'cookiefile'})) {
		$self->{'cookiefile'} = $cookiefile;
		$self->init_ua();
	}
	return $self->{'cookiefile'};
}

#----------------------------------------------------------------------
## @fn uas
#  @brief Set or get the User Agent String
#  @param uas
#  @return uas
sub uas {
	my ($self, $uas) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::uas()\n";
	}

	if (defined($uas) && length($uas) && $uas ne $self->{'uas'}) {
		$self->{'uas'} = $uas;
		$self->Fetch::init_ua();
	}
	return $self->{'uas'};
}

#----------------------------------------------------------------------
## @fn headers
#  @brief Set or get the Headers
#  @param data
#  @return headers
sub headers {
	my $self = shift(@_);
	my ($data) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::headers()\n";
	}

	if (defined($data)) {
		if (reftype($data) eq 'HASH') {
			%{ $self->{'headers'} } = %{$data};
		} else {
			%{ $self->{'headers'} } = %{@_};
		}
	}
	return %{ $self->{'headers'} };
}

#----------------------------------------------------------------------
## @fn url
#  @brief Set or get the URL
#  @param url
#  @return url
sub url {
	my ($self, $url) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::url()\n";
	}

	if (defined($url)) {
		$self->{'referer'} = $self->{'url'};
		$self->{'url'}     = $url;
	}
	return $self->{'url'};
}

#----------------------------------------------------------------------
## @fn file
#  @brief Set or get the file
#  @param file
#  @return file
sub file {
	my ($self, $file) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::file()\n";
	}

	if (defined($file)) {
		$self->{'file'} = $file;
	}
	return $self->{'file'};
}

#----------------------------------------------------------------------
## @fn post_content
#  @brief Set or get the POST content
#  @param data
#  @return post_content
sub post_content {
	my ($self) = shift(@_);
	my ($data) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::post_content()\n";
	}
	my $content = '';

	# Return immediately if there is no change
	if (!defined($data)) {
		return $self->{'post_content'};
	}

	# Set the content type
	$self->{'content_type'} = 'application/x-www-form-urlencoded';

	# Skip processing is the data is empty
	my $type = reftype($data);
	if (defined($type) || length($data) > 0) {

		# Convert the hash to a string
		if (defined($type) && $type eq 'HASH') {
			foreach my $key (keys(%{$data})) {
				if (defined($content) && length($content)) {
					$content .= '&';
				}

				# Ensure the value is always defined (even if empty)
				my $value = $data->{$key};
				if (!$value) {
					$value = '';
				}

				# URL encode if necessary
				if ($key =~ /[^\w\%]/) {
					$key = uri_escape($key);
				}
				if ($value =~ /[^\w\%]/) {
					$value = uri_escape($value);
				}

				# Append the string
				$content .= $key . '=' . $value;
			}
		} else {

			# No conversion needed for strings
			$content = $data;
		}
	}

	# Save and return
	$self->{'post_content'} = $content;
	if ($DEBUG) {
		print STDERR 'Fetch::post_content(' . length($content) . '): ' . $content . "\n";
	}
	return $self->{'post_content'};
}

#----------------------------------------------------------------------
## @fn post_content_multi
#  @brief Set or get the POST content multipart
#  @param data
#  @param boundary
#  @return post_content
sub post_content_multi {
	my ($self, $data, $boundary) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::post_content_multi()\n";
	}
	my $content = '';

	# Return immediately if there is no change
	if (!defined($data)) {
		return $self->{'post_content'};
	}

	# Pick a boundary if we need one
	if (!defined($boundary) || length($boundary) < 5) {
		$boundary = '';
		while (length($boundary) < 10) {
			$boundary .= chr(rand() * 127);
			$boundary =~ s/[^\w]//g;
		}
	}

	# Set the content type
	$self->{'content_type'} = 'multipart/form-data; boundary=' . $boundary;

	# Skip processing is the data is empty (or invalid)
	my $type = reftype($data);
	if (defined($type) && $type eq 'HASH') {

		# Convert the hash to a string
		foreach my $key (keys(%{$data})) {
			my $name = $key;
			if (ref($data->{$key}) ne 'ARRAY') {
				my @tmp = ($data->{$key});
				$data->{$key} = \@tmp;
			}
			foreach my $val (@{ $data->{$key} }) {
				$content .= '--' . $boundary . "\r\n";
				$content .= 'Content-Disposition: form-data; name="' . $name . "\"\r\n\r\n";
				$content .= $val . "\r\n";
			}
		}

		# End the multipart form
		$content .= '--' . $boundary . '--';
	}

	# Save and return
	$self->{'post_content'} = $content;
	if ($DEBUG) {
		print STDERR 'Fetch::post_content_multi(' . length($content) . "):\n" . $content . "\n";
	}
	return $self->{'post_content'};
}

#----------------------------------------------------------------------
## @fn status_code
#  @brief Get the Status Code
#  @return status_code
sub status_code() {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::status_code()\n";
	}

	return $self->{'status_code'};
}

#----------------------------------------------------------------------
## @fn last_redirect
#  @brief Get the redirect URI
#  @return redirect_uri
sub last_redirect() {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::redirect_uri()\n";
	}

	return $self->{'redirect_uri'};
}

#----------------------------------------------------------------------
## @fn fetch
#  @brief Performs a Fetch
#  @return status code
sub fetch() {
	my ($self)   = shift(@_);
	my (%params) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::fetch()\n";
	}
	my ($request, $response, $host);

	# Save the URL and filename, if any
	$self->Fetch::url($params{'url'});
	$self->Fetch::file($params{'file'});

	# Decide if we care about the result code
	my $nocheck = 0;
	if ($params{'nocheck'}) {
		$nocheck = 1;
	}

	# Check the URL
	if (!length($self->Fetch::url())) {
		$self->{'status_code'} = 400;
		return $self->Fetch::status_code();
	}

	# Create a GET or POST request
	if (length($self->Fetch::post_content())) {
		$request = HTTP::Request->new('POST' => $self->Fetch::url());
		$request->header('Content-Type'   => $self->{'content_type'});
		$request->header('Content-Length' => length($self->Fetch::post_content()));
		$request->content($self->Fetch::post_content());
		if ($DEBUG) {
			print STDERR 'Fetching via POST: ' . $self->Fetch::url() . "\n";
		}
	} else {
		$request = HTTP::Request->new('GET' => $self->Fetch::url());
		if ($DEBUG) {
			print STDERR 'Fetching via GET: ' . $self->Fetch::url() . "\n";
		}
	}

	# Always add the 'Host' header
	# But allow headers() to override the value
	if (!defined($self->{'headers'}{'Host'}) || length($self->{'headers'}{'Host'}) < 1) {
		my ($host) = $self->Fetch::url() =~ /\w+:\/\/([^\/]+)/;
		$request->header('Host' => $host);
		if ($DEBUG) {
			print STDERR 'Setting host header: ' . $host . "\n";
		}
	}

	# Always add the 'Referer' header
	# But allow headers() to override the value
	if (!defined($self->{'headers'}{'Referer'}) || length($self->{'headers'}{'Referer'}) < 1) {
		$request->header('Referer' => $self->{'referer'});
		if ($DEBUG) {
			print STDERR 'Setting referer header: ' . $self->{'referer'} . "\n";
		}
	}

	# Always add the 'Accept-Encoding' header
	# But allow headers() to override the value
	if (!defined($self->{'headers'}{'Accept-Encoding'}) || length($self->{'headers'}{'Accept-Encoding'}) < 1) {
		$request->header('Accept-Encoding' => HTTP::Message::decodable);
		if ($DEBUG) {
			print STDERR 'Setting Accept-Encoding header: ' . HTTP::Message::decodable . "\n";
		}
	}

	# Append any extra headers
	foreach my $key (keys(%{ $self->{'headers'} })) {
		$request->header($key => $self->{'headers'}{$key});
		if ($DEBUG) {
			print STDERR 'Setting header: ' . $key . ' => ' . $self->{'headers'}{$key} . "\n";
		}
	}

	# Dial until we get results
	my $connectcount = $self->Fetch::redial();
	GET: {

		# Limit redials
		if (!$connectcount) {
			last GET;
		}
		$connectcount--;

		# Run the request
		$self->{'ua'}->ZACH_clear_redirect();
		$response = $self->{'ua'}->request($request);
		$self->{'redirect_uri'} = $self->{'ua'}->ZACH_last_redirect();
		if (defined($self->{'cookies'})) {
			$self->{'cookies'}->extract_cookies($response);
		}

		# Check for errors, loop if we aren't happy
		if ($nocheck) {
			last GET;
		} elsif ($response->status_line =~ /^200/) {
			last GET;
		} else {
			sleep($self->Fetch::delay() * (rand(2) + 0.5));
			redo GET;
		}
	}

	# Grab the status code
	($self->{'status_code'}) = $response->status_line =~ /^(\d+)\s/;

	# Grab the content for future use
	$self->{'content'} = $response->decoded_content();

	# Save the output (save() does its own validity checks)
	$self->Fetch::save('nocheck' => $nocheck);

	# Write any new cookies to disk
	if (defined($self->{'cookies'}) && ref($self->{'cookies'})) {
		$self->{'cookies'}->save();
	}

	# Return the status code
	return $self->Fetch::status_code();
}

#----------------------------------------------------------------------
## @fn content
#  @brief Get the Content
#  @return data
sub content() {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::content()\n";
	}

	# Extract content (if any)
	my $data = $self->{'content'};
	if (!$data) {
		return undef();
	}

	# Standardize line endings
	$data =~ s/\r\n/\n/;

	# Return an array when requested
	if (wantarray) {
		return split(/\n/, $data);
	}

	# Otherwise return a string
	return $data;
}

#----------------------------------------------------------------------
## @fn save
#  @brief Save
#  @param params
#  @return 1 if successful, 0 if not
sub save() {
	my ($self) = shift(@_);
	if ($DEBUG) {
		print STDERR "Fetch::save()\n";
	}
	my (%params) = @_;

	# Optionally update the file name
	$self->Fetch::file($params{'file'});

	# Bail on bad HTTP result codes (if we're checking)
	if (!$params{'nocheck'}) {
		if ($self->Fetch::status_code() != 200) {
			print STDERR "Fetch::save: Refusing to save file with bad status code\n";
			return 1;
		}
	}

	# Bail on bad file names -- but don't die, because we don't always want to save
	if (!defined($self->Fetch::file()) || !length($self->Fetch::file())) {
		return 1;
	}

	# Bail on I/O errors
	if (!open(OUT, '>', $self->Fetch::file())) {
		die('Fetch::save: Unable to open output file: ' . $self->Fetch::file() . ': ' . $! . "\n");
	}

	# Print out the URL, the post content (if any)
	if (defined($self->{'print_comments'}) && $self->{'print_comments'}) {
		print OUT '<!-- ' . $self->Fetch::url() . ' -->' . "\n";
		if (length($self->Fetch::post_content())) {
			print OUT '<!-- ' . $self->Fetch::post_content() . ' -->' . "\n";
		}
		print OUT "\n\n";
	}

	# Print the document body
	print OUT $self->Fetch::content() . "\n";
	close(OUT);

	# Return 0 on success
	return 0;
}

#----------------------------------------------------------------------
## @fn DESTROY
#  @brief Deconstructor
sub DESTROY() {
	my ($self) = @_;
	if ($DEBUG) {
		print STDERR "Fetch::DESTROY()\n";
	}

	$self->{'cookies'} = undef();
	$self->{'ua'}      = undef();
}

# Packages must return true
return 1;
