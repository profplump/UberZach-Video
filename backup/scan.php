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

# Allow local-only scanning
$REMOTE = true;
if (isset($_ENV['REMOTE'])) {
	if (!$_ENV['REMOTE']) {
		$REMOTE = false;
	}
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
while ($row = $missing->fetch(PDO::FETCH_ASSOC)) {
	$trigger = false;
	$file = $row['base'] . '/' . $row['path'];

	if ($row['type'] == 'folder') {
		# Ensure the path exists and is a folder
		if (!is_dir($file)) {
			echo 'Missing folder: ' . $file . "\n";
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
$select = $dbh->prepare('SELECT base, path, type FROM files WHERE base = :base AND path = :path');
$insert = $dbh->prepare('INSERT INTO files (base, path, type, mtime) VALUES (:base, :path, :type, now())');
$check = $dbh->prepare('SELECT type, size, EXTRACT(EPOCH FROM mtime) AS mtime FROM files WHERE base = :base AND path = :path');
$set_mtime = $dbh->prepare('UPDATE files SET mtime = now() WHERE base = :base AND path = :path');
$set_size = $dbh->prepare('UPDATE files SET size = :size WHERE base = :base AND path = :path');
$set_type = $dbh->prepare('UPDATE files SET type = :type WHERE base = :base AND path = :path');
$check_hash = $dbh->prepare('SELECT hash, EXTRACT(EPOCH FROM hash_time) AS hash_time ' .
	'FROM files WHERE base = :base AND path = :path AND ' .
	'(hash_time IS NULL OR EXTRACT(EPOCH FROM hash_time) < :mtime)');
$set_hash = $dbh->prepare('UPDATE files SET hash = :hash, hash_time = now() WHERE base = :base AND path = :path');
foreach ($FILES as $file) {

	# Construct the absolute path
	$path = $BASE_LOCAL . '/' . $file;

	# Pick a file type
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
		preg_match('/^\.smbdelete/', $NAME) || preg_match('/\.mkv\.\w+$/', $path)) {
			$TYPE = 'ignored';
	} else if (is_dir($path)) {
		$TYPE = 'folder';
		if ($EXT == '' && $NAME == 'cmd') {
			$TYPE = 'ignored';
		}
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
		die('Unknown file type: ' . $path . ': ' . $NAME . '|' . $EXT . "\n");
	}

	# Add missing paths
	$select->execute(array(':base' => $BASE_LOCAL, ':path' => $file));
	if (!$select->fetch(PDO::FETCH_ASSOC)) {
		if ($DEBUG) {
			echo 'Adding: ' . $path . ': ' . $TYPE . "\n";
		}
		$insert->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':type' => $TYPE));
	}

	# Grab the DB entry
	$check->execute(array(':base' => $BASE_LOCAL, ':path' => $file));
	$row = $check->fetch(PDO::FETCH_ASSOC);
	if (!$row || !is_array($row)) {
		die('Unable to fetch entry for: ' . $file . "\n");
	}

	# Check the file type
	if ($row['type'] != $TYPE) {
		if ($DEBUG) {
			echo 'Updating type for: ' . $file . "\n";
		}
		$set_type->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':type' => $TYPE));
	}

	# Skip everything else for 'ignored' files
	if ($TYPE == 'ignored') {
		continue;
	}

	# Check the file mtime
	$mtime = trim(shell_exec('stat -c "%Y" ' . escapeshellarg($path)));
	if ($row['mtime'] < $mtime) {
		if ($DEBUG) {
			echo 'Updating mtime for: ' . $file . "\n";
		}
		$set_mtime->execute(array(':base' => $BASE_LOCAL, ':path' => $file));
	}

	# Check the file size
	$size = trim(shell_exec('stat -c "%s" ' . escapeshellarg($path)));
	if ($row['size'] != $size) {
		if ($DEBUG) {
			echo 'Updating size for: ' . $file . "\n";
		}
		$set_size->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':size' => $size));
	}
	unset($size);

	# Update hashes as needed
	if ($TYPE != 'folder') {
		$check_hash->execute(array(':base' => $BASE_LOCAL, ':path' => $file, ':mtime' => $mtime));
                $row = $check_hash->fetch(PDO::FETCH_ASSOC);
                if ($row) {
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
		}
		unset($row);
	}
	unset($mtime);

	unset($NAME);
	unset($EXT);
	unset($TYPE);
	unset($path);
}
unset($FILES);
unset($select);
unset($insert);
unset($check);
unset($set_mtime);
unset($set_size);
unset($check_hash);
unset($set_hash);

# Update priorities
$priority = $dbh->prepare('UPDATE files SET priority = :priority WHERE path LIKE :path');
$priority->execute(array(':priority' => 100,	':path' => 'Movies/%'));
$priority->execute(array(':priority' => 50,	':path' => 'iTunes/%'));
$priority->execute(array(':priority' => -50,	':path' => 'Backups/%'));
$priority->execute(array(':priority' => -100,	':path' => 'TV/%'));
unset($priority);

# If remote operations are enabled
if ($REMOTE) {
	# Log in to OpenDrive
	require_once 'opendrive.php';
	$session = login();

	# Validate the existence, type and size of all files we think on the remote system
	$select = $dbh->prepare('SELECT base, path, type, size FROM files WHERE remote_mtime IS NOT NULL AND path LIKE :subdir');
	$clear = $dbh->prepare('UPDATE files SET remote_mtime = NULL, remote_hash = NULL WHERE base = :base AND path = :path');
	$select->execute(array(':subdir' => $SUB_DIR . '/%'));
	while ($row = $select->fetch(PDO::FETCH_ASSOC)) {
		$trigger = false;
		if ($DEBUG > 2) {
			echo 'Checking remote: ' . $row['path'] . "\n";
		}

		if ($row['type'] == 'ignored') {
			continue;
		} else if ($row['type'] == 'folder') {
			if (!folderID($session, $row['path'])) {
				echo 'Missing remote folder: ' . $row['path'] . "\n";
				$trigger = true;
			}
		} else {
			$data = fileInfo($session, $row['path']);
			if (!$data) {
				echo 'Missing remote file: ' . $row['path'] . "\n";
				$trigger = true;
			} else if ($data['Size'] != $row['size']) {
				echo 'Wrong size remote file: ' . $row['path'] . ' (' . $data['size'] . '/' . $row['Size'] . ")\n";
				$trigger = true;
			}
			unset($data);
		}

		if ($DELETE && $trigger) {
			$clear->execute(array(':base' => $row['base'], ':path' => $row['path']));
		}
		unset($trigger);
	}
	unset($select);
	unset($clear);

	# Logout of OpenDrive
	logout($session);
	unset($session);
}

# Cleanup
unset($dbh);

?>
