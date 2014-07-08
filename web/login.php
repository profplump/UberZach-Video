<?

# Include the TV functions
require_once 'includes/main.php';

# Send our headers early
header('Content-type: text/html; charset=utf-8');

# Process logout
if (isset($_REQUEST['logout'])) {
	logout();
}

# Redirect if we're already authenticated
if (authenticated()) {
	login_redirect();
}

# Process login
if (isset($_POST['username']) && isset($_POST['password'])) {
	login($_POST['username'], $_POST['password']);
}

#=========================================================================================

printHeader('UberZach TV - Login');

# Preserve the redirect
$url = $_SERVER['PHP_SELF'];
if (isset($_GET['dest'])) {
	$url .= '?dest=' . urlencode($_GET['dest']);
}

# Save our AUTH_ERR as a user notice, if it exists
$notice = '';
if ($AUTH_ERR) {
	$notice = $AUTH_ERR;
}

# Header
print <<<ENDOLA
<div style="width: 50%; margin-left: auto; margin-right: auto;">
<form action="${url}" method="post" data-ajax="false">
ENDOLA;

# Print the user notice, if any, above the login fields
if ($notice) {
	print <<<ENDOLA
<p style="color: red;">
$notice
</p>
ENDOLA;
}

# Login fields
print <<<ENDOLA
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
