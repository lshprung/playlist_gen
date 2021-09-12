#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use File::HomeDir;

require "./shared.pl";

# Variables to be set by the user
our $dbname = File::HomeDir->my_home . "/Music/library.db";
our $output_dir; # By default, output in current directory
our $table_name = "LIBRARY";

my $statement; #Hold statements for sqlite


# Write to an m3u file to create a playlist
# 	@_[0] -> m3u file path
# 	@_[1] -> array of file paths
sub append_to_m3u {
	open FH, ">> $_[0]" or die $!;

	for my $line ($_[1]){
		print FH $line;
	}

	close FH;
}

my $dbh = DBI->connect("DBI:SQLite:dbname=$dbname", "", "", { RaiseError => 1}) or die $DBI::errstr;
# DEBUG
print "Opened database successfully\n";

# Check that table exists
$statement = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$table_name';";
if (!db_cmd($dbh, $statement)){
	die "Error: table \"$table_name\" does not exist in $dbname";
}
