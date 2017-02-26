package App::BorgRestore::Helper;
use v5.10;
use strict;
use warnings;


sub untaint {
	my $data = shift;
	my $regex = shift;

	$data =~ m/^($regex)$/ or die "Failed to untaint: $data";
	return $1;
}

sub untaint_archive_name {
	my $archive = shift;
	return untaint($archive, qr([a-zA-Z0-9-:+]+));
}

1;

__END__
