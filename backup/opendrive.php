<?php

# Debug
$DEBUG = false;
if ($_ENV['DEBUG']) {
	$DEBUG = true;
}

# On-disk config
require_once '.secrets';

# Config
$API_BASE = 'https://dev.opendrive.com/api/v1';
$API_VERSION = 10;

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

# POST the provided data to OpenDrive
function curlPost($url, $data) {
	global $API_BASE;
	global $CA_PATH;

	# Setup cURL
	$ch = curl_init($API_BASE . $url);
	curl_setopt_array($ch, array(
		CURLOPT_CAINFO => $CA_PATH,
		CURLOPT_POST => true,
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_HTTPHEADER => array(
			'Content-Type: application/json'
		),
		CURLOPT_POSTFIELDS => json_encode($data)
	));

	# Send the request
	$response = curl_exec($ch);

	# Check for errors
	if ($response === FALSE){
	    die(curl_error($ch));
	}

	# Return
	$responseData = json_decode($response, TRUE);
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
		'version'	=> $API_VERISON
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

?>
