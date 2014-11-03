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
$SUB_DIR = '';
if (($argc > 1) && (strlen($argv[1]) > 0)) {
	$SUB_DIR = trim($argv[1]);
}

# Wait DELAY_DAYS before considering a file
$DELAY_DAYS = 30;
if (isset($_ENV['DELAY_DAYS'])) {
	$DELAY_DAYS = $_ENV['DELAY_DAYS'];
}

# Delete only if specified
$DELETE = false;
if ($_ENV['DELETE']) {
	$DELETE = true;
}

# Build our local base path
$VIDEO_DIR=$_ENV['HOME'] . '/bin/video';
if (isset($_ENV['VIDEO_DIR'])) {
	$VIDEO_DIR = $_ENV['VIDEO_DIR'];
}
$BASE_LOCAL='';
if (isset($_ENV['BASE_LOCAL'])) {
	$BASE_LOCAL = $_ENV['BASE_LOCAL'];
} else {
	$BASE_LOCAL = trim(shell_exec($VIDEO_DIR . '/mediaPath'));
}

# Allow usage with absolute local paths
if (substr($SUB_DIR, 0, 1) == '/') {
	$SUB_DIR = preg_replace('/^' . preg_quote($BASE_LOCAL, '/') . '\//', '', $SUB_DIR);
}

# Usage checks
if (strlen($SUB_DIR) < 1 || $DELAY_DAYS < 1) {
	die('Usage: ' . $argv[0] . " sub_directory\n");
}

# Sanity checks
$LOCAL = $BASE_LOCAL . '/' . $SUB_DIR;
if (!file_exists($LOCAL) || !is_dir($LOCAL)) {
	die('Invalid local directory: ' . $LOCAL . "\n");
}

# Open the DB connection
$dbh = dbOpen();

# Look for files in the DB that no longer exist or have changed types
$delete = $dbh->prepare('DELETE FROM files WHERE base = :base AND path = :path');
$missing = $dbh->prepare('SELECT base, path, type FROM files');
$missing->execute();
while ($row = $missing->fetch()) {
	$trigger = false;
	$file = $row['base'] . '/' . $row['path'];

	if ($row['type'] == 'folder') {
		# Ensure the path exists and is a folder
		if (!is_dir($file)) {
			echo 'Missing/changed folder: ' . $file . "\n";
			$trigger = true;
		}
	} else if ($row['type'] == 'ignored') {
		# Silently delete missing ignored files of any type
		if (!file_exists($file)) {
			if ($DEBUG) {
				echo 'Missing ignored file: ' . $file . "\n";
			}
			$trigger = true;
		}
	} else {
		# Ensure the path exists and is a regular file
		if (!is_file($file)) {
			echo 'Missing file: ' . $file . "\n";
			$trigger = true;
		}
	}

	# Delete if global DELETE is enabled
	if ($DELETE && $trigger) {
		$delete->execute(array(':base' => $row['base'], ':path' => $row['path']));
	}

	unset($trigger);
	unset($file);
}
unset($delete);

# Grab the file list -- limit files by mtime, but include all directories
$FIND=tempnam(sys_get_temp_dir(), 'scanLocal-find');
exec('cd ' . escapeshellarg($BASE_LOCAL) . ' && find ' . escapeshellarg($SUB_DIR) .
	' -type f -mtime +' . escapeshellarg($DELAY_DAYS) . ' > ' . escapeshellarg($FIND));
exec('cd ' . escapeshellarg($BASE_LOCAL) . ' && find ' . escapeshellarg($SUB_DIR) .
	' -type d >> ' . escapeshellarg($FIND));

# Sort and injest
exec('cat ' . escapeshellarg($FIND) . ' | sort ', $FILES);
unlink($FIND);
unset($FIND);

# Loop through all the files we found
$select = $dbh->prepare('SELECT base, path, type, mtime, hash, hash_time FROM files WHERE base = :base AND path = :path');
$insert = $dbh->prepare('INSERT INTO files (base, path, type, mtime) VALUES (:base, :path, :type, now())');
$check_mtime = $dbh->prepare('SELECT EXTRACT(EPOCH FROM mtime) AS mtime FROM files WHERE base = :base AND path = :path');
$set_mtime = $dbh->prepare('UPDATE files SET mtime = now() WHERE base = :base AND path = :path');
$hash_time_check = $dbh->prepare('SELECT hash, EXTRACT(EPOCH FROM hash_time) AS hash_time FROM files WHERE base = :base AND path = :path AND (hash_time IS NULL OR EXTRACT(EPOCH FROM hash_time) < :mtime)');
$set_hash = $dbh->prepare('UPDATE files SET hash = :hash, hash_time = now() WHERE base = :base AND path = :path');
foreach ($FILES as $file) {

	# Construct the absolute path
	$path = $BASE_LOCAL . '/' . $file;

	# Is the path in the DB
	$select->execute(array(':base' => $BASE_LOCAL, ':path' => $file));
	$result = $select->fetch();
	if (!$result) {
		$parts = pathinfo($path);
		$EXT = strtolower($parts['extension']);
		$NAME = strtolower($parts['filename']);
		unset($parts);

		$TYPE = 'other';
		if (preg_match('/\/\.git(\/.*)?$/', $path)) {
			$TYPE = 'ignored';
		} else if (preg_match('/\/\._/', $path)) {
			$TYPE = 'ignored';
		} else if ($EXT == 'lastfindrecode' || $NAME == 'placeholder' || $EXT == 'plexignore') {
			$TYPE = 'ignored';
		} else if ($EXT == 'tmp' || $EXT == 'gitignore' || $EXT == 'ds_store' || 
			preg_match('/^\.smbdelete/', $NAME)) {
				$TYPE = 'ignored';
		} else if (is_dir($path)) {
			$TYPE = 'folder';
		} else if ($EXT == 'm4v' || $EXT == 'mkv' || $EXT == 'mp4' || $EXT == 'mov' ||
			$EXT == 'vob' || $EXT == 'iso' || $EXT == 'avi') {
				$TYPE = 'video';
		} else if ($EXT == 'mp3' || $EXT == 'aac' || $EXT == 'm4a' || $EXT == 'm4b' ||
			$EXT == 'm4p' || $EXT == 'wav') {
				$TYPE = 'audio';
		} else if ($EXT == 'epub' || $EXT == 'pdf') {
			$TYPE = 'book';
		} else if ($EXT == 'jpg' || $EXT == 'png') {
			$TYPE = 'image';
		} else if ($EXT == 'gz' || $EXT == 'zip' || $EXT == 'xz') {
			$TYPE = 'archive';
		} else if ($EXT == 'itc' || $EXT == 'itl' || $EXT == 'strings' || $EXT == 'itdb' ||
			$EXT == 'plist' || $EXT == 'ipa' || $EXT == 'ini') {
				$TYPE = 'database';
		} else if ($EXT == 'clip' || $EXT == 'riff' || $EXT == 'nfo') {
			$TYPE = 'metadata';
		} else if ($EXT == 'webloc' || $NAME == 'skip' || $NAME == 'season_done' || 
			$NAME == 'more_number_formats' || $NAME == 'no_quality_checks' ||
			$NAME == 'filler' || $NAME == 'search_name' || $EXT == 'disabled' ||
			$NAME == 'must_match' || $EXT == 'fakeshow' || $EXT == 'filler' ||
			$NAME == 'excludes' || $NAME == 'search_by_date' || $EXT == 'twopart') { 
				$TYPE = 'metadata';
		} else if ($EXT == 'fake' || $EXT == 'txt' || $EXT == 'json' ||
			$EXT == 'bup' || $EXT == 'ifo') {
				$TYPE = 'metadata';
		}
		if ($TYPE == 'other') {
			die('Unknown file type: ' . $path . ': ' . $NAME . '^' . $EXT . "\n");
		}
		if ($DEBUG) {
			echo 'Adding: ' . $path . ': ' . $TYPE . "\n";
		}
		$insert->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':type' => $TYPE));
		if ($insert->rowCount() != 1) {
			print_r($insert->errorInfo());
			die('Unable to insert: ' . $path . "\n");
		}
	} else {
		$TYPE = $result['type'];
	}

	# Skip 'ingnored' files
	if ($TYPE == 'ignored') {
		continue;
	}

	# Update the mtime as needed
	$mtime = trim(shell_exec('stat -c "%Y" ' . escapeshellarg($path)));
	$check_mtime->execute(array(':base' => $BASE_LOCAL, ':path' => $file));
	$result = $check_mtime->fetch(PDO::FETCH_ASSOC);
	if (!$result && !$result['mtime'] || !$mtime) {
		die('Unable to find mtime for: ' . $path . "\n");
	} else if ($result['mtime'] < $mtime) {
		$set_mtime->execute(array(':base' => $BASE_LOCAL, ':path' => $file));
	}

	# Update hashes as needed
	if ($TYPE != 'folder') {
		$hash_time_check->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':mtime' => $mtime));
		$result = $hash_time_check->fetch(PDO::FETCH_ASSOC);
		if ($result) {
			if ($DEBUG) {
				echo 'Adding hash: ' . $path . "\n";
			}
			$hash = trim(shell_exec('md5sum ' . escapeshellarg($path) . ' | cut -d " " -f 1'));
			if (strlen($hash) == 32) {
				$set_hash->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':hash' => $hash));
			} else {
				die('Invalid hash (' . $hash . ') for file: ' . $path . "\n");
			}
			unset($hash);
		} else {
			if ($DEBUG) {
				echo 'Hash is up-to-date: ' . $path . "\n";
			}
		}
	} else {
		if ($DEBUG) {
			echo 'No hash for folder: ' . $path . "\n";
		}
	}

	unset($mtime);
	unset($NAME);
	unset($EXT);
	unset($path);
}
unset($FILES);
unset($select);
unset($insert);
unset($check_mtime);
unset($set_mtime);
unset($hash_time_check);
unset($set_hash);

# Update priorities
$priority = $dbh->prepare('UPDATE files SET priority = :priority WHERE path LIKE :path');
$priority->execute(array(':priority' => 100,	':path' => 'Movies/%'));
$priority->execute(array(':priority' => 50,	':path' => 'iTunes/%'));
$priority->execute(array(':priority' => -50,	':path' => 'Backups/%'));
$priority->execute(array(':priority' => -100,	':path' => 'TV/%'));
unset($priority);

# Cleanup
unset($dbh);

?>
