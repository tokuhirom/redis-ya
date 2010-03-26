use strict;
use warnings;
use Test::More;
use Redis::YA;

my $data = "YO\x00HO\x015\x012HAH,DO!"x(1024*1024);
my $redis = Redis::YA->new(timeout => 1);
$redis->del("HEY");
is $redis->set("HEY", $data), "OK", "send large packet";
is $redis->get("HEY"), $data, "get large packet";

done_testing;
