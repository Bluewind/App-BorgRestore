use strict;
use warnings;

use Test::More;
use Test::Exception;

use App::BorgRestore::Helper;

ok(App::BorgRestore::Helper::untaint_archive_name('abc-1234:5+1') eq 'abc-1234:5+1');
ok(App::BorgRestore::Helper::untaint_archive_name('abc') eq 'abc');

dies_ok(sub{App::BorgRestore::Helper::untaint_archive_name('abc`"\'')}, 'special chars not allowed');
dies_ok(sub{App::BorgRestore::Helper::untaint_archive_name('abc`')}, 'special chars not allowed');
dies_ok(sub{App::BorgRestore::Helper::untaint_archive_name('abc"')}, 'special chars not allowed');
dies_ok(sub{App::BorgRestore::Helper::untaint_archive_name('abc\'')}, 'special chars not allowed');


done_testing;
