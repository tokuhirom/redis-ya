use strict;
use warnings;
use Benchmark ':all';
use Redis;
use Redis::Fast;

my $r = Redis->new(server => '127.0.0.1:6379');
my $f = Redis::Fast->new(server => '127.0.0.1:6379');
cmpthese(
    10000 => {
        'Redis' => sub {
            $r->set("HEY", "YO");
            $r->get("HEY");
        },
        'Redis::Fast' => sub {
            $f->set("HEY", "YO");
            $f->get("HEY");
        },
    }
);
