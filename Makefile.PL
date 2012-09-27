use strict;
use warnings;
use inc::Module::Install;

name 'IO-ReStoreFH';
author 'Diab Jerius';
license 'gpl3';
all_from 'lib/IO/ReStoreFH.pm';

author_tests( 'xt' );

test_requires 'Test::More';
test_requires 'Test::File::Contents', 0.20;
test_requires 'Test::Exception';

author_requires 'Test::NoBreakpoints';
auto_install;

requires 'Try::Tiny';

WriteAll;
