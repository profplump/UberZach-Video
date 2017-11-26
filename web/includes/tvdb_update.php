<?php
require_once('includes/main.php');
require_once('includes/tvdb/init.php');

function tvdb_lastModified($id) {
	# DB init
	$dbh = new PDO(TVDB_DBN);
	$select = $dbh->prepare('SELECT modified FROM series WHERE id=:id');

	# Query
	$select->execute(array('id' => $id));
	$result = $select->fetch(PDO::FETCH_ASSOC);

	# Cast as a datetime
	$time = 0;
	if ($result && is_array($result) && $result['modified']) {
		$time = strtotime($result['modified']);
	}
	return $time;
}

function tvdb_update($id, $force = false) {
	if (!$force) {
		$modified = tvdb_lastModified($id);
		if (time() - $modified < TVDB_UPDATE_TIMEOUT) {
			if (DEBUG) {
				echo 'Skipping due to recent update: ' . $id . "\n";
			}
			return true;
		}
	}
	return (tvdb_series($id) && tvdb_episodes($id));
}

function tvdb_episodes($id) {

	# Fetch
	$tvdb = new Moinax\TvDb\Client(TVDB_URL, TVDB_API_KEY);
	$episodes = $tvdb->getSerieEpisodes($id);

	# DB init
	$dbh = new PDO(TVDB_DBN);
	$insert = $dbh->prepare(
		'INSERT INTO episodes ("id", "season", "episode", "airdate", "name", "desc", "modified") ' .
		'VALUES (:id, :season, :number, :airdate, :name, :desc, now())'
	);
	$update = $dbh->prepare(
		'UPDATE episodes SET ' .
		'airdate=:airdate, name=:name, "desc"=:desc, modified=now() ' .
		'WHERE id=:id and season=:season and episode=:number'
	);

	# Update
	$error = 0;
	foreach ($episodes['episodes'] as $episode) {
		$airdate = null;
		if (is_object($episode->firstAired)) {
			$airdate = $episode->firstAired->format('c');
		} else if (DEBUG) {
			echo 'No airdate for: ' . $id . '::' . $episode->season . ':' . $episode->number . "\n";
		}
		$data = array(
			'id' => $id,
			'season' => $episode->season,
			'number' => $episode->number,
			'airdate' => $airdate,
			'name' => $episode->name,
			'desc' => $episode->overview
		);
		if (!tvdb_insert($insert, $update, $data)) {
			if (DEBUG) {
				print_r($dbh->errorInfo());
			}
			$err++;
		}
	}
	return ($err == 0);
}

function tvdb_series($id) {

	# Fetch series and episodes
	$tvdb = new Moinax\TvDb\Client(TVDB_URL, TVDB_API_KEY);
	$series = $tvdb->getSerie($id);

	# DB init
	$dbh = new PDO(TVDB_DBN);
	$insert = $dbh->prepare(
		'INSERT INTO series ("id", "name", "desc", "year", "modified") ' .
		'VALUES (:id, :name, :desc, :year, now())'
	);
	$update = $dbh->prepare(
		'UPDATE series SET ' .
		'name=:name, "desc"=:desc, year=:year, modified=now()' .
		'WHERE id=:id'
	);


	# Update
	$data = array(
		'id' => $id,
		'name' => $series->name,
		'desc' => $series->overview,
		'year' => $series->firstAired->format('Y')
	);
	if (!tvdb_insert($insert, $update, $data)) {
		if (DEBUG) {
			print_r($dbh->errorInfo());
		}
		return false;
	}
	return true;
}

function tvdb_insert($insert, $update, $data) {
	if (!$insert->execute($data) && !$update->execute($data)) {
		return false;
	}
	return true;
}
?>
