package App::BorgRestore::Helper;
use v5.10;
use strict;
use warnings;

use Function::Parameters;
use POSIX ();

fun untaint($data, $regex) {
	$data =~ m/^($regex)$/ or die "Failed to untaint: $data";
	return $1;
}

fun untaint_archive_name($archive) {
	return untaint($archive, qr([a-zA-Z0-9-:+\.]+));
}

fun format_timestamp($timestamp) {
	return POSIX::strftime "%a. %F %H:%M:%S %z", localtime $timestamp;
}

1;

__END__
