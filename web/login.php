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

# Generic XHTML 1.1 header
print <<<ENDOLA
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" 
   "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
	<title>UberZach TV - Login</title>

	<!-- Default JQuery -->
	<script src="http://code.jquery.com/jquery-1.9.1.min.js"></script>

	<!-- Provide # support in JQuery-mobile autodividers -->
	<!-- Must be loaded before JQuery-mobile  -->
	<script>
	$( document ).on( "mobileinit", function() {
		$.mobile.listview.prototype.options.autodividersSelector = function( elt ) {
			var text = $.trim( elt.text() ) || null;
			if ( !text ) {
				return null;
			}
			if ( !isNaN(parseFloat(text)) ) {
				return "#";
			} else {
				text = text.slice( 0, 1 ).toUpperCase();
				return text;
			}
		};
	});
	</script>

	<!-- Default JQuery-mobile -->
	<link rel="stylesheet" href="http://code.jquery.com/mobile/1.3.2/jquery.mobile-1.3.2.min.css" />
	<script src="http://code.jquery.com/mobile/1.3.2/jquery.mobile-1.3.2.min.js"></script>

	<!-- Custom code for the linkbar -->
	<script src="autodividers-linkbar.js"></script>
	<link rel="stylesheet" href="autodividers-linkbar.css">
</head>
<body>

ENDOLA;

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

# Generic XHTML 1.1 footer
print <<<ENDOLA
</body>
</html>
ENDOLA;
?>
