package App::BorgRestore;
use v5.10;
use strict;
use warnings;

our $VERSION = "2.0.0";

use App::BorgRestore::Borg;
use App::BorgRestore::DB;
use App::BorgRestore::Helper;
use App::BorgRestore::Settings;

use autodie;
use Cwd qw(abs_path getcwd);
use File::Basename;
use File::Slurp;
use File::Spec;
use File::Temp;
use Getopt::Long;
use List::Util qw(any all);
use Pod::Usage;
use POSIX ();
use Time::HiRes;

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
	my $deps = shift;

	my $self = {};
	bless $self, $class;

	my $db_path = App::BorgRestore::Settings::get_cache_path('archives.db');
	# TODO: make db_path configurable, probably settings too

	$self->{opts} = $opts;
	$self->{borg} = $deps->{borg} // App::BorgRestore::Borg->new();
	$self->{db} = $deps->{db} // App::BorgRestore::DB->new($db_path);

	return $self;
}

sub new_no_defaults {
	my $class = shift;
	my $opts = shift;
	my $deps = shift;

	my $self = {};
	bless $self, $class;

	$self->{opts} = $opts;
	$self->{borg} = $deps->{borg};
	$self->{db} = $deps->{db};

	return $self;
}

sub debug {
	my $self = shift;
	say STDERR @_ if $self->{opts}->{debug};
}

sub find_archives {
	my $self = shift;
	my $path = shift;

	my %seen_modtime;
	my @ret;

	$self->debug("Building unique archive list");

	my $archives = $self->{db}->get_archives_for_path($path);

	for my $archive (@$archives) {
		my $modtime = $archive->{modification_time};

		if (defined($modtime) && (!$seen_modtime{$modtime}++)) {
			push @ret, $archive;
		}
	}

	if (!@ret) {
		printf "\e[0;91mWarning:\e[0m Path '%s' not found in any archive.\n", $path;
	}

	@ret = sort { $a->{modification_time} <=> $b->{modification_time} } @ret;

	return \@ret;
}

sub select_archive_timespec {
	my $self = shift;
	my $archives = shift;
	my $timespec = shift;

	my $seconds = $self->timespec_to_seconds($timespec);
	if (!defined($seconds)) {
		say STDERR "Error: Invalid time specification";
		return;
	}

	my $target_timestamp = time - $seconds;

	$self->debug("Searching for newest archive that contains a copy before ", $self->format_timestamp($target_timestamp));

	for my $archive (reverse @$archives) {
		if ($archive->{modification_time} < $target_timestamp) {
			return $archive;
		}
	}

	return;
}

sub format_timestamp {
	my $self = shift;
	my $timestamp = shift;

	return POSIX::strftime "%a. %F %H:%M:%S %z", localtime $timestamp;
}

sub timespec_to_seconds {
	my $self = shift;
	my $timespec = shift;

	if ($timespec =~ m/^(?>(?<value>[0-9.]+))(?>(?<unit>[a-z]+))$/) {
		my $value = $+{value};
		my $unit = $+{unit};

		my %factors = (
			s       => 1,
			second  => 1,
			seconds => 1,
			minute  => 60,
			minutes => 60,
			h       => 60*60,
			hour    => 60*60,
			hours   => 60*60,
			d       => 60*60*24,
			day     => 60*60*24,
			days    => 60*60*24,
			m       => 60*60*24*31,
			month   => 60*60*24*31,
			months  => 60*60*24*31,
			y       => 60*60*24*365,
			year    => 60*60*24*365,
			years   => 60*60*24*365,
		);

		if (exists($factors{$unit})) {
			return $value * $factors{$unit};
		}
	}

	return;
}

sub restore {
	my $self = shift;
	my $path = shift;
	my $archive = shift;
	my $destination = shift;

	$destination = App::BorgRestore::Helper::untaint($destination, qr(.*));
	$path = App::BorgRestore::Helper::untaint($path, qr(.*));
	my $archive_name = App::BorgRestore::Helper::untaint_archive_name($archive->{archive});

	printf "Restoring %s to %s from archive %s\n", $path, $destination, $archive->{archive};

	my $basename = basename($path);
	my $components_to_strip =()= $path =~ /\//g;

	$self->debug(sprintf("CWD is %s", getcwd()));
	$self->debug(sprintf("Changing CWD to %s", $destination));
	mkdir($destination) unless -d $destination;
	chdir($destination) or die "Failed to chdir: $!";

	my $final_destination = abs_path($basename);
	$final_destination = App::BorgRestore::Helper::untaint($final_destination, qr(.*));
	$self->debug("Removing ".$final_destination);
	File::Path::remove_tree($final_destination);
	$self->{borg}->restore($components_to_strip, $archive_name, $path);
}

sub get_temp_path {
	my $self = shift;
	my $item = shift;

	state $tempdir_obj = File::Temp->newdir();

	my $tempdir = $tempdir_obj->dirname;

	return $tempdir."/".$item;
}

sub add_path_to_hash {
	my $self = shift;
	my $hash = shift;
	my $path = shift;
	my $time = shift;

	my @components = split /\//, $path;

	my $node = $hash;

	if ($path eq ".") {
		if ($time > $$node[1]) {
			$$node[1] = $time;
		}
		return;
	}

	# each node is an arrayref of the format [$hashref_of_children, $mtime]
	# $hashref_of_children is undef if there are no children
	for my $component (@components) {
		if (!defined($$node[0]->{$component})) {
			$$node[0]->{$component} = [undef, $time];
		}
		# update mtime per child
		if ($time > $$node[1]) {
			$$node[1] = $time;
		}
		$node = $$node[0]->{$component};
	}
}

sub get_missing_items {
	my $self = shift;
	my $have = shift;
	my $want = shift;

	my $ret = [];

	for my $item (@$want) {
		my $exists = any { $_ eq $item } @$have;
		push @$ret, $item if not $exists;
	}

	return $ret;
}

sub handle_removed_archives {
	my $self = shift;
	my $borg_archives = shift;

	my $start = Time::HiRes::gettimeofday();

	my $existing_archives = $self->{db}->get_archive_names();

	# TODO this name is slightly confusing, but it works as expected and
	# returns elements that are in the previous list, but missing in the new
	# one
	my $remove_archives = $self->get_missing_items($borg_archives, $existing_archives);

	if (@$remove_archives) {
		for my $archive (@$remove_archives) {
			$self->debug(sprintf("Removing archive %s", $archive));
			$self->{db}->begin_work;
			$self->{db}->remove_archive($archive);
			$self->{db}->commit;
			$self->{db}->vacuum;
		}

		my $end = Time::HiRes::gettimeofday();
		$self->debug(sprintf("Removing archives finished after: %.5fs", $end - $start));
	}
}

sub handle_added_archives {
	my $self = shift;
	my $borg_archives = shift;

	my $archives = $self->{db}->get_archive_names();
	my $add_archives = $self->get_missing_items($archives, $borg_archives);

	for my $archive (@$add_archives) {
		my $start = Time::HiRes::gettimeofday();
		my $lookuptable = [{}, 0];

		$self->debug(sprintf("Adding archive %s", $archive));

		$self->{borg}->list_archive($archive, sub {
			my $line = shift;
			# roll our own parsing of timestamps for speed since we will be parsing
			# a huge number of lines here
			# example timestamp: "Wed, 2016-01-27 10:31:59"
			if ($line =~ m/^.{4} (?<year>....)-(?<month>..)-(?<day>..) (?<hour>..):(?<minute>..):(?<second>..) (?<path>.+)$/) {
				my $time = POSIX::mktime($+{second},$+{minute},$+{hour},$+{day},$+{month}-1,$+{year}-1900);
				#$self->debug(sprintf("Adding path %s with time %s", $+{path}, $time));
				$self->add_path_to_hash($lookuptable, $+{path}, $time);
			}
		});

		$self->debug(sprintf("Finished parsing borg output after %.5fs. Adding to db", Time::HiRes::gettimeofday - $start));

		$self->{db}->begin_work;
		$self->{db}->add_archive_name($archive);
		my $archive_id = $self->{db}->get_archive_id($archive);
		$self->save_node($archive_id,  undef, $lookuptable);
		$self->{db}->commit;
		$self->{db}->vacuum;

		my $end = Time::HiRes::gettimeofday();
		$self->debug(sprintf("Adding archive finished after: %.5fs", $end - $start));
	}
}

sub build_archive_cache {
	my $self = shift;
	my $borg_archives = $self->{borg}->borg_list();
	my $db_path = $self->get_cache_path('archives.db');

	my $archives = $self->{db}->get_archive_names();

	$self->debug(sprintf("Found %d archives in db", scalar(@$archives)));

	$self->handle_removed_archives($self->{db}, $borg_archives);
	$self->handle_added_archives($self->{db}, $borg_archives);

	if ($self->{opts}->{debug}) {
		$self->debug(sprintf("DB contains information for %d archives in %d rows", scalar(@{$self->{db}->get_archive_names()}), $self->{db}->get_archive_row_count()));
	}
}

sub save_node {
	my $self = shift;
	my $archive_id = shift;
	my $prefix = shift;
	my $node = shift;

	for my $child (keys %{$$node[0]}) {
		my $path;
		$path = $prefix."/" if defined($prefix);
		$path .= $child;

		my $time = $$node[0]->{$child}[1];
		$self->{db}->add_path($archive_id, $path, $time);

		$self->save_node($archive_id, $path, $$node[0]->{$child});
	}
}

sub get_mtime_from_lookuptable {
	my $self = shift;
	my $lookuptable = shift;
	my $path = shift;

	my @components = split /\//, $path;
	my $node = $lookuptable;

	for my $component (@components) {
		$node = $$node[0]->{$component};
		if (!defined($node)) {
			return;
		}
	}
	return $$node[1];
}

sub update_cache {
	my $self = shift;
	$self->debug("Checking if cache is complete");
	$self->build_archive_cache();
	$self->debug("Cache complete");
}


1;
__END__
