package App::BorgRestore::Borg;
use v5.10;
use warnings;
use strict;

use IPC::Run qw(run start new_chunker);

sub new {
	my $class = shift;
	my $borg_repo = shift;

	my $self = {};
	bless $self, $class;

	$self->{borg_repo} = $borg_repo;

	return $self;
}

sub borg_list {
	my $self = shift;
	my @archives;

	run [qw(borg list), $self->{borg_repo}], '>', \my $output or die "borg list returned $?";

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

	system(qw(borg extract -v --strip-components), $components_to_strip, $self->{borg_repo}."::".$archive_name, $path);
}

sub list_archive {
	my $self = shift;
	my $archive = shift;
	my $cb = shift;

	open (my $fh, '-|', 'borg', qw/list --list-format/, '{isomtime} {path}{NEWLINE}', $self->{borg_repo}."::".$archive);
	while (<$fh>) {
		$cb->($_);
	}

	# this is slow
	#return start [qw(borg list --list-format), '{isomtime} {path}{NEWLINE}', "::".$archive], ">", new_chunker, $cb;
	#$proc->finish() or die "borg list returned $?";
}

1;

__END__
