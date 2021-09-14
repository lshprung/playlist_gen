#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use File::HomeDir;

require "./shared.pl";

# Variables to be set by the user
our $dbname = File::HomeDir->my_home . "/Music/library.db";
our $table_name = "LIBRARY";
our @tags_of_interest; # Record TAG arguments
our $output_pattern;   # Record OUTPUT_PATTERN argument
our $statement_arg;    # Record SQL_STATEMENT argument

# Keep track of options that have been set
our %options = (
	sql => 0
);

my @db_output; #Hold array containing output from a sql statement
my $statement; #Hold statements for sqlite


# Write to an m3u file to create a playlist
# 	@_[0] -> m3u file handle
# 	@_[1] -> array of audio file paths
sub build_m3u {
	my $filehandle = shift;

	# Create m3u header
	# TODO check if file is empty before adding the header
	print $filehandle "#EXTM3U\n\n";

	# TODO add support for EXTINF metadata (track runtime, Display name)
	for my $line (@_){
		print $filehandle "$line\n";
	}
}

# Print a help message
sub print_help {
	print
"Usage:
  $0 [OPTION]... TAG [OUTPUT_PATTERN]
  $0 [OPTION]... --sql SQL_STATEMENT [OUTPUT]

Generate m3u playlist(s) for audio files in a database (by default ~/Music/library.db).
Playlists can be generated based on columns (TAGs) in the database or based on a SQL statement output.
Multiple tags can be specified. They must be comma-separated.
If tags are specified, an output pattern can also be specified (see Examples).

Options:
  -h, --help			display this help and exit
      --sql SQL_STATEMENT	generate a single playlist based on output of some SQL statement

Examples:
  $0 ALBUM,ALBUMARTIST ~/Music/playlists/{ALBUMARTIST}-{ALBUM}.m3u			Generate a playlist for every combination of ALBUM and ALBUMARTIST in the database, with the output file pattern ALBUMARTIST-ALBUM.m3u
  $0 --sql \"SELECT PATH FROM LIBRARY WHERE ARTIST='Steely Dan';\" steely_dan.m3u	Generate a playlist based on the output of this SQL statement
  $0 --sql \"ARTIST='Steely Dan';\" steely_dan.m3u					If an incomplete SQL statement is received, the \"SELECT PATH FROM LIBRARY WHERE \" part of the SQL statement is assumed to be implied
";
}


# parse flags and arguments
for (my $i = 0; $i <= $#ARGV; $i++){
	if ($ARGV[$i] =~ /-h|--help/){
		print_help();
		exit;
	}

	elsif ($ARGV[$i] =~ /--sql/){
		$i++;
		$statement_arg = "$ARGV[$i]";
		$options{sql} = 1;
	}

	elsif ($ARGV[$i] =~ /^[^-]/){
		# This arg should contain the list of tags
		if (!$options{sql} and !scalar(@tags_of_interest)){
			@tags_of_interest = split(',', "$ARGV[$i]");
		}
		# This arg should contain the output_pattern
		else {
			$output_pattern = "$ARGV[$i]";
			last;
		}
	}
}

# Connect to database file
my $dbh = DBI->connect("DBI:SQLite:dbname=$dbname", "", "", { RaiseError => 1}) or die $DBI::errstr;
# DEBUG
print "Opened database successfully\n";

# Check that table exists
$statement = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$table_name';";
if (!db_cmd($dbh, $statement)){
	die "Error: table \"$table_name\" does not exist in $dbname";
}

# If sql mode is turned on, build a playlist based on a query
if ($options{sql}){
	@db_output = flatten_array(db_cmd($dbh, $statement_arg, "SQL_STATEMENT returned successfully"));

	# TODO add switch for appending
	# TODO alert user to overwrite
	open FH, "> $output_pattern" or die $!;
	build_m3u(*FH, @db_output);
}
