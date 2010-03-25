use inc::Module::Install;
name 'Redis-Fast';
all_from 'lib/Redis/Fast.pm';

# requires '';


readme_markdown_from 'lib/Redis/Fast.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More';
test_requires 'YAML';
author_tests('xt');
# use_test_base;
auto_include;
WriteAll;
