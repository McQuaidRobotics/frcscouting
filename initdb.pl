#!/usr/bin/perl

$name=shift(@ARGV);
if(-e "data/$name/data.db"){die("Database already exists");}
use DBI;
my $db = DBI->connect("dbi:SQLite:dbname=data/$name/data.db","","",{RaiseError=>1},) or die $DBI::errstr;

$db->do("CREATE TABLE `data` (`id` varchar(16) NOT NULL, `dkey` varchar(64), `user` int(11), `val` int(11), `visible` int(11) NOT NULL DEFAULT '1', `added` datetime DEFAULT CURRENT_TIMESTAMP)");
$db->do("CREATE INDEX `id` on `data`(`id`,`dkey`)");
$db->do("CREATE TABLE `datas` (`id` varchar(16) NOT NULL, `dkey` varchar(64), `user` int(11), `val` text, `visible` int(11) NOT NULL DEFAULT '1', `added` datetime DEFAULT CURRENT_TIMESTAMP)");
$db->do("CREATE INDEX `ids` on `datas`(`id`,`dkey`)");
$db->do("CREATE TABLE `question` (`id` varchar(64) NOT NULL, `numleft` int(11) NOT NULL, `waituntil` datetime, `priority` int(11) NOT NULL, `role` varchar(16) NOT NULL)");
$db->do("CREATE INDEX `qq` on `question`(`id`)");

$db->disconnect();

if(!-e "data/users.db"){
  $db = DBI->connect("dbi:SQLite:dbname=data/users.db","","",{RaiseError=>1},) or die $DBI::errstr;

  $db->do("CREATE TABLE `user` (`id` INTEGER PRIMARY KEY, `name` varchar(32) NOT NULL, `exp` int(11) NOT NULL DEFAULT '0', `role` varchar(16) NOT NULL DEFAULT '')");

  $db->disconnect();
}

