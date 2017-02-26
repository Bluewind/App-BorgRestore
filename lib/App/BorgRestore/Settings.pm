package App::BorgRestore::Settings;
use v5.10;
use strict;
use warnings;

use App::BorgRestore::Helper;

our $borg_repo = "";
our $cache_path_base = sprintf("%s/borg-restore.pl", $ENV{XDG_CACHE_HOME} // $ENV{HOME}."/.cache");
our @backup_prefixes = (
	{regex => "^/", replacement => ""},
);

my @configfiles = (
	sprintf("%s/borg-restore.cfg", $ENV{XDG_CONFIG_HOME} // $ENV{HOME}."/.config"),
	"/etc/borg-restore.cfg",
);

for my $configfile (@configfiles) {
	$configfile = App::BorgRestore::Helper::untaint($configfile, qr/.*/);
	if (-e $configfile) {
		unless (my $return = do $configfile) {
			die "couldn't parse $configfile: $@" if $@;
			die "couldn't do $configfile: $!"    unless defined $return;
			die "couldn't run $configfile"       unless $return;
		}
	}
}
$cache_path_base = App::BorgRestore::Helper::untaint($cache_path_base, qr/.*/);

1;

__END__
