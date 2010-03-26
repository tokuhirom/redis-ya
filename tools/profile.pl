use strict;
use warnings;
use Redis::Fast;

my $f = Redis::Fast->new(server => '127.0.0.1:6379');
for my $i (0..100) {
    $f->set("HEY", "YO");
    $f->get("HEY");
}
