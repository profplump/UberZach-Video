#!/usr/local/bin/php
<?php

# Command-line parameters
global $argc;
global $argv;
$SUB_DIR = '';
if (($argc > 1) && (strlen($argv[1]) > 0)) {
	$SUB_DIR = trim($argv[1]);
}
$DELAY_DAYS=30;
if (isset($_ENV['DELAY_DAYS'])) {
	$DELAY_DAYS = $_ENV['DELAY_DAYS'];
}
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
try {
	$dbh = new PDO('pgsql:dbname=backup', $_ENV{'USER'});
} catch (PDOException $e) {
	die('DB error: ' . $e->getMessage() . "\n");
}

# Grab the file list -- limit files by mtime, but include all directories
$FIND=tempnam(sys_get_temp_dir(), 'scanLocal-find');
exec('cd ' . escapeshellarg($BASE_LOCAL) . ' && find ' . escapeshellarg($SUB_DIR) . ' -type f -mtime +' . escapeshellarg($DELAY_DAYS) . ' > ' . escapeshellarg($FIND));
exec('cd ' . escapeshellarg($BASE_LOCAL) . ' && find ' . escapeshellarg($SUB_DIR) . ' -type d >> ' . escapeshellarg($FIND));

# Sort
$SORT=tempnam(sys_get_temp_dir(), 'scanLocal-sort');
exec('cat ' . escapeshellarg($FIND) . ' | sort > ' . escapeshellarg($SORT));
unlink($FIND);
unset($FIND);

# Filter junk
exec('grep -v "\/\._" ' . escapeshellarg($SORT) .
	' | grep -v "\/\.DS_Store\$" | grep -v "\/\.git\/"',
	$FILES);
unlink($SORT);
unset($SORT);

# Prepare statements
$select = $dbh->prepare('SELECT base, path, type, mtime, hash, hash_time FROM local WHERE base = :base AND path = :path');
$insert = $dbh->prepare('INSERT INTO local (base, path, type, mtime) VALUES (:base, :path, :type, now())');
$mtime = $dbh->prepare('SELECT EXTRACT(EPOCH FROM mtime) AS mtime FROM local WHERE base = :base AND path = :path');
$set_mtime = $dbh->prepare('UPDATE local SET mtime = now() WHERE base = :base AND path = :path');
$hash_time_check = $dbh->prepare('SELECT hash, EXTRACT(EPOCH FROM hash_time) AS hash_time FROM local WHERE base = :base AND path = :path AND (hash_time IS NULL OR EXTRACT(EPOCH FROM hash_time) < :mtime)');
$set_hash = $dbh->prepare('UPDATE local SET hash = :hash, hash_time = now() WHERE base = :base AND path = :path');

# Loop through all the files
foreach ($FILES as $FILE) {

	# Construct the absolute path
	$PATH = $BASE_LOCAL . '/' . $FILE;

	# Does the path exist
	$EXISTS = false;
	$select->execute(array(':base' => $BASE_LOCAL, ':path' => $FILE));
	$result = $select->fetch();
	if (!$result) {
		$PARTS = pathinfo($PATH);
		$EXT = strtolower($PARTS['extension']);
		$NAME = strtolower($PARTS['filename']);
		unset($PARTS);

		$TYPE = 'other';
		if (is_dir($PATH)) {
			$TYPE = 'folder';
			if ($NAME == '.git') {
				$TYPE = 'ignored';
			}
		} else {
			if ($EXT == 'm4v' || $EXT == 'mkv' || $EXT == 'mp4' || $EXT == 'mov' ||
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
			} else if ($EXT == 'lastfindrecode' || $NAME == 'placeholder' || $EXT == 'plexignore') {
				$TYPE = 'ignored';
			} else if ($EXT == 'tmp' || $EXT == 'gitignore' || preg_match('/^\.smbdelete/', $NAME)) {
				$TYPE = 'ignored';
			}
		}
		if ($TYPE == 'other') {
			die('Unknown file type: ' . $PATH . ': ' . $NAME . '^' . $EXT . "\n");
		}
		echo 'Adding: ' . $PATH . ': ' . $TYPE . "\n";
		$insert->execute(array(':base' => $BASE_LOCAL, ':path' => $FILE, ':type' => $TYPE));
		if ($insert->rowCount() != 1) {
			print_r($insert->errorInfo());
			die('Unable to insert: ' . $PATH . "\n");
		}
	} else {
		$TYPE = $result['type'];
	}

	# Skip 'ingnored' files
	if ($TYPE == 'ignored') {
		continue;
	}

	# Update the mtime as needed
	$MTIME = trim(shell_exec('stat -c "%Y" ' . escapeshellarg($PATH)));
	$mtime->execute(array(':base' => $BASE_LOCAL, ':path' => $FILE));
	$result = $mtime->fetch(PDO::FETCH_ASSOC);
	if (!$result && !$result['mtime'] || !$MTIME) {
		die('Unable to find mtime for: ' . $PATH . "\n");
	} else if ($result['mtime'] < $MTIME) {
		$set_mtime->execute(array(':base' => $BASE_LOCAL, ':path' => $FILE));
	}

	# Update hashes as needed
	if ($TYPE != 'folder') {
		$hash_time_check->execute(array(':base' => $BASE_LOCAL, ':path' => $FILE, ':mtime' => $MTIME));
		$result = $hash_time_check->fetch(PDO::FETCH_ASSOC);
		if ($result) {
			echo 'Adding hash: ' . $PATH . "\n";
			$HASH = trim(shell_exec('md5sum ' . escapeshellarg($PATH) . ' | cut -d " " -f 1'));
			if (strlen($HASH) == 32) {
				$set_hash->execute(array(':base' => $BASE_LOCAL, ':path' => $FILE, ':hash' => $HASH));
			} else {
				die('Invalid hash (' . $HASH . ') for file: ' . $PATH . "\n");
			}
		} else {
			echo 'Hash is up-to-date: ' . $PATH . "\n";
		}
	}
}
unset($FILES);

?>
