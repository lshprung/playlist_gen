#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use Audio::Scan;
use File::HomeDir;


# Keep track of columns that need to be created in the database
our %columns = (
	ID => '1'
);

# Variables to be set by user (TODO)
our $music_dir = File::HomeDir->my_home . "/Music/";


# Scan a directory recursively, return an array of files (optionally, matching a certain file extension or extensions TODO)
sub scan_dir {
	my @file_list;

	# Remove extra /'s from the end of $_[0]
	$_[0] =~ s/\/+$//g;
	my $dir_path = $_[0];
	my @extensions = $_[1]; #TODO

	opendir my $dh, "$dir_path" or die "$!";
	while (my $file = readdir($dh)) {
		# Skip . and .. directories
		if ($file eq "." or $file eq ".."){
			next;
		}

		if (-d "$dir_path/$file"){
			push(@file_list, scan_dir("$dir_path/$file", @extensions));
		}

		elsif (-f "$dir_path/$file" and -r "$dir_path/$file"){
			push(@file_list, "$dir_path/$file");
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

# Look through files in $music_dir
print "Looking through files in $music_dir\n";
my @file_list = scan_dir($music_dir);
for my $i (sort @file_list){
	print "$i\n";
}
