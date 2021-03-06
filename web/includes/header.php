<?

# Generic XHTML 1.1 header
function printHeader($title) {
	print <<<ENDOLA
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" 
   "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
	<title>${title}</title>
ENDOLA;

	printJQuery();

	echo '</head><body>';
}

# Generic XHTML 1.1 footer
function printFooter() {
	print <<<ENDOLA
</body>
</html>
ENDOLA;
}

function printJQuery() {
	# Determine our protocol
	$protocol = protocolName();

	# Print
	echo <<<ENDOLA
<!-- Default JQuery -->
<script type="text/javascript" src="${protocol}://code.jquery.com/jquery-1.11.2.min.js"></script>

<!-- Provide # support in JQuery-mobile autodividers -->
<!-- Must be loaded before JQuery-mobile  -->
<script type="text/javascript">
$( document ).on( "mobileinit", function() {
	$.mobile.listview.prototype.options.autodividersSelector = function( elt ) {
		var text = $.trim( elt.text() ) || null;
		if ( !text ) {
			return null;
		}
		var short = text.slice( 0, 1 ).toUpperCase();
		if ( short == '@' || !isNaN(parseFloat(text)) ) {
			return '#';
		} else {
			return short;
		}
	};
});
</script>

<!-- Default JQuery-mobile -->
<link rel="stylesheet" href="${protocol}://code.jquery.com/mobile/1.4.5/jquery.mobile-1.4.5.min.css" />
<script type="text/javascript" src="${protocol}://code.jquery.com/mobile/1.4.5/jquery.mobile-1.4.5.min.js"></script>
ENDOLA;
}

?>
