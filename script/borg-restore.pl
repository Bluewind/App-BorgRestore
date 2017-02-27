#!/usr/bin/perl -T
use warnings;
use strict;

=head1 NAME

borg-restore.pl - Restore paths from borg backups

=head1 SYNOPSIS

borg-restore.pl [options] <path>

 Options:
  --help, -h                 short help message
  --debug                    show debug messages
  --update-cache, -u         update cache files
  --destination, -d <path>   Restore backup to directory <path>
  --time, -t <timespec>      Automatically find newest backup that is at least
                             <time spec> old

 Time spec:
  Select the newest backup that is at least <time spec> old.
  Format: <number><unit>
  Units: s (seconds), min (minutes), h (hours), d (days), m (months = 31 days), y (year)

=head1 DESCRIPTION

borg-restore.pl helps to restore files from borg backups.

It takes one path, looks for its backups, shows a list of distinct versions and
allows to select one to be restored. Versions are based on the modification
time of the file.

It is also possible to specify a time for automatic selection of the backup
that has to be restored. If a time is specified, the script will automatically
select the newest backup that is at least as old as the time value that is
passed and restore it without further user interaction.

B<borg-restore.pl --update-cache> has to be executed regularly, ideally after
creating or removing backups.

=cut

=head1 OPTIONS

=over 4

=item B<--help>, B<-h>

Show help message.

=item B<--debug>

Enable debug messages.

=item B<--update-cache>, B<-u>

Update the lookup database. You should run this after creating or removing a backup.

=item B<--destination=>I<path>, B<-d >I<path>

Restore the backup to 'path' instead of its original location. The destination
either has to be a directory or missing in which case it will be created. The
backup will then be restored into the directory with its original file or
directory name.

=item B<--time=>I<timespec>, B<-t >I<timespec>

Automatically find the newest backup that is at least as old as I<timespec>
specifies. I<timespec> is a string of the form "<I<number>><I<unit>>" with I<unit> being one of the following:
s (seconds), min (minutes), h (hours), d (days), m (months = 31 days), y (year). Example: 5.5d

=back

=head1 CONFIGURATION

borg-restore.pl searches for configuration files in the following locations in
order. The first file found will be used, any later ones are ignored. If no
files are found, defaults are used.

=over

=item * $XDG_CONFIG_HOME/borg-restore.cfg

=item * /etc/borg-restore.cfg

=back

=head2 Configuration Options

You can set the following options in the config file.

Note that the configuration file is parsed as a perl script. Thus you can also
use any features available in perl itself.

=over

=item C<$borg_repo>

This specifies the URL to the borg repo as used in other borg commands. If you
use the $BORG_REPO environment variable leave this empty.

=item C<$cache_path_base>

This defaults to "C<$XDG_CACHE_HOME>/borg-restore.pl". It contains the lookup database.

=item C<@backup_prefixes>

This is an array of prefixes that need to be added when looking up a file in the
backup archives. If you use filesystem snapshots and the snapshot for /home is
located at /mnt/snapshots/home, you have to add the following:

# In the backup archives, /home has the path /mnt/snapshots/home
{regex => "^/home/", replacement => "mnt/snapshots/home/"},

The regex must always include the leading slash and it is suggested to include
a tailing slash as well to prevent clashes with directories that start with the
same string. The first regex that matches for a given file is used. This
setting only affects lookups, it does not affect the creation of the database
with --update-database.

=back

=head2 Example Configuration

 $borg_repo = "/path/to/repo";
 $cache_path_base = "/mnt/somewhere/borg-restore.pl-cache";
 @backup_prefixes = (
 	{regex => "^/home/", replacement => "mnt/snapshots/home/"},
 	# /boot is not snapshotted
 	{regex => "^/boot", replacement => ""},
 	{regex => "^/", replacement => "mnt/snapshots/root/"},
 );

=head1 LICENSE

Copyright (C) 2016-2017  Florian Pritz <bluewind@xinu.at>

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

=cut

use v5.10;

use App::BorgRestore;
use App::BorgRestore::Borg;
use App::BorgRestore::DB;
use App::BorgRestore::Helper;
use App::BorgRestore::Settings;

use autodie;
use Cwd qw(abs_path getcwd);
use Data::Dumper;
use DateTime;
use File::Basename;
use File::Path qw(mkpath);
use File::Slurp;
use File::Spec;
use File::Temp;
use Getopt::Long;
use List::Util qw(any all);
use Pod::Usage;
use Time::HiRes;

my %opts;
my %db;
my $app;

sub debug {
	$app->debug(@_);
}

sub find_archives {
	my $path = shift;

	my $db_path = get_cache_path('archives.db');

	my $db = open_db($db_path);

	my %seen_modtime;
	my @ret;

	debug("Building unique archive list");

	my $archives = $db->get_archives_for_path($path);

	for my $archive (@$archives) {
		my $modtime = $archive->{modification_time};

		if (defined($modtime) && (!$seen_modtime{$modtime}++)) {
			push @ret, $archive;
		}
	}

	if (!@ret) {
		printf "\e[0;91mWarning:\e[0m Path '%s' not found in any archive.\n", $path;
	}

	@ret = sort { $a->{modification_time} cmp $b->{modification_time} } @ret;

	return \@ret;
}

sub user_select_archive {
	my $archives = shift;

	my $selected_archive;

	my $counter = 0;

	if (!@$archives) {
		return;
	}

	for my $archive (@$archives) {
		printf "\e[0;33m%3d: \e[1;33m%s\e[0m %s\n", $counter++, format_timestamp($archive->{modification_time}), $archive->{archive};
	}

	printf "\e[0;34m%s: \e[0m", "Enter ID to restore (Enter to skip)";
	my $selection = <STDIN>;
	return if !defined($selection);
	chomp $selection;

	return unless ($selection =~ /^\d+$/ && defined(${$archives}[$selection]));
	return ${$archives}[$selection];
}

sub select_archive_timespec {
	my $archives = shift;
	my $timespec = shift;

	my $seconds = timespec_to_seconds($timespec);
	if (!defined($seconds)) {
		say STDERR "Error: Invalid time specification";
		return;
	}

	my $target_timestamp = time - $seconds;

	debug("Searching for newest archive that contains a copy before ", format_timestamp($target_timestamp));

	for my $archive (reverse @$archives) {
		if ($archive->{modification_time} < $target_timestamp) {
			return $archive;
		}
	}

	return;
}

sub format_timestamp {
	my $timestamp = shift;

	state $timezone = DateTime::TimeZone->new( name => 'local' );
	my $dt = DateTime->from_epoch(epoch => $timestamp, time_zone => $timezone);
	return $dt->strftime("%a. %F %H:%M:%S %z");
}

sub timespec_to_seconds {
	my $timespec = shift;

	if ($timespec =~ m/^(?<value>[0-9.]+)(?<unit>.+)$/) {
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
	my $path = shift;
	my $archive = shift;
	my $destination = shift;

	$destination = App::BorgRestore::Helper::untaint($destination, qr(.*));
	$path = App::BorgRestore::Helper::untaint($path, qr(.*));
	my $archive_name = App::BorgRestore::Helper::untaint_archive_name($archive->{archive});

	printf "Restoring %s to %s from archive %s\n", $path, $destination, $archive->{archive};

	my $basename = basename($path);
	my $components_to_strip =()= $path =~ /\//g;

	debug(sprintf("CWD is %s", getcwd()));
	debug(sprintf("Changing CWD to %s", $destination));
	mkdir($destination) unless -d $destination;
	chdir($destination) or die "Failed to chdir: $!";

	my $final_destination = abs_path($basename);
	$final_destination = App::BorgRestore::Helper::untaint($final_destination, qr(.*));
	debug("Removing ".$final_destination);
	File::Path::remove_tree($final_destination);
	App::BorgRestore::Borg::restore($components_to_strip, $archive_name, $path);
}

sub get_cache_dir {
	return "$App::BorgRestore::Settings::cache_path_base/v2";
}

sub get_cache_path {
	my $item = shift;
	return get_cache_dir()."/$item";
}

sub get_temp_path {
	my $item = shift;

	state $tempdir_obj = File::Temp->newdir();

	my $tempdir = $tempdir_obj->dirname;

	return $tempdir."/".$item;
}

sub add_path_to_hash {
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
	my $db = shift;
	my $borg_archives = shift;

	my $start = Time::HiRes::gettimeofday();

	my $existing_archives = $db->get_archive_names();

	# TODO this name is slightly confusing, but it works as expected and
	# returns elements that are in the previous list, but missing in the new
	# one
	my $remove_archives = get_missing_items($borg_archives, $existing_archives);

	if (@$remove_archives) {
		for my $archive (@$remove_archives) {
			debug(sprintf("Removing archive %s", $archive));
			$db->begin_work;
			$db->remove_archive($archive);
			$db->commit;
			$db->vacuum;
		}

		my $end = Time::HiRes::gettimeofday();
		debug(sprintf("Removing archives finished after: %.5fs", $end - $start));
	}
}

sub handle_added_archives {
	my $db = shift;
	my $borg_archives = shift;

	my $archives = $db->get_archive_names();
	my $add_archives = get_missing_items($archives, $borg_archives);

	for my $archive (@$add_archives) {
		my $start = Time::HiRes::gettimeofday();
		my $lookuptable = [{}, 0];

		debug(sprintf("Adding archive %s", $archive));

		my $proc = App::BorgRestore::Borg::list_archive($archive, \*OUT);
		while (<OUT>) {
			# roll our own parsing of timestamps for speed since we will be parsing
			# a huge number of lines here
			# example timestamp: "Wed, 2016-01-27 10:31:59"
			if (m/^.{4} (?<year>....)-(?<month>..)-(?<day>..) (?<hour>..):(?<minute>..):(?<second>..) (?<path>.+)$/) {
				my $time = POSIX::mktime($+{second},$+{minute},$+{hour},$+{day},$+{month}-1,$+{year}-1900);
				#debug(sprintf("Adding path %s with time %s", $+{path}, $time));
				add_path_to_hash($lookuptable, $+{path}, $time);
			}
		}
		$proc->finish() or die "borg list returned $?";

		debug(sprintf("Finished parsing borg output after %.5fs. Adding to db", Time::HiRes::gettimeofday - $start));

		$db->begin_work;
		$db->add_archive_name($archive);
		my $archive_id = $db->get_archive_id($archive);
		save_node($db, $archive_id,  undef, $lookuptable);
		$db->commit;
		$db->vacuum;

		my $end = Time::HiRes::gettimeofday();
		debug(sprintf("Adding archive finished after: %.5fs", $end - $start));
	}
}

sub build_archive_cache {
	my $borg_archives = App::BorgRestore::Borg::borg_list();
	my $db_path = get_cache_path('archives.db');

	# ensure the cache directory exists
	mkpath(get_cache_dir(), {mode => oct(700)});

	if (! -f $db_path) {
		debug("Creating initial database");
		my $db = open_db($db_path);
		$db->initialize_db();
	}

	my $db = open_db($db_path);

	my $archives = $db->get_archive_names();

	debug(sprintf("Found %d archives in db", scalar(@$archives)));

	handle_removed_archives($db, $borg_archives);
	handle_added_archives($db, $borg_archives);

	if ($opts{debug}) {
		debug(sprintf("DB contains information for %d archives in %d rows", scalar(@{$db->get_archive_names()}), $db->get_archive_row_count()));
	}
}

sub open_db {
	my $db_path = shift;

	return App::BorgRestore::DB->new($db_path);
}

sub save_node {
	my $db = shift;
	my $archive_id = shift;
	my $prefix = shift;
	my $node = shift;

	for my $child (keys %{$$node[0]}) {
		my $path;
		$path = $prefix."/" if defined($prefix);
		$path .= $child;

		my $time = $$node[0]->{$child}[1];
		$db->add_path($archive_id, $path, $time);

		save_node($db, $archive_id, $path, $$node[0]->{$child});
	}
}

sub get_mtime_from_lookuptable {
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
	debug("Checking if cache is complete");
	build_archive_cache();
	debug("Cache complete");
}

sub main {
	# untaint PATH because we only expect this to run as root
	$ENV{PATH} = App::BorgRestore::Helper::untaint($ENV{PATH}, qr(.*));

	$ENV{BORG_REPO} = $App::BorgRestore::Settings::borg_repo unless $App::BorgRestore::Settings::borg_repo eq "";

	Getopt::Long::Configure ("bundling");
	GetOptions(\%opts, "help|h", "debug", "update-cache|u", "destination|d=s", "time|t=s") or pod2usage(2);
	pod2usage(0) if $opts{help};

	$app = App::BorgRestore->new(\%opts);

	if ($opts{"update-cache"}) {
		update_cache();
		return 0;
	}

	pod2usage(-verbose => 0) if (@ARGV== 0);

	my @paths = @ARGV;

	my $path;
	my $timespec;
	my $destination;

	$path = $ARGV[0];

	if (defined($opts{destination})) {
		$destination = $opts{destination};
	}

	if (defined($opts{time})) {
		$timespec = $opts{time};
	}

	if (@ARGV > 1) {
		say STDERR "Error: Too many arguments";
		exit(1);
	}

	my $canon_path = File::Spec->canonpath($path);
	my $abs_path = abs_path($canon_path);
	if (!defined($abs_path)) {
		say STDERR "Error: Failed to resolve path to absolute path: $canon_path: $!";
		say STDERR "Make sure that all parts of the path, except the last one, exist.";
		exit(1);
	}

	if (!defined($destination)) {
		$destination = dirname($abs_path);
	}
	my $backup_path = $abs_path;
	for my $backup_prefix (@App::BorgRestore::Settings::backup_prefixes) {
		if ($backup_path =~ m/$backup_prefix->{regex}/) {
			$backup_path =~ s/$backup_prefix->{regex}/$backup_prefix->{replacement}/;
			last;
		}
	}

	debug("Asked to restore $backup_path to $destination");

	my $archives = find_archives($backup_path);

	my $selected_archive;

	if (defined($timespec)) {
		$selected_archive = select_archive_timespec($archives, $timespec);
	} else {
		$selected_archive = user_select_archive($archives);
	}

	if (!defined($selected_archive)) {
		say STDERR "Error: No archive selected or selection invalid";
		return 1;
	}

	restore($backup_path, $selected_archive, $destination);

	return 0;
}

exit main();

