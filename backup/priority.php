#!/usr/local/bin/php
<?php

# Includes
require_once 'opendrive.php';

# Open the DB connection
$dbh = dbOpen();

# Prepare statements
$update = $dbh->prepare('UPDATE files SET priority = :priority WHERE path LIKE :path');

# Set several groups
$update->execute(array(':priority' => 100,	':path' => 'Movies/%'));
$update->execute(array(':priority' => 50,	':path' => 'iTunes/%'));
$update->execute(array(':priority' => -50,	':path' => 'Backups/%'));
$update->execute(array(':priority' => -100,	':path' => 'TV/%'));

?>
