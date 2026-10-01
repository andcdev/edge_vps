#!/bin/sh
# Crea nel database SQLite di Roundcube la tabella di rcguard, se non c'è (l'initdb di Roundcube non la conosce).
exec php -r '
$db = new PDO("sqlite:/var/roundcube/db/sqlite.db");
if ($db->query("SELECT name FROM sqlite_master WHERE type=\"table\" AND name=\"rcguard\"")->fetch()) {
    echo "rcguard: tabella presente\n";
    exit(0);
}
$db->exec(file_get_contents("/var/www/html/plugins/rcguard/SQL/sqlite.initial.sql"));
echo "rcguard: tabella creata\n";
'
