# File to hold shared variables and subroutines


# Wrapper to handle sqlite commands, return an array of returned lines from sqlite output
# 	@_[0]            -> database handle
# 	@_[1]            -> command/statement
# 	@_[2] (optional) -> output statement
sub db_cmd {
	my $sth = $_[0]->prepare($_[1]);

	if ($sth->execute < 0){
		die $DBI::errstr;
	}

	# DEBUG
	if (!$options{quiet} and defined $_[2]){
		print "$_[2]\n";
	}

	# Build output array
	return($sth->fetchrow_array);
}

1;
