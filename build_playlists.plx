#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use File::HomeDir;

require "./shared.pl";

# Variables to be set by the user
our $dbname = File::HomeDir->my_home . "/Music/library.db";
our $table_name = "LIBRARY";
our @tags_of_interest = ("PATH"); # Record TAG arguments (PATH will always be of interest)
our $output_pattern;              # Record OUTPUT_PATTERN argument
our $statement_arg;               # Record SQL_STATEMENT argument

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
	if (eof $filehandle){
		print $filehandle "#EXTM3U\n\n";
	}

	# TODO add support for EXTINF metadata (track runtime, Display name)
	for my $line (@_){
		print $filehandle "$line\n";
		# DEBUG
		print "Added $line\n";
	}
}

# Print a help message
# TODO support custom table name
# TODO support custom database path
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
  $0 ALBUM,ALBUMARTIST \"/home/john/Music/playlists/{ALBUMARTIST}-{ALBUM}.m3u\"			Generate a playlist for every combination of ALBUM and ALBUMARTIST in the database, with the output file pattern ALBUMARTIST-ALBUM.m3u
  $0 --sql \"SELECT PATH FROM LIBRARY WHERE ARTIST='Steely Dan';\" steely_dan.m3u	Generate a playlist based on the output of this SQL statement
  $0 --sql \"ARTIST='Steely Dan';\" steely_dan.m3u					If an incomplete SQL statement is received, the \"SELECT PATH FROM {table_name} WHERE \" part of the SQL statement is assumed to be implied
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
		if (!$options{sql} and scalar(@tags_of_interest) <= 1){
			push(@tags_of_interest, split(',', "$ARGV[$i]"));
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
	# If query does not start with 'SELECT', assume it is implied
	if (!($statement_arg =~ /^SELECT/i)){
		$statement_arg = "SELECT PATH FROM $table_name WHERE " . $statement_arg;
	}

	@db_output = flatten_array(db_cmd($dbh, $statement_arg, "SQL_STATEMENT returned successfully"));

	# TODO add switch for appending
	# TODO alert user to overwrite
	open FH, "> $output_pattern" or die $!;
	# DEBUG
	print "Opened $output_pattern\n";
	build_m3u(*FH, @db_output);
	close FH;
}

# Go through every entry to build multiple playlists
else {
	my %tag_hash;    # Track tag values for each file
	my $output_file; # Output file, based on output_pattern

	@db_output = flatten_array(db_cmd($dbh, "SELECT count(*) FROM $table_name;"));
	my $row_count = $db_output[0];

	# Go through each row by ID
	for my $i (1..$row_count){
		# Get output for the PATH, plus each tag of interest; store it in tag_hash
		$statement = join(',', @tags_of_interest);
		@db_output = flatten_array(db_cmd($dbh, "SELECT $statement FROM $table_name WHERE ID=$i;"));
		for my $j (0..scalar(@db_output)-1){
			$tag_hash{$tags_of_interest[$j]} = $db_output[$j];

			# remove illegal filename characters, replace them with underscore
			if (!($tags_of_interest[$j] eq "PATH")){
				$tag_hash{$tags_of_interest[$j]} =~ s/[\/<>:"\\|?*]/_/g;
			}
		}

		## DEBUG TODO remove me
		#for my $i (keys %tag_hash){
		#	for my $j ($tag_hash{$i}){
		#		print "$j\n";
		#	}
		#}
		#die;

		# TODO break up by semicolon (signifying array of tag values)
		# Determine output_file
		$output_file = $output_pattern;
		$output_file =~ s/[{]([^}]*)[}]/$tag_hash{$1}/g;

		# Open the file for writing
		open FH, ">> $output_file" or die $!;
		# DEBUG
		print "Opened $output_file\n";
		build_m3u(*FH, $tag_hash{PATH});
		close FH;
	}
}

# Disconnect from sqlite database
$dbh->disconnect();
