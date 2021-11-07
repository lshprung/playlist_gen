#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use File::HomeDir;
use File::Spec;

require "./shared.pl";

# Variables to be set by the user
our $dbname = File::HomeDir->my_home . "/Music/library.db";
our $table_name = "LIBRARY";
our @tags_of_interest = ("PATH"); # Record TAG arguments (PATH will always be of interest)
our $output_pattern;              # Record OUTPUT_PATTERN argument
our $statement_arg;               # Record SQL_STATEMENT argument
our $separator = ';';             # Symbol set to separate multiple values per file tag (TODO add flags related to this)

# Keep track of options that have been set
our %options = (
	quiet => 0,
	relative => 0,
	sql => 0
);

my @db_output; #Hold array containing output from a sql statement
my $statement; #Hold statements for sqlite


# TODO quit with help message if no arguments set
# TODO add support for overwriting playlists
# Write to an m3u file to create a playlist
# 	@_[0] -> m3u file path
# 	@_[1] -> m3u file handle
# 	@_[2] -> array of audio file paths
sub build_m3u {
	my $filename = shift;
	my $filehandle = shift;

	# Create m3u header if the file is new
	if ((-s $filename) == 0){
		print $filehandle "#EXTM3U\n\n";
	}

	# TODO add support for EXTINF metadata (track runtime, Display name)
	for my $line (@_){
		# Set $line to a relative path compared to $filename if relative option is set
		if($options{relative}){
			$filename = File::Spec->rel2abs($filename);
			$line = File::Spec->abs2rel($line, $filename);
			$line =~ s/^\.\.\///;
		}

		print $filehandle "$line\n";
		# DEBUG
		if (!$options{quiet}){
			print "Added $line\n";
		}
	}
}

# Subroutine to determine the output files for a given file
#   @_[0] -> reference to tag hashes
sub get_output_files {
	my @output;
	my %tag_hash = @_;
	my %count_hash; #keep track of index from tag_hash
	my %value_hash; #keep track of value from tag_hash
	my @keys_arr;   #array of keys from tag_hash

	# Remove PATH from tag_hash
	delete($tag_hash{"PATH"});
	
	# Initialize count_hash and value_hash
	for my $i (sort(keys %tag_hash)){
		push(@keys_arr, $i);
		#print("@keys_arr\n");
		$count_hash{$i} = 0;
		#print("$i -> $count_hash{$i}\n");
		$value_hash{$i} = @{$tag_hash{$i}}[0];
		#print("$i -> $value_hash{$i}\n");
	}

	# Loop through all possible combinations of tags and append to @output
	OUTER: while(1){
		push(@output, $output_pattern);
		$output[-1] =~ s/[{]([^}]*)[}]/$value_hash{$1}/g;

		# Update
		INNER: for my $key_index (@keys_arr){
			$count_hash{$key_index} = (($count_hash{$key_index}+1) % scalar(@{$tag_hash{$key_index}}));
			$value_hash{$key_index} = @{$tag_hash{$key_index}}[$count_hash{$key_index}];
			if($count_hash{$key_index} > 0){
				next OUTER;
			}
		}
		last OUTER;
	}

	return @output;
}


	#for my $i (keys %tag_hash){
	#	if (!($i eq "PATH")){
	#		print("$i -> @{$tag_hash{$i}}\n");
	#	}
	#	else{
	#		print("$i -> $tag_hash{$i}\n");
	#	}
	#}

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
  -i, --input FILE		specify path for database file to use to generate playlists (default is \$HOME/Music/library.db)
  -h, --help			display this help and exit
  -q, --quiet			quiet (no output)
      --relative		use relative paths instead of absolute paths for entries
      --sql SQL_STATEMENT	generate a single playlist based on output of some SQL statement
  -t, --table-name TABLE	specify table name in database file (default is LIBRARY)

Examples:
  $0 ALBUM,ALBUMARTIST \"/home/john/Music/playlists/{ALBUMARTIST}-{ALBUM}.m3u\"	Generate a playlist for every combination of ALBUM and ALBUMARTIST in the database, with the output file pattern ALBUMARTIST-ALBUM.m3u
  $0 --sql \"SELECT PATH FROM LIBRARY WHERE ARTIST='Steely Dan';\" steely_dan.m3u	Generate a playlist based on the output of this SQL statement
  $0 --sql \"ARTIST='Steely Dan';\" steely_dan.m3u					If an incomplete SQL statement is received, the \"SELECT PATH FROM {table_name} WHERE \" part of the SQL statement is assumed to be implied
";
}


# parse flags and arguments
for (my $i = 0; $i <= $#ARGV; $i++){
	if ($ARGV[$i] =~ /-i|--input/){
		$i++;
		$dbname = "$ARGV[$i]";
	}

	elsif ($ARGV[$i] =~ /-h|--help/){
		print_help();
		exit;
	}

	elsif ($ARGV[$i] =~ /-q|--quiet/){
		$options{quiet} = 1;
	}

	elsif ($ARGV[$i] =~ /--relative/){
		$options{relative} = 1;
	}

	elsif ($ARGV[$i] =~ /--sql/){
		$i++;
		$statement_arg = "$ARGV[$i]";
		$options{sql} = 1;
	}

	elsif ($ARGV[$i] =~ /-t|--table-name/){
		$i++;
		$table_name = "$ARGV[$i]";
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

# Quit if dbname does not exist
if (! -r $dbname){
	die "Error: database $dbname is not readable or does not exist"
}
# Connect to database file
my $dbh = DBI->connect("DBI:SQLite:dbname=$dbname", "", "", { RaiseError => 1}) or die $DBI::errstr;
# DEBUG
if (!$options{quiet}){
	print "Opened database successfully\n";
}

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
	if (!$options{quiet}){
		print "Opened $output_pattern\n";
	}
	build_m3u("$output_pattern", *FH, @db_output);
	close FH;
}

# Go through every entry to build multiple playlists
else {
	my %tag_hash;    # Track tag values for each file
	my @output_files; # Output files, based on output_pattern
	my @value_arr;   # Hold values after splitting by SEP to append to tag_hash

	@db_output = flatten_array(db_cmd($dbh, "SELECT count(*) FROM $table_name;"));
	my $row_count = $db_output[0];

	# Go through each row by ID
	for my $i (1..$row_count){
		# Reset @output_files
		@output_files = ();

		# Get output for the PATH, plus each tag of interest; store it in tag_hash
		$statement = join(',', @tags_of_interest);
		@db_output = flatten_array(db_cmd($dbh, "SELECT $statement FROM $table_name WHERE ID=$i;"));
		for my $j (0..scalar(@db_output)-1){
			$tag_hash{$tags_of_interest[$j]} = $db_output[$j];

			if (!($tags_of_interest[$j] eq "PATH")){
				# remove illegal filename characters, replace them with underscore
				$tag_hash{$tags_of_interest[$j]} =~ s/[\/<>:"\\|?*]/_/g;

				# Separate out arrays
				@value_arr = split(';', $tag_hash{$tags_of_interest[$j]}); 
				@tag_hash{$tags_of_interest[$j]} = ();
				push(@{$tag_hash{$tags_of_interest[$j]}}, @value_arr);
			}

		}

		# determine array of output files (consider making this a separate subroutine)
		@output_files = get_output_files(%tag_hash);

		# Loop to add to proper files:
		for my $output_file (@output_files){
			# Open the file for writing
			open FH, ">> $output_file" or die $!;
			# DEBUG
			if (!$options{quiet}){
				print "Opened $output_file\n";
			}
			build_m3u("$output_file", *FH, $tag_hash{PATH});
			close FH;
		}

	}
}

# Disconnect from sqlite database
$dbh->disconnect();
