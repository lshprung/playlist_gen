# File to hold shared subroutines


# Wrapper to handle sqlite commands, return an array of returned lines from sqlite output
# 	@_[0]            -> database handle
# 	@_[1]            -> command/statement
# 	@_[2] (optional) -> output statement
sub db_cmd {
	if ($options{debug}){
		print "Preparing SQL query \"$_[1]\"\n"
	}

	my $sth = $_[0]->prepare($_[1]);

	if ($sth->execute < 0){
		die $DBI::errstr;
	}

	# DEBUG
	if (!$options{quiet} and defined $_[2]){
		print "$_[2]\n";
	}

	# Build output array
	return($sth->fetchall_arrayref);
}

1;

# Handle digging into non-scalar tags and other deep arrays
# 	@_[0] -> array tag/deep array
sub flatten_array {
	my @output;

	for my $i (@_){
		# If another array, recursively handle
		if (ref($i) eq 'ARRAY'){
			push(@output, flatten_array(@$i));
		}

		# If scalar, append to output normally
		elsif (!ref($i)){
			push(@output, "$i");
		}
	}

	return @output;
}

