use Test::More;

use IO::Handle;

use IO::ReStoreFH;

use Test::Exception;

use t::test;

test_wfh 'new: [ fh, mode ]', '>',
         sub { IO::ReStoreFH->new( [ $_[0], '>' ] ) };

test_wfh 'new: fh', '>',
         sub { IO::ReStoreFH->new( $_[0] ) };

test_wfh 'new: fh', '>>',
         sub { IO::ReStoreFH->new( $_[0] ) };

test_wfh 'new: fh', '+>',
         sub { IO::ReStoreFH->new( $_[0] ) };


throws_ok {

 IO::ReStoreFH->new( 3.2 );

} qr/must be opened/, 'bad fd';

throws_ok {

 IO::ReStoreFH->new( bless {} );

} qr/does not have/, 'no fileno method';

throws_ok {

 IO::ReStoreFH->new( IO::Handle->new );

} qr/is not open/, 'undefined fileno';

# try and make fcntl fail to test rest of mode setting code
{
         package MyTest;
  sub new { bless {}, shift; }
  sub fileno { return 22; }
}

throws_ok { 
            IO::ReStoreFH->new( MyTest->new );

} qr/not a GLOB/i, 'defined fileno';


done_testing;
