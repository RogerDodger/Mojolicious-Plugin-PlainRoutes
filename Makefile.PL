use inc::Module::Install;

name     'Mojolicious-Plugin-PlainRoutes';
all_from 'lib/Mojolicious/Plugin/PlainRoutes.pm';
author   q{Cameron Thornton <cthor@cpan.org>};
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

