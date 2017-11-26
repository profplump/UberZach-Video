#!/usr/local/bin/php
<?php

define('DEBUG', true);
set_time_limit(0);
require_once 'includes/main.php';
require_once 'includes/tvdb_update.php';
global $EXISTS_FILES;
global $CONTENT_FILES;

# Allow single-ID use
if ($argv[1]) {
	return tvdb_update($argv[1], true);
}

# Files->DB import
$insertSQL = 'INSERT INTO search (id, ' . join(', ', $EXISTS_FILES) . ', ' . join(',', $CONTENT_FILES) .
	') VALUES (:id, :' . join(', :', $EXISTS_FILES) . ', :' . join(', :', $CONTENT_FILES) . ')';
$updateSQL = 'UPDATE search SET ';
foreach ($EXISTS_FILES as $name) {
	if ($name != $EXISTS_FILES[0]) {
		$updateSQL .= ', ';
	}
	$updateSQL .= $name . '=:' . $name;
}
foreach ($CONTENT_FILES as $name) {
	$updateSQL .= ', ' . $name . '=:' . $name;
}
$updateSQL .= ' WHERE id=:id';
$dbh = new PDO(TVDB_DBN);
$insert = $dbh->prepare($insertSQL);
$update = $dbh->prepare($updateSQL);
$insertDone = $dbh->prepare('INSERT INTO search_season (id, season, complete) VALUES (:id, :season, :complete)');
$updateDone = $dbh->prepare('UPDATE search_season SET complete=:complete WHERE id=:id AND season=:season');

# Update all series
$all_series = allSeriesSeasons(TV_PATH, false);
foreach ($all_series as $series => $seasons) {
	$flags = readFlags($series);
	if (!$flags['tvdb-id']) {
		echo 'No TVDB ID for: ' . $series . "\n";
		continue;
	}

	if (DEBUG) {
		echo 'Updating: ' . $series . ' (' . $flags['tvdb-id'] . ")\n";
	}
	tvdb_update($flags['tvdb-id']);

	$data = array('id' => $flags['tvdb-id']);
	foreach ($EXISTS_FILES as $name) {
		$data[$name] = $flags[$name] ? 't' : 'f';
	}
	foreach ($CONTENT_FILES as $name) {
		$data[$name] = $flags[$name];
	}
	if (!$insert->execute($data) && !$update->execute($data)) {
		print_r($dbh->errorInfo());
	}

	$data = array('id' => $flags['tvdb-id']);
	foreach ($seasons as $number => $monitored) {
		$data['season'] = $number;
		$data['complete'] = $monitored ? 'f' : 't'; 
		if (!$insertDone->execute($data) && !$updateDone->execute($data)) {
			print_r($dbh->errorInfo());
		}		
	}
}

?>
