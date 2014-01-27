<?

# Always start a session
session_start();

function login($username, $password) {
	require 'config.php';
	$username = preg_replace('/\W/', '_', $username);

	# Set the PAM service name
	ini_set('pam.servicename', $PAM_SERVICE);

	if (pam_auth($username, $password)) {
		$_SESSION['USER'] = $username;
		session_regenerate_id(true);
	} else {
		logout();
	}

	# Redirect, if we have a target
	if (isset($_GET['dest'])) {
		header('Location: ' . $_GET['dest']);
	}
}

function logout() {
	require 'config.php';
	unset($_SESSION['USER']);
	session_regenerate_id(true);
	header('Location: ./');
	exit();
}

function username() {
	return $_SESSION['USER'];
}

function authenticated() {
	return isset($_SESSION['USER']);
}

function require_authentication() {
	require 'config.php';
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

?>
