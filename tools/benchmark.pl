use strict;
use warnings;
use Benchmark ':all';
use Redis;
use Redis::YA;

my $r = Redis->new(server => '127.0.0.1:6379');
my $f = Redis::YA->new(server => '127.0.0.1:6379');
cmpthese(
    100000 => {
        'Redis' => sub {
            $r->set("HEY", "YO");
            $r->get("HEY");
        },
        'Redis::YA' => sub {
            $f->set("HEY", "YO");
            $f->get("HEY");
        },
    }
);
