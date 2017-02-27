package App::BorgRestore;
use v5.10;
use strict;
use warnings;

our $VERSION = "2.0.0";

=pod
=encoding utf-8

=head1 NAME

App::BorgRestore - Restore paths from borg backups

=head1 SYNOPSIS

    use App::BorgRestore;

=head1 DESCRIPTION

App::BorgRestore is ...

=head1 LICENSE

Copyright (C) 2016-2017  Florian Pritz E<lt>bluewind@xinu.atE<gt>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

See gpl-3.0.txt for the full license text.

=head1 AUTHOR

Florian Pritz E<lt>bluewind@xinu.atE<gt>

=cut

sub new {
	my $class = shift;
	my $opts = shift;

	my $self = {};
	bless $self, $class;

	$self->{opts} = $opts;

	return $self;
}

sub debug {
	my $self = shift;
	say STDERR @_ if $self->{opts}->{debug};
}


1;
__END__
