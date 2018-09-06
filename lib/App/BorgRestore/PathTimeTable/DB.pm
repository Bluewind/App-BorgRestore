package App::BorgRestore::PathTimeTable::DB;
use strict;
use warnings;

use Function::Parameters;

=head1 NAME

App::BorgRestore::PathTimeTable::DB - Directly write new archive data to the database

=head1 DESCRIPTION

This is used by L<App::BorgRestore> to add new archive data into the database.
Data is written to the database directly and existing data is updated where necessary.

=cut

method new($class: $deps = {}) {
	return $class->new_no_defaults($deps);
}

method new_no_defaults($class: $deps = {}) {
	my $self = {};
	bless $self, $class;
	$self->{deps} = $deps;
	return $self;
}

method set_archive_id($archive_id) {
	$self->{archive_id} = $archive_id;
}

method add_path($path, $time) {
	while ($path =~ m#/#) {
		$self->{deps}->{db}->update_path_if_greater($self->{archive_id}, $path, $time);
		$path =~ s|/[^/]*$||;
	}
	$self->{deps}->{db}->update_path_if_greater($self->{archive_id}, $path, $time) unless $path eq ".";
}


method save_nodes() {
	# do nothing because we already write everything to the DB directly
}

1;

__END__
