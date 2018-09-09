package App::BorgRestore::PathTimeTable::DB;
use strictures 2;

use Function::Parameters;
use Log::Any qw($log);

=head1 NAME

App::BorgRestore::PathTimeTable::DB - Directly write new archive data to the database

=head1 DESCRIPTION

This is used by L<App::BorgRestore> to add new archive data into the database.
Data is written to the database directly and existing data is updated where necessary.

For performance reasons this class keeps an internal cache so that the database
is only contacted when necessary. Depending on the distribution of modification
times of files and directories, the effectiveness of this cache can vary. The
cache also assumes that the path are sorted so that all files from one
directory are added, before files from another. If a path from a different
directory is added, the previous cache is invalidated.

=cut

method new($class: $deps = {}) {
	return $class->new_no_defaults($deps);
}

method new_no_defaults($class: $deps = {}) {
	my $self = {};
	bless $self, $class;
	$self->{deps} = $deps;
	$self->{cache} = {};
	$self->{current_path_in_cache} = "";
	$self->{stats} = {};
	return $self;
}

method set_archive_id($archive_id) {
	$self->{archive_id} = $archive_id;
}

method add_path($path, $time) {
	$self->{stats}->{total_paths}++;
	my $old_cache_path = $self->{current_path_in_cache};
	while ($old_cache_path =~ m#/#) {
		unless ($path =~ m#^\Q$old_cache_path\E/#) {
			delete $self->{cache}->{$old_cache_path};
		}
		$old_cache_path =~ s|/[^/]*$||;
	}

	my $full_path = $path;
	while ($path =~ m#/#) {
		$self->_add_path_to_db($self->{archive_id}, $path, $time);
		my $cached = $self->{cache}->{$path};
		if ($path ne $full_path && (!defined $cached || $cached < $time)) {
			# logging statements are commented since they incur a performance
			# overhead because they are called very often. Uncomment when necessary
			#$log->tracef("Setting cache time for path '%s' to %d", $path, $time);
			$self->{cache}->{$path} = $time;
		}
		$path =~ s|/[^/]*$||;
	}
	$self->_add_path_to_db($self->{archive_id}, $path, $time) unless $path eq ".";
	my $cached = $self->{cache}->{$path};
	if ($path ne $full_path && (!defined $cached || $cached < $time)) {
		#$log->tracef("Setting cache time for path '%s' to %d", $path, $time);
		$self->{cache}->{$path} = $time;
	}
	$self->{current_path_in_cache} = $full_path;
}

method _add_path_to_db($archive_id, $path,$time) {
	my $cached = $self->{cache}->{$path};
	$self->{stats}->{total_potential_calls_to_db_class}++;
	if (!defined $cached || $cached < $time) {
		#$log->tracef("Updating DB for path '%s' with time %d", $path, $time);
		$self->{stats}->{real_calls_to_db_class}++;
		$self->{deps}->{db}->update_path_if_greater($archive_id, $path, $time);
	} else {
		#$log->tracef("Skipping DB update for path '%s' because (cached) DB time is %d and file time is %d which is lower", $path, $cached, $time);
	}
}


method save_nodes() {
	for my $key (keys %{$self->{stats}}) {
		$log->debugf("Performance counter %s = %s", $key, $self->{stats}->{$key});
	}
	# do nothing because we already write everything to the DB directly
}

1;

__END__
