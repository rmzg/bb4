use lib "../lib";
use lib "lib";

use Test::More;

use strict; 
use warnings;

use BB4::ConfigParser;

my $config_file = "test_config.conf";
if( ! -e $config_file ) { $config_file = "t/test_config.conf" }

ok( my $config = BB4::ConfigParser->parse_file( $config_file ), "Parsed config" );

is_deeply( $config, {
          'test' => {
                      'bar' => '95',
                      '18' => '121',
                      'foo' => '42',
                      'foo2' => '43'
                    },
          'test3' => {
                       'subvalue' => {
                                       'superfoo' => 'superbar',
                                       'subfoo' => 'subfoo'
                                     },
                       'subvalue2' => {
                                        'oaksd' => '21',
                                        'suduper' => '95'
                                      }
                     },
          'test2' => {
                       'bar' => 'flibble \' babble',
                       'baz' => ' this is also a foo',
                       'foo' => 'this is a foo'
                     }
        },
"Parsed test config properly!" );


done_testing;
