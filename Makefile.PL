use inc::Module::Install;
name 'Redis-YA';
all_from 'lib/Redis/YA.pm';

requires 'IO::Socket::INET' => 1.31;;


readme_markdown_from 'lib/Redis/YA.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More';
test_requires 'YAML';
recursive_author_tests('xt');
# use_test_base;
auto_include;
WriteAll;
