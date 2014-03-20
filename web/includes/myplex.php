<?

function myplexToken($username, $password) {
	global $PLEX_PRODUCT;
	global $PLEX_VERSION;
	global $PLEX_ID;
	global $PLEX_AUTH_URL;

	$username = preg_replace('/\W/', '_', $username);
	$token = false;

	# Construct the headers
	$headers = array(
		'X-Plex-Product: ' . $PLEX_PRODUCT,
		#'X-Plex-Device: Foo',
		#'X-Plex-Platform: Bar',
		#'X-Plex-Platform-Version: Baz',
		'X-Plex-Version: ' . $PLEX_VERSION,
		'X-Plex-Client-Identifier: ' . $PLEX_ID,
	);

	# Configure the request
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL,            $PLEX_AUTH_URL);
	curl_setopt($ch, CURLOPT_USERPWD,        $username . ':' . $password); 
	curl_setopt($ch, CURLOPT_TIMEOUT,        4);
	curl_setopt($ch, CURLOPT_HTTPHEADER,     $headers);
	curl_setopt($ch, CURLOPT_POST,           0);
	curl_setopt($ch, CURLOPT_POSTFIELDS,     '');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

	# POST
	if ($body = curl_exec($ch)) {
		$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
		if ($code >= 200 & $code <= 299) {
			if (preg_match('/\<authentication\-token\>(\w+)\<\/authentication\-token\>/i', $body, $matches)) {
				$token = $matches[1];
			}
		}
	}

	# Cleanup cURL
	curl_close($ch);

	return $token;
}

function myplexValidTokens() {
	global $PLEX_TOKENS_URL;

	$tokens = array();
	$body = @file($PLEX_TOKENS_URL);
	foreach ($body as $line) {
		if (preg_match('/\<access_token\s+([^\>]*)\>/', $line, $matches)) {
			$attrs = $matches[1];
			if (preg_match('/\btoken\=\"(\w+)\"/', $attrs, $matches)) {
				$tokens[$matches[1]] = 1;
			}
		}
	}

	return $tokens;
}

function myplexServerToken($userToken) {
	global $PLEX_SERVERS_URL;
	global $PLEX_SERVER_NAME;

	$token = false;
	$body = @file($PLEX_SERVERS_URL . $userToken);
	foreach ($body as $line) {
		if (preg_match('/\<Server\s+([^\>]*)\>/', $line, $matches)) {
			$attrs = $matches[1];
			if (preg_match('/\bname\=\"(\w+)\"/', $attrs, $matches)) {
				if ($matches[1] == $PLEX_SERVER_NAME) {
					if (preg_match('/\baccessToken\=\"(\w+)\"/', $attrs, $matches)) {
						$token = $matches[1];
					}
				}
			}

		}
	}

	return $token;
}

function myplexAuthorize($token) {
	$tokens = myplexValidTokens();
	$serverToken = myplexServerToken($token);
	return ($tokens[$serverToken] ? true : false);
}

?>
