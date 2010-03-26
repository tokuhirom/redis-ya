use strict;
use warnings;
use Test::More;
use Redis::YA;

my $redis = Redis::YA->new(timeout => 1);
$redis->del("HEY");
$redis->set("HEY", "YO\x00HO\x015\x012HAH,DO!");
is $redis->get("HEY"), "YO\x00HO\x015\x012HAH,DO!";

done_testing;
