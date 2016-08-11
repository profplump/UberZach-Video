<?

$AUTH_ERR = '';

# Always start a session, unless we're on the CLI
if (php_sapi_name() != 'cli') {
	session_set_cookie_params(30 * 86400, '/tv', $_SERVER['HTTP_HOST'], true, true);
	session_start();
}

function login($username, $password) {
	global $AUTH_ERR;
	$authenticated = false;
	$authorized    = false;

	# Auth against MyPlex
	$token = myplexToken($username, $password);
	if ($token !== false) {
		$authenticated = true;
	} else {
		$AUTH_ERR = 'Invalid Credentials';
	}

	# Authorize against MyPlex
	if ($authenticated) {
		$authorized = myplexAuthorize($token);
		if (!$authorized) {
			$AUTH_ERR = 'Invalid Credentials';
			#$AUTH_ERR = 'Not Authorized';
		}
	}

	# Login on dual success
	if ($authenticated && $authorized) {
		$_SESSION['USER'] = $username;
		session_regenerate_id(true);
	} else {
		logout(false);
	}

	# Redirect, using the provided target if available
	if (authenticated()) {
		login_redirect();
	}
}

function login_redirect() {
	global $MAIN_PAGE;
	$url = $MAIN_PAGE;
	if (isset($_GET['dest'])) {
		$url = $_GET['dest'];
	}
	header('Location: ' . $url);
}

function logout($redirect = true) {
	unset($_SESSION['USER']);
	session_regenerate_id(true);
	if ($redirect) {
		global $MAIN_PAGE;
		header('Location: ' . $MAIN_PAGE);
		exit();
	}
}

function username() {
	return $_SESSION['USER'];
}

function authenticated() {
	return isset($_SESSION['USER']);
}

function require_authentication() {
	global $LOGIN_PAGE;
	if (!authenticated()) {

		# Provide the current URL for post-auth redirect, if possible
		$dest = '';
		if (!preg_match('/' . preg_quote($LOGIN_PAGE) . '/', $_SERVER['PHP_SELF'])) {
			$dest = $_SERVER['PHP_SELF'];
			if ($_GET['series']) {
				$dest .= '?series=' . $_GET['series'];
			}
		}

		$url = $LOGIN_PAGE;
		if (strlen($dest)) {
			$url .= '?dest=' . urlencode($dest);
		}

		header('Location: ' . $url);
		exit();
	}
}

function die_if_not_authenticated() {
	if (!authenticated) {
		die('Failure: Auth');
	}
}

?>
