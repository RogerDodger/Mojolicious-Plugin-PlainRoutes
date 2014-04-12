use inc::Module::Install;

name     'Mojolicious-Plugin-PlainRoutes';
all_from 'lib/Mojolicious/Plugin/PlainRoutes.pm';
author   q{Cameron Thornton <cthor@cpan.org>};
license  'perl';

requires (
	"Mojolicious" => 4.60,
);

test_requires (
	"Test::More" => 0.98,
	"Test::Deep" => 0.11,
);

auto_install;

WriteAll;

