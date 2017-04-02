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

See LICENSE for the full license text.

=cut

use v5.10;

use App::BorgRestore;
use App::BorgRestore::Borg;
use App::BorgRestore::DB;
use App::BorgRestore::Helper;
use App::BorgRestore::Settings;

use autodie;
use Cwd qw(abs_path);
use File::Basename;
use Getopt::Long;
use Log::Any qw($log);
use Log::Any::Adapter;
use Log::Log4perl;
use Log::Log4perl::Appender::Screen;
use Log::Log4perl::Appender::ScreenColoredLevels;
use Log::Log4perl::Layout::PatternLayout;
use Log::Log4perl::Level;
use Pod::Usage;

my $app;

sub user_select_archive {
	my $archives = shift;

	my $selected_archive;

	if (!@$archives) {
		return;
	}

	my $counter = 0;
	for my $archive (@$archives) {
		printf "\e[0;33m%3d: \e[1;33m%s\e[0m %s\n", $counter++, App::BorgRestore::Helper::format_timestamp($archive->{modification_time}), $archive->{archive};
	}

	printf "\e[0;34m%s: \e[0m", "Enter ID to restore (Enter to skip)";
	my $selection = <STDIN>;
	return if !defined($selection);
	chomp $selection;

	return unless ($selection =~ /^\d+$/ && defined(${$archives}[$selection]));
	return ${$archives}[$selection];
}

sub logger_setup {
	my $appender = "Screen";
	$appender = "ScreenColoredLevels" if -t STDERR; ## no critic (InputOutput::ProhibitInteractiveTest)

	my $conf = "
	log4perl.rootLogger = INFO, screenlog

	log4perl.appender.screenlog          = Log::Log4perl::Appender::$appender
	log4perl.appender.screenlog.stderr   = 1
	log4perl.appender.screenlog.layout   = Log::Log4perl::Layout::PatternLayout
	log4perl.appender.screenlog.layout.ConversionPattern = %p %m%n

	log4perl.PatternLayout.cspec.U = sub {my \@c = caller(\$_[4]); \$c[0] =~ s/::/./g; return sprintf('%s:%s', \$c[0], \$c[2]);}
	";
	Log::Log4perl::init( \$conf );
	Log::Any::Adapter->set('Log4perl');

	$SIG{__WARN__} = sub {
		local $Log::Log4perl::caller_depth =
			$Log::Log4perl::caller_depth + 1;
		 Log::Log4perl->get_logger()->warn(@_);
	};

	$SIG{__DIE__} = sub {
		# ignore eval blocks
		return if($^S);
		local $Log::Log4perl::caller_depth =
			$Log::Log4perl::caller_depth + 1;
		 Log::Log4perl->get_logger()->fatal(@_);
		 exit(2);
	};
}

sub main {
	logger_setup();

	my %opts;
	# untaint PATH because we do not expect this to be run across user boundaries
	$ENV{PATH} = App::BorgRestore::Helper::untaint($ENV{PATH}, qr(.*));

	Getopt::Long::Configure ("bundling");
	GetOptions(\%opts, "help|h", "debug", "update-cache|u", "destination|d=s", "time|t=s") or pod2usage(2);
	pod2usage(0) if $opts{help};

	if ($opts{debug}) {
		my $logger = Log::Log4perl->get_logger('');
		$logger->level($DEBUG);
		Log::Log4perl->appenders()->{"screenlog"}->layout(
			Log::Log4perl::Layout::PatternLayout->new("%d %8r [%-30U] %p %m%n"));
	}

	$app = App::BorgRestore->new();

	if ($opts{"update-cache"}) {
		$app->update_cache();
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
		die "Too many arguments";
	}

	my $abs_path = $app->resolve_relative_path($path);

	$destination = dirname($abs_path) unless defined($destination);
	my $backup_path = $app->map_path_to_backup_path($abs_path);

	$log->debug("Asked to restore $backup_path to $destination");

	my $archives = $app->find_archives($backup_path);

	my $selected_archive;
	if (defined($timespec)) {
		$selected_archive = $app->select_archive_timespec($archives, $timespec);
	} else {
		$selected_archive = user_select_archive($archives);
	}

	if (!defined($selected_archive)) {
		die "No archive selected or selection invalid";
	}

	$app->restore($backup_path, $selected_archive, $destination);

	return 0;
}

exit main();

