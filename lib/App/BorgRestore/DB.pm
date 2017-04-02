package App::BorgRestore::DB;
use v5.10;
use strict;
use warnings;

use App::BorgRestore::Helper;

use Data::Dumper;
use DBI;
use Log::Any qw($log);

sub new {
	my $class = shift;
	my $db_path = shift;
	my $cache_size = shift;

	my $self = {};
	bless $self, $class;

	if (! -f $db_path) {
		my $db = $self->open_db($db_path, $cache_size);
		$self->{db}->initialize_db();
	} else {
		$self->_open_db($db_path, $cache_size);
	}

	return $self;
}

sub _open_db {
	my $self = shift;
	my $dbfile = shift;
	my $cache_size = shift;

	$log->debugf("Opening database at %s", $dbfile);
	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$dbfile","","", {RaiseError => 1, Taint => 1});
	$self->{dbh}->do("PRAGMA cache_size=-".$cache_size);
	$self->{dbh}->do("PRAGMA strict=ON");
}

sub initialize_db {
	my $self = shift;

	$log->debug("Creating initial database");
	$self->{dbh}->do('create table `files` (`path` text, primary key (`path`)) without rowid;');
	$self->{dbh}->do('create table `archives` (`archive_name` text unique);');
}

sub get_archive_names {
	my $self = shift;

	my @ret;

	my $st = $self->{dbh}->prepare("select `archive_name` from `archives`;");
	$st->execute();
	while (my $result = $st->fetchrow_hashref) {
		push @ret, $result->{archive_name};
	}
	return \@ret;
}

sub get_archive_row_count {
	my $self = shift;

	my $st = $self->{dbh}->prepare("select count(*) count from `files`;");
	$st->execute();
	my $result = $st->fetchrow_hashref;
	return $result->{count};
}

sub add_archive_name {
	my $self = shift;
	my $archive = shift;

	$archive = App::BorgRestore::Helper::untaint_archive_name($archive);

	my $st = $self->{dbh}->prepare('insert into `archives` (`archive_name`) values (?);');
	$st->execute($archive);

	$self->_add_column_to_table("files", $archive);
}

sub _add_column_to_table {
	my $self = shift;
	my $table = shift;
	my $column = shift;

	my $st = $self->{dbh}->prepare('alter table `'.$table.'` add column `'._prefix_archive_id($column).'` integer;');
	$st->execute();
}

sub remove_archive {
	my $self = shift;
	my $archive = shift;

	$archive = App::BorgRestore::Helper::untaint_archive_name($archive);

	my $archive_id = $self->get_archive_id($archive);

	my @keep_archives = grep {$_ ne $archive;} @{$self->get_archive_names()};

	$self->{dbh}->do('create table `files_new` (`path` text, primary key (`path`)) without rowid;');
	for my $archive (@keep_archives) {
		$self->_add_column_to_table("files_new", $archive);
	}

	my @columns_to_copy = map {'`'._prefix_archive_id($_).'`'} @keep_archives;
	@columns_to_copy = ('`path`', @columns_to_copy);
	$self->{dbh}->do('insert into `files_new` select '.join(',', @columns_to_copy).' from files');

	$self->{dbh}->do('drop table `files`');

	$self->{dbh}->do('alter table `files_new` rename to `files`');

	my $sql = 'delete from `files` where ';
	$sql .= join(' is null and ', grep {$_ ne '`path`' } @columns_to_copy);
	$sql .= " is null";

	my $st = $self->{dbh}->prepare($sql);
	my $rows = $st->execute();

	$st = $self->{dbh}->prepare('delete from `archives` where `archive_name` = ?;');
	$st->execute($archive);
}

sub _prefix_archive_id {
	my $archive = shift;

	$archive = App::BorgRestore::Helper::untaint_archive_name($archive);

	return 'timestamp-'.$archive;
}

sub get_archive_id {
	my $self = shift;
	my $archive = shift;

	return _prefix_archive_id($archive);
}

sub get_archives_for_path {
	my $self = shift;
	my $path = shift;

	my $st = $self->{dbh}->prepare('select * from `files` where `path` = ?;');
	$st->execute(App::BorgRestore::Helper::untaint($path, qr(.*)));

	my @ret;

	my $result = $st->fetchrow_hashref;
	my $archives = $self->get_archive_names();

	for my $archive (@$archives) {
		my $archive_id = $self->get_archive_id($archive);
		my $timestamp = $result->{$archive_id};

		push @ret, {
			modification_time => $timestamp,
			archive => $archive,
		};
	}

	return \@ret;
}


sub add_path {
	my $self = shift;
	my $archive_id = shift;
	my $path = shift;
	my $time = shift;

	my $st = $self->{dbh}->prepare_cached('insert or ignore into `files` (`path`, `'.$archive_id.'`)
		values(?, ?)');
	$st->execute($path, $time);

	$st = $self->{dbh}->prepare_cached('update files set `'.$archive_id.'` = ? where `path` = ?');
	$st->execute($time, $path);
}

sub begin_work {
	my $self = shift;

	$self->{dbh}->begin_work();
}

sub commit {
	my $self = shift;

	$self->{dbh}->commit();
}

sub vacuum {
	my $self = shift;

	$self->{dbh}->do("vacuum");
}


1;

__END__
