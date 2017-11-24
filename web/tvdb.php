#!/usr/local/bin/php
<?php
require_once('includes/main.php');
require_once('includes/tvdb/init.php');

# TEST
if (!update(275557)) {
	return -1;
}
return 0;
# END TEST

function update($id) {
	return (updateSeries($id) && updateEpisodes($id));
}

function updateEpisodes($id) {

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
		$data = array(
			'id' => $id,
			'season' => $episode->season,
			'number' => $episode->number,
			'airdate' => $episode->firstAired->format('c'), 
			'name' => $episode->name,
			'desc' => $episode->overview
		);
		if (!insertOrUpdate($insert, $update, $data)){
			$err++;
		}
	}
	return ($err == 0);
}

function updateSeries($id) {

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
	return insertOrUpdate($insert, $update, $data);
}

function insertOrUpdate($insert, $update, $data) {
	if (!$insert->execute($data) && !$update->execute($data)) {
		if (DEBUG) {
			print_r($dbh->errorInfo());
		}
		return false;
	}
	return true;
}
?>
