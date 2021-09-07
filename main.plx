#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use DBI;
use Audio::Scan;
use File::HomeDir;


# Keep track of columns that need to be created in the database
our %columns;

# Variables to be set by user (TODO)
our $music_dir = File::HomeDir->my_home . "/Music/";
our $dbname = "library.db";
our $table_name = "LIBRARY";
our %extensions = (
	flac => '1',
	mp3 => '1',
	ogg => '1'
);

my $data;      #Hold info from Audio::Scan
my $statement; #Hold statements for sqlite


# Wrapper to handle sqlite commands
# 	@_[0]            -> database handle
# 	@_[1]            -> command/statement
# 	@_[2] (optional) -> output statement
sub db_cmd {
	my $rv = $_[0]->do($_[1]);
	if ($rv < 0){
		die $DBI::errstr;
	}

	if (defined $_[2]){
		print "$_[2]\n";
	}
}


# Scan a directory recursively, return an array of files (optionally, matching a certain file extension or extensions)
# 	@_[0] -> $music_dir
# 	@_[1] -> hash of file extensions to scan for
sub get_files {
	my @file_list;
	my @file_split;

	# Remove extra /'s from the end of $_[0]
	$_[0] =~ s/\/+$//g;
	my $dir_path = $_[0];
	my $extensions = $_[1];

	opendir my $dh, "$dir_path" or die "$!";
	while (my $file = readdir($dh)) {
		# Skip . and .. directories
		if ($file eq "." or $file eq ".."){
			next;
		}

		if (-d "$dir_path/$file"){
			push(@file_list, get_files("$dir_path/$file", %extensions));
		}

		elsif (-f "$dir_path/$file" and -r "$dir_path/$file"){
			# Check that the extension matches
			@file_split = split /\./, "$dir_path/$file";
			if (defined $extensions{"$file_split[-1]"} and $extensions{"$file_split[-1]"} == 1){
				push(@file_list, "$dir_path/$file");
			}
		}
	}

	closedir $dh;
	return @file_list;
}

# Test scan for Audio::Scan module
sub scan_test {
	my $data = Audio::Scan->scan("/home/louie/Music/Bjork/Debut/01 Human Behaviour.flac");
	$data = $data->{tags};
	for (keys %$data){
		print "$_ -> $data->{$_}\n";
	}
}


# TODO parse flags and arguments

# Test to ensure $music_dir is a valid directory
if (! -d $music_dir){
	die "Error: \"$music_dir\" is not a directory\n";
}

# Get a list of files in $music_dir
print "Looking through files in $music_dir\n";
my @file_list = get_files($music_dir, %extensions);
# DEBUG
for my $i (sort @file_list){
	print "$i\n";
}

# Append tags to %columns
for my $file (@file_list){
	$data = Audio::Scan->scan("$file");
	$data = $data->{tags};
	for my $i (keys %$data){
		$columns{$i} = '1';
	}
}
# DEBUG
for my $i (keys %columns){
	print "$i\n";
}

# Connect to sqlite database created in the base of $music_dir
my $dbh = DBI->connect("DBI:SQLite:dbname=$music_dir/$dbname", "", "", { RaiseError => 1}) or die $DBI::errstr;
print "Opened database successfully\n";

# Create table in the database
$statement = "CREATE TABLE $table_name 
(ID INT PRIMARY KEY NOT NULL);";
db_cmd($dbh, $statement, "Created table successfully");
 
# Get tags for each file
#for my $file (sort @file_list){
#	$data = Audio::Scan->scan("$file");
#	$data = $data->{tags};
#	for my $i (keys %$data){
#		print "$i -> $data->{$i}\n";
#	}
#}

# Disconnect from sqlite database
$dbh->disconnect();
