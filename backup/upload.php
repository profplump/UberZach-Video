#!/usr/local/bin/php
<?php

# Debug
$DEBUG = false;
if ($_ENV['DEBUG']) {
	$DEBUG = true;
}

# Includes
require_once 'opendrive.php';

# Command-line parameters
global $argc;
global $argv;
$BYTES = 1 * 1024 * 1024 * 1024;
if (($argc > 1) && (strlen($argv[1]) > 0)) {
	$BYTES = intval($argv[1]) * 1024 * 1024;
}

# Run serially
$PID_FILE = sys_get_temp_dir() . '/upload.pid';
if (file_exists($PID_FILE)) {
	$OLD_PID = trim(@file_get_contents($PID_FILE));
	if ($OLD_PID && posix_kill($OLD_PID, 0)) {

		# Already running
		if ($DEBUG) {
			echo 'Already running: ' . $OLD_PID . "\n";
		}
		exit(0);
	}
}
file_put_contents($PID_FILE, posix_getpid());
unset($PID_FILE);

# Open the DB connection
$dbh = dbOpen();

# Open the OpenDrive session
$session = login();
if (!$session) {
	die("Unable to connect to OpenDrive\n");
}

# Prepare statements
$folders = $dbh->prepare('SELECT base, path FROM files WHERE ' .
	"type = 'folder' AND " .
	'(remote_mtime IS NULL OR remote_mtime < mtime) ' .
	'ORDER BY base, path');
$files = $dbh->prepare('SELECT base, path FROM files WHERE ' .
	"(type != 'ignored' AND type != 'folder') AND " .
	'(remote_mtime IS NULL OR remote_mtime < mtime) ' .
	'ORDER BY base, path'
);
$update = $dbh->prepare('UPDATE files SET remote_mtime = now() WHERE base = :base AND path = :path');

# Create all the folders
if ($DEBUG) {
	echo "Creating folders\n";
}
$folders->execute();
while ($row = $folders->fetch()) {

	# Ensure the local reference is valid
	$file = $row['base'] . '/' . $row['path'];
	if (!is_dir($file)) {
		echo 'Invalid directory: ' . $file . "\n";
		continue;
	}

	# Create the folder
	if ($DEBUG) {
		echo 'Creating folder: ' . $row['path'] . "\n";
	}
	if (folderID($session, $row['path']) || mkFolder($session, $row['path'])) {
		$update->execute(array(':base' => $row['base'], ':path' => $row['path']));
	}
}

# Loop through all the files
if ($DEBUG) {
	echo 'Uploading files with byte limit: ' . $BYTES . "\n";
}
$uploaded = 0;
$files->execute();
while ($row = $files->fetch()) {

	# Ensure the local reference is valid
	$file = $row['base'] . '/' . $row['path'];
	if (!is_readable($file)) {
		echo 'Invalid file: ' . $file . "\n";
		continue;
	}
	$stat = stat($file);

	# Upload the file
	if ($DEBUG) {
		echo 'Uploading file (' . $stat['size'] . ' bytes): ' . $row['path'] . "\n";
	}
	$result = fileUpload($session, $row['path'], $file);
	if ($result !== false && $result == $stat['size']) {
		$uploaded += $result;
		$update->execute(array(':base' => $row['base'], ':path' => $row['path']));
	}

	# Bail if we exceed the byte limit
	if ($DEBUG) {
		echo 'Uploaded ' . $uploaded . ' of ' . $BYTES . " bytes\n";
	}
	if ($BYTES && $uploaded >= $BYTES) {
		if ($DEBUG) {
			echo "Exiting due to byte limit\n";
		}
		break;
	}
}

# Logout from OpenDrive
logout($session);

?>
