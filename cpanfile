requires 'perl', '5.010000';
requires 'Log::Any';
requires 'Log::Log4perl';
requires 'Log::Any::Adapter::Log4perl';
requires 'Function::Parameters';

on 'test' => sub {
    requires 'Test::More', '0.98';
	requires 'Test::MockObject';
	requires 'Test::Exception';
	requires 'Test::Differences';
};

