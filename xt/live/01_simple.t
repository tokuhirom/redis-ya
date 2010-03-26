use strict;
use warnings;
use Test::More;
use Redis::Fast;

my $redis = Redis::Fast->new(timeout => 1);
$redis->del("HEY");
$redis->set("HEY", "YO");
is $redis->get("HEY"), "YO";
ok $redis->info()->{last_save_time};
ok $redis->info()->{redis_version};
is_deeply [$redis->keys('H*')], ['HEY'], 'keys';
is $redis->rpush("fll", 1), 'OK';
$redis->rpush("fll", 4);
$redis->rpush("fll", 9);
is_deeply [$redis->lrange("fll", 0, 2)], [1,4,9];
is $redis->get("UNKNOWN_KEY"), undef;
$redis->quit();
eval { $redis->set("HEY", "YO") };
ok $@;

done_testing;
