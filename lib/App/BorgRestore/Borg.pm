package App::BorgRestore::Borg;
use v5.10;
use warnings;
use strict;

use IPC::Run qw(run start);

sub new {
	my $class = shift;

	my $self = {};
	bless $self, $class;

	return $self;
}

sub borg_list {
	my $self = shift;
	my @archives;

	run [qw(borg list)], '>', \my $output or die "borg list returned $?";

	for (split/^/, $output) {
		if (m/^([^\s]+)\s/) {
			push @archives, $1;
		}
	}

	return \@archives;
}

sub restore {
	my $self = shift;
	my $components_to_strip = shift;
	my $archive_name = shift;
	my $path = shift;

	system(qw(borg extract -v --strip-components), $components_to_strip, "::".$archive_name, $path);
}

sub list_archive {
	my $self = shift;
	my $archive = shift;
	my $fh = shift;

	return start [qw(borg list --list-format), '{isomtime} {path}{NEWLINE}', "::".$archive], ">pipe", $fh;
}

1;

__END__
