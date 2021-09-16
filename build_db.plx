#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use DBI;
use Audio::Scan;
use File::HomeDir;

require "./shared.pl";


# Keep track of columns that need to be created in the database
our %columns;

# Variables to be set by user
our $music_dir = File::HomeDir->my_home . "/Music/";
our $dbname;
our $table_name = "LIBRARY";
our $extensions_list = "flac,mp3,ogg";
our %extensions;

# Keep track of options that have been set
our %options = (
	append => 0,
	output => 0,
	quiet  => 0
);

my %data;      #Hold info from Audio::Scan
my @db_output; #Hold array containing output from a sql statement
my $statement; #Hold statements for sqlite


# Wrapper to handle calls to Audio::Scan->scan(); returns tags hash
# 	@_[0] -> file to scan
sub audio_scan {
	my $data = Audio::Scan->scan("$_[0]");
	$data = $data->{tags};
	return %$data;
}

sub build_extension_hash {
	my @extensions_arr = split /[,]/,$extensions_list;
	for my $i (@extensions_arr){
		$extensions{$i} = 1;
	}
}


# Scan a directory recursively, return an array of files (optionally, matching a certain file extension or extensions)
# 	@_[0] -> $music_dir
# 	@_[1] -> hash of file extensions to scan for
sub get_files {
	my @file_list;
	my @file_split;

	# Remove extra /'s from the end of $_[0]
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
				# DEBUG
				if (!$options{quiet}){
					print "Found $dir_path/$file\n";
				}

				push(@file_list, "$dir_path/$file");
			}
		}
	}

	closedir $dh;
	return @file_list;
}

# Print a help message
sub print_help {
	print
"Usage:
  $0 [OPTION]... [DIRECTORY]

Generate a database for audio files in DIRECTORY (by default ~/Music).

Options:
  -a, --append			append to database file, instead of overwriting it
  -e, --extension EXTENSIONS	Set file extensions to look for, separated by commas (default is flac,mp3,ogg)
  -h, --help			display this help and exit
  -o, --output FILE		specify output file for database (default is library.db at the root of DIRECTORY)
  -q, --quiet			quiet (no output)
  -t, --table-name TABLE	specify table name in database file (default is LIBRARY)
";
}


# parse flags and arguments
for (my $i = 0; $i <= $#ARGV; $i++){
	if ($ARGV[$i] =~ /-a|--append/){
		$options{append} = 1;
	}

	elsif ($ARGV[$i] =~ /-e|--extension/){
		$i++;
		$extensions_list = $ARGV[$i];
	}

	elsif ($ARGV[$i] =~ /-h|--help/){
		print_help();
		exit;
	}

	elsif ($ARGV[$i] =~ /-o|--output/){
		$i++;
		$dbname = "$ARGV[$i]";
		$options{output} = 1;
	}

	elsif ($ARGV[$i] =~ /-q|--quiet/){
		$options{quiet} = 1;
	}

	elsif ($ARGV[$i] =~ /-t|--table-name/){
		$i++;
		$table_name = $ARGV[$i];
	}

	elsif ($ARGV[$i] =~ /^[^-]/){
		$music_dir = "$ARGV[$i]";
		last;
	}
}

# Remove trailing '/' from $music_dir and handle if $dbname was not set by the user
$music_dir =~ s/\/+$//g;
if (!$options{output}){
	$dbname = $music_dir . "/library.db";
}
for my $i (keys %extensions){
	print "$i\n";
}

# Test to ensure $music_dir is a valid directory
if (! -d $music_dir){
	die "Error: \"$music_dir\" is not a directory\n";
}

# Build the extensions hash for use in get_files
build_extension_hash();

# DEBUG
if (!$options{quiet}){
	print "Looking through files in $music_dir\n";
}

# Get a list of files in $music_dir
my @file_list = get_files($music_dir, %extensions);

# Quit if @file_list is empty
if ($#file_list < 1){
	die "Error: Could not find any files in \"$music_dir\" matching extension(s) \"$extensions_list\"\n";
}

# Append tags to %columns
for my $file (@file_list){
	%data = audio_scan("$file");
	for my $i (keys %data){
		$columns{$i} = '1';
	}
}
# DEBUG
if (!$options{quiet}){
	for my $i (keys %columns){
		print "Found tag \"$i\"\n";
	}
}

# Connect to sqlite database created in the base of $music_dir
my $dbh = DBI->connect("DBI:SQLite:dbname=$dbname", "", "", { RaiseError => 1}) or die $DBI::errstr;
# DEBUG
if (!$options{quiet}){
	print "Opened database successfully\n";
}

# Overwrite $table_name if it exists (TODO alert user to overwrite)
# If --append flag was passed, skip this step
if (!$options{append}){
	$statement = "DROP TABLE if EXISTS $table_name";
	db_cmd($dbh, $statement, "Overwriting table \"$table_name\"");

	# Create table $table_name in the database with columns from %columns
	# Need to create additional columns for ID and PATH
	$statement = "CREATE TABLE $table_name 
	(ID INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
	PATH TEXT NOT NULL UNIQUE";
	for my $i (sort(keys %columns)){
		$statement = $statement . ",
		\"$i\" TEXT";
	}
	$statement = $statement . ");";
	db_cmd($dbh, $statement, "Created table successfully");
}

# If appending, add columns where necessary
else {
	for my $i (sort(keys %columns)){
		$statement = "SELECT COUNT(*) AS CNTREC FROM pragma_table_info('$table_name') WHERE name='$i';";
		@db_output = flatten_array(db_cmd($dbh, $statement));
		if (!$db_output[0]){
			$statement = "ALTER TABLE $table_name ADD COLUMN \"$i\";";
			db_cmd($dbh, $statement);
		}
	}
}

# Add each file from @file_list to the table
$statement = "INSERT INTO $table_name(PATH)
VALUES";
for my $file (@file_list){
	# Skip existing files
	@db_output = flatten_array(db_cmd($dbh, "SELECT count(*) FROM $table_name WHERE PATH='$file';"));

	if(!$db_output[0]){
		$statement = $statement . "(\"$file\"),";
	}
}
$statement =~ s/[,]$/;/g;
db_cmd($dbh, $statement);

# Set each file's tags in the table
for my $file (@file_list){
	$statement = "UPDATE $table_name
	SET ";

	%data = audio_scan("$file");

	# Loop to add all the columns for $statement
	for my $i (sort(keys %data)){
		next if $i eq "MCDI"; #FIXME MCDI field creates issues
		$data{$i} =~ s/\"/\'\'/g;
		$statement = $statement . "\"$i\" = \"";

		# If tag is an array, encode the array into semicolon-separated string
		if (ref($data{$i}) eq 'ARRAY'){
			for my $j (flatten_array($data{$i})){
				$statement = $statement . "$j;";
			}
			$statement =~ s/[;]+$//g;
			$statement = $statement . "\",";
		}

		else {
			$statement = $statement . "$data{$i}\",";
		}
	}
	$statement =~ s/[,]$/\n/g;

	# Specify this insertion is for $file only
	# Encode to fix issues with non-ascii characters
	utf8::encode($statement);
	$statement = $statement . "WHERE PATH = \"$file\";";

	#FIXME MCDI tag is binary. This should be considered and handled in a secondary file
	db_cmd($dbh, $statement, "Updated tags for $file");
}

 
# Disconnect from sqlite database
$dbh->disconnect();
