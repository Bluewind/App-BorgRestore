requires 'perl', '5.010000';

on 'test' => sub {
    requires 'Test::More', '0.98';
	requires 'Test::MockObject';
	requires 'Test::Exception';
	requires 'Test::Differences';
};

