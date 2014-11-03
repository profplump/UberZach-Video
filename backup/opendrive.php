#!/usr/local/bin/php
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

function login() {
	global $API_BASE;
	global $OD_USER;
	global $OD_PASSWD;
	
	$ch = curl_init($API_BASE . '/session/login.json');
	curl_setopt_array($ch, array(
	    CURLOPT_POST => TRUE,
	    CURLOPT_RETURNTRANSFER => TRUE,
	    CURLOPT_HTTPHEADER => array(
	        'Content-Type: application/json'
	    ),
	    CURLOPT_POSTFIELDS => json_encode($postData)
	));

	// Send the request
	$response = curl_exec($ch);

	// Check for errors
	if($response === FALSE){
	    die(curl_error($ch));
	}

	// Decode the response
	$responseData = json_decode($response, TRUE);
	return($responseData);
}

?>
