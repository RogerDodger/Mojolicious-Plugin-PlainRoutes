#!/usr/bin/env perl
use Mojo::Base -strict;
use Test::More;
use Test::Deep;
use Mojolicious::Plugin::PlainRoutes;

sub tokenise {
	state $m = Mojolicious::Plugin::PlainRoutes->new;
	return $m->tokenise(@_);
}

my $t1 = tokenise(<<EOF);
GET / -> Foo.bar
GET /baz -> Foo.baz
EOF

cmp_deeply(
	$t1,
	[
		{
			action => 'foo#bar',
			verb => 'GET',
			url => '/',
		},
		{
			action => 'foo#baz',
			verb => 'GET',
			url => '/baz',
		},
	],
	"Simple case"
);

my $t2 = tokenise(<<EOF);
ANY /foo -> Foo.do
	GET /bar -> Foo.bar
	GET /baz -> Foo.baz
EOF

cmp_deeply(
	$t2,
	[
		[
			{ action => 'foo#do', verb => 'ANY', url => '/foo' },
			{ action => 'foo#bar', verb => 'GET', url => '/bar' },
			{ action => 'foo#baz', verb => 'GET', url => '/baz' },
		],
	],
	"One-depth bridge",
);

my $t3 = tokenise(<<EOF);
ANY / -> Foo.do
	GET /bar -> Foo.bar
	ANY /baz -> Foo.baz
		GET /quux -> Foo.quux
	GET /egimosx -> Foo.regex
EOF

cmp_deeply(
	$t3,
	[
		[
			{ action => 'foo#do', verb => 'ANY', url => '/' },
			{ action => 'foo#bar', verb => 'GET', url => '/bar' },
			[
				{ action => 'foo#baz', verb => 'ANY', url => '/baz' },
				{ action => 'foo#quux', verb => 'GET', url => '/quux' },
			],
			{ action => 'foo#regex', verb => 'GET', url => '/egimosx' },
		],
	],
	"Two-depth bridge",
);

done_testing;
