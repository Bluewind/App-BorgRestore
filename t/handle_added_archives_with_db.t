use strict;
use warnings;

use Log::Any::Adapter ('TAP');
use POSIX qw(tzset);
use Test::Differences;
use Test::MockObject;
use Test::More;

use App::BorgRestore;
use App::BorgRestore::Settings;

for my $in_memory (0,1) {
	$App::BorgRestore::Settings::prepare_data_in_memory = $in_memory;

	my $db = App::BorgRestore::DB->new(":memory:", 0);

	$ENV{TZ} = 'UTC';
	tzset;

	my $borg = Test::MockObject->new();
	$borg->set_list('borg_list', ['archive-1']);
	$borg->mock('list_archive', sub {
			my ($self, $archive, $cb) = @_;
			$cb->("XXX, 1970-01-01 00:00:05 .");
			$cb->("XXX, 1970-01-01 00:00:10 boot");
			$cb->("XXX, 1970-01-01 00:00:20 boot/grub");
			$cb->("XXX, 1970-01-01 00:00:08 boot/grub/grub.cfg");
			$cb->("XXX, 1970-01-01 00:00:13 boot/foo");
			$cb->("XXX, 1970-01-01 00:00:13 boot/foo/blub");
			$cb->("XXX, 1970-01-01 00:00:19 boot/foo/bar");
		} );

	# Call the actual function we want to test
	my $app = App::BorgRestore->new({borg => $borg, db => $db});
	$app->_handle_added_archives(['archive-1']);

	# check database content
	eq_or_diff($db->get_archives_for_path('.'), [{archive => 'archive-1', modification_time => undef},]);
	eq_or_diff($db->get_archives_for_path('boot'), [{archive => 'archive-1', modification_time => 20},]);
	eq_or_diff($db->get_archives_for_path('boot/foo'), [{archive => 'archive-1', modification_time => 19},]);
	eq_or_diff($db->get_archives_for_path('boot/foo/bar'), [{archive => 'archive-1', modification_time => 19},]);
	eq_or_diff($db->get_archives_for_path('boot/foo/blub'), [{archive => 'archive-1', modification_time => 13},]);
	eq_or_diff($db->get_archives_for_path('boot/grub'), [{archive => 'archive-1', modification_time => 20},]);
	eq_or_diff($db->get_archives_for_path('boot/grub/grub.cfg'), [{archive => 'archive-1', modification_time => 8},]);
	eq_or_diff($db->get_archives_for_path('lulz'), [{archive => 'archive-1', modification_time => undef},]);
}


done_testing;
