use strict;
use warnings;

use Test::More;
use Test::MockObject;
use Test::Differences;

use App::BorgRestore;

# Only log calls to $db->add_path
my $db = Test::MockObject->new();
$db->set_true(qw(add_path -begin_work -commit -vacuum -add_archive_name));
$db->mock('-get_archive_id', sub {return 'prefix-archive-1' if $_[1] eq 'archive-1';});
$db->mock('-get_archive_names', sub {return []});

my $borg = Test::MockObject->new();
$borg->set_list('borg_list', ['archive-1']);
$borg->mock('list_archive', sub {
		my ($self, $archive, $cb) = @_;
		$cb->("XXX, 1970-01-01 01:00:05 .");
		$cb->("XXX, 1970-01-01 01:00:10 boot");
		$cb->("XXX, 1970-01-01 01:00:20 boot/grub");
		$cb->("XXX, 1970-01-01 01:00:08 boot/grub/grub.cfg");
		$cb->("XXX, 1970-01-01 01:00:13 boot/foo");
		$cb->("XXX, 1970-01-01 01:00:13 boot/foo/blub");
		$cb->("XXX, 1970-01-01 01:00:19 boot/foo/bar");
	} );

# Call the actual function we want to test
my $app = App::BorgRestore->new({borg => $borg, db => $db});
$app->_handle_added_archives(['archive-1'], $db);

# Check if $db->add_path has been called properly
my (@calls, @a);
push @calls, [@a] while @a = $db->next_call();

# sort by path
@calls = sort {$a->[1][2] cmp $b->[1][2];} @calls;

eq_or_diff(\@calls, [
		['add_path', [$db, 'prefix-archive-1', 'boot', 20]],
		['add_path', [$db, 'prefix-archive-1', 'boot/foo', 19]],
		['add_path', [$db, 'prefix-archive-1', 'boot/foo/bar', 19]],
		['add_path', [$db, 'prefix-archive-1', 'boot/foo/blub', 13]],
		['add_path', [$db, 'prefix-archive-1', 'boot/grub', 20]],
		['add_path', [$db, 'prefix-archive-1', 'boot/grub/grub.cfg', 8]],
	], "Database is populated with the correct timestamps");

done_testing;
