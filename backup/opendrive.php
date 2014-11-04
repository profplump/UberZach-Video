<?php

# Debug
$DEBUG = 0;
if ($_ENV['DEBUG']) {
	$DEBUG = intval($_ENV['DEBUG']);
	if (!$DEBUG) {
		$DEBUG = 1;
	}
}

# On-disk config
require_once '.secrets';

# Config
$API_BASE = 'https://dev.opendrive.com/api/v1';
$API_VERSION = 10;

# PHP version support
if (!function_exists('curl_file_create')) {
	function curl_file_create($filename, $mimetype = '', $postname = '') {
		return '@' . $filename . ';filename=' .
		($postname ?: basename($filename)) .
		($mimetype ? ';type=' . $mimetype : '');
	}
}

# Open the DB connection
function dbOpen() {
	global $DB_STRING;
	global $DB_USER;
	global $DB_PASSWD;
	try {
		$dbh = new PDO($DB_STRING, $DB_USER, $DB_PASSWD);
	} catch (PDOException $e) {
		die('DB error: ' . $e->getMessage() . "\n");
	}
	return $dbh;
}

# Cleanup a path for better matching at OpenDrive
function pathCleanup($path) {
	$path = preg_replace('/\/+$/', '', $path);
	$path = preg_replace('/^\/+/', '', $path);
	return $path;
}

# Return the clean parent path of a provided path
function parentPath($path) {
	return dirname(pathCleanup($path));
}

# Return the clean base name of a provided path
function basePath($path) {
	return basename(pathCleanup($path));
}

function curlPostRaw($url, $data, $header = NULL) {
	global $API_BASE;
	global $CA_PATH;
	global $DEBUG;

	# Setup cURL
	$ch = curl_init($API_BASE . $url);
	curl_setopt_array($ch, array(
		CURLOPT_CAINFO => $CA_PATH,
		CURLOPT_POST => true,
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_POSTFIELDS => $data
	));
	if ($DEBUG >= 3) {
		curl_setopt($ch, CURLOPT_VERBOSE, true);
	}
	if ($header != NULL) {
		if (!is_array($header)) {
			$header = array($header);
		}
		curl_setopt($ch, CURLOPT_HTTPHEADER, $header);
	}

	# Send the request
	if ($DEBUG >= 2) {
		echo "Request: \n";
		print_r($data);
		echo "\n";
	}
	$response = curl_exec($ch);

	# Check for errors
	if ($response === FALSE){
	    die(curl_error($ch));
	}

	# Return
	return($response);
}

# POST the provided data to OpenDrive
function curlPost($url, $data) {
	$data = json_encode($data);
	$response = curlPostRaw($url, $data, 'Content-Type: application/json');
	$responseData = json_decode($response, true);
	return($responseData);
}

# GET from OpenDrive
function curlGet($url) {
	global $API_BASE;
	global $CA_PATH;
	global $DEBUG;

	# Setup cURL
	$ch = curl_init($API_BASE . $url);
	curl_setopt_array($ch, array(
		CURLOPT_CAINFO => $CA_PATH,
		CURLOPT_RETURNTRANSFER => true
	));
	if ($DEBUG >= 3) {
		curl_setopt($ch, CURLOPT_VERBOSE, true);
	}

	# Send the request
	if ($DEBUG >= 2) {
		echo "Request: \n";
		print_r($data);
		echo "\n";
	}
	$response = curl_exec($ch);

	# Check for errors
	if ($response === FALSE){
	    die(curl_error($ch));
	}

	# Return
	$responseData = json_decode($response, true);
	return($responseData);
}

# Login to OD and return the SessionID
function login() {
	global $API_VERSION;
	global $OD_USER;
	global $OD_PASSWD;
	$data = array(
		'username' 	=> $OD_USER,
		'passwd'	=> $OD_PASSWD,
		'version'	=> $API_VERSION
	);
	$response = curlPost('/session/login.json', $data);

	# Check the result
	if ($response['SessionID']) {
		return $response['SessionID'];
	}
	return false;
}

# Logout of OpenDrive
function logout($session) {
	$data = array(
		'session_id'	=> $session
	);
	$response = curlPost('/session/logout.json', $data);

	# Check the result
	if ($response['result'] == 'true') {
		return true;
	}
	return false;
}

# Return the ID of a folder
function folderID($session, $path) {
	$data = array(
		'session_id'	=> $session,
		'path'		=> $path
	);
	$response = curlPost('/folder/idbypath.json', $data);

	# Check the result
	if ($response['FolderId']) {
		return($response['FolderId']);
	}
	return false;
}

# Find the parent ID for a given path
function parentID($session, $path) {
	$parent = parentPath($path);

	$parentID = 0;
	if ($parent != '.') {
		$parentID = folderID($session, $parent);
	}
	return $parentID;
}

# Create a folder
function mkFolder($session, $path) {
	global $DEBUG;

	# Find the parent ID (if any)
	$parentID = parentID($session, $path);
	if ($parentID === false) {
		if ($DEBUG) {
			echo 'Invalid parent for path: ' . $path . "\n";
		}
		return false;
	}

	# POST
	$data = array(
		'session_id'		=> $session,
		'folder_name'		=> basePath($path),
		'folder_sub_parent'	=> $parentID,
		'folder_is_public'	=> 0
	);
	$response = curlPost('/folder.json', $data);

	# Check the result
	if ($response['FolderId']) {
		return($response['FolderId']);
	}
	return false;
}

# Trash a folder
function rmFolder($session, $path) {
	$id = folderID($session, $path);
	if (!$id) {
		return false;
	}

	$data = array(
		'session_id'	=> $session,
		'folder_id'	=> $id
	);
	$response = curlPost('/folder/trash.json', $data);

	# Check the result
	if ($response['DirUpdateTime']) {
		return true;
	}
	return false;
}

# Return the ID of a file
function fileID($session, $path) {
	$data = array(
		'session_id'	=> $session,
		'path'		=> $path
	);
	$response = curlPost('/file/idbypath.json', $data);

	# Check the result
	if ($response['FileId']) {
		return($response['FileId']);
	}
	return false;
}

# Return all file metadata
function fileInfo($session, $path) {
	$id = fileID($session, $path);
	if (!$id) {
		return false;
	}

	# GET
	$response = curlGet('/file/info.json/' . $session . '/' . $id);

	# Check the result
	if ($response['FileId']) {
		return($response);
	}
	return false;
}

# Upload the provided file to the given path
function fileUpload($session, $path, $file) {
	global $DEBUG;

	# Find the local file
	$stat = @stat($file);
	if ($stat === false) {
		if ($DEBUG) {
			echo 'Unable to stat: ' . $file . "\n";
		}
		return false;
	}

	# Find the parent ID
	$parentID = parentID($session, $path);
	if ($parentID === false) {
		if ($DEBUG) {
			echo 'No parent for path: ' . $path . "\n";
		}
		return false;
	}

	# Allocate
	$data = array(
		'session_id'	=> $session,
		'folder_id'	=> $parentID,
		'file_name'	=> basePath($path),
		'file_size'	=> $stat['size']
	);
	$response = curlPost('/upload/create_file.json', $data);
	$id = $response['FileId'];
	if (!$id) {
		if ($DEBUG) {
			echo 'Unable to allocate: ' . $path . "\n";
		}
		return false;
	}

	# Open
	$data = array(
		'session_id'	=> $session,
		'file_id'	=> $id,
		'file_size'	=> $stat['size']
	);
	$response = curlPost('/upload/open_file_upload.json', $data);
	$tmpPath = $response['TempLocation'];
	if (!$tmpPath) {
		if ($DEBUG) {
			echo 'Unable to open: ' . $path . "\n";
		}
		return false;
	}

	# Upload
	$cfile = curl_file_create($file, 'application/octet-stream', basePath($file));
	$data = array(
		'session_id'	=> $session,
		'file_id'	=> $id,
		'temp_location'	=> $tmpPath,
		'chunk_offset'	=> 0,
		'chunk_size'	=> $stat['size'],
		'file_data'	=> $cfile
	);
	$response = curlPostRaw('/upload/upload_file_chunk.json', $data, 'Expect:');
	if ($response) {
		$response = json_decode($response, true);
	}
	if (!$response || $response['TotalWritten'] != $stat['size']) {
		if ($DEBUG) {
			echo 'Unable to upload: ' . $path . "\n";
		}
		return false;
	}

	# Close
	$data = array(
		'session_id'	=> $session,
		'file_id'	=> $id,
		'temp_location'	=> $tmpPath,
		'file_time'	=> $stat['mtime'],
		'file_size'	=> $stat['size']
	);
	$response = curlPost('/upload/close_file_upload.json', $data);

	# Ignore 500 errors on close. It works anyway.
	if ($response && !$response['DirUpdateTime']) {
		if ($DEBUG) {
			echo 'Unable to close: ' . $path . "\n";
		}
		return false;
	}

	# Return the file size on success
	return $stat['size'];
}

?>
