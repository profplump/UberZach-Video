<?

# Include the TV functions
require_once 'includes/main.php';

# Send our headers early
header('Content-type: text/html; charset=utf-8');

# Process logout
if (isset($_REQUEST['logout'])) {
	logout();
}

# Process login
if (isset($_POST['username']) && isset($_POST['password'])) {
	login($_POST['username'], $_POST['password']);
}

# Redirect if we're already authenticated
if (authenticated()) {
	login_redirect();
}

#=========================================================================================

printHeader('UberZach TV - Login');

$url = $_SERVER['PHP_SELF'];
if (isset($_GET['dest'])) {
	$url .= '?dest=' . urlencode($_GET['dest']);
}

print <<<ENDOLA
<div style="width: 50%; margin-left: auto; margin-right: auto;">
<form action="${url}" method="post" data-ajax="false">
<p>
<label>Username: <input type="text" name="username" /></label><br/>
<label>Password: <input type="password" name="password" /></label><br/>
</p>
<p><input type="submit" name="login" value="Login" /></p>
</form>
</div>
ENDOLA;

printFooter();

?>
