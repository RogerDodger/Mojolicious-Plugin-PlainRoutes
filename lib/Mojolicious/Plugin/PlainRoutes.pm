package Mojolicious::Plugin::PlainRoutes;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.01';

has autoname => 0;

sub register {
	my ($self, $app, $conf) = @_;

	my $file = $app->home->rel_file(
		$conf->{filename} // "lib/" . $app->moniker . ".routes"
	);

	$self->autoname($conf->{autoname});

	open my $fh, '<', $file;
	my $tree = $self->tokenise($fh);
	close $fh;

	process($app->routes, $tree);
}

sub tokenise {
	my ($self, $input) = @_;

	if (ref $input eq 'GLOB') {
		$input = do { local $/; <$input> };
	} elsif (ref $input) {
		Carp::carp "Non-filehandle reference passed to tokenise";
		return [];
	}

	$input =~ s/\r\n/\n/g;
	$input =~ s/\n\r/\n/g;
	$input =~ s/\r/\n/g;

	return $self->_tokenise(split /\n/, $input);
}

sub _tokenise {
	my ($self, @lines) = @_;

	my $root = [];
	my @nodes = ($root);

	for my $line (@lines) {
		# Remove comments
		$line =~ s/#.+//;

		# Ignore empty lines
		next if $line =~ /^\s+$/;

		if ($line =~ m{
			(?<verb> ANY|GET|POST|PUT|PATCH|DELETE)
			\s+
			(?<url> \S+)
			\s+
			->
			\s+
			(?<action> \w+ (?:\.\w+)*+ )
			(?:
				\s+
				\( (?<name>\w+) \)
			)?
			}x)
		{
			my $token = {
				map { $_ => $+{$_} }
					grep { defined $+{$_} } qw/verb url action name/
			};

			$token->{action} =~ s/\./#/;
			$token->{action} = lcfirst $token->{action};

			if ($self->autoname && !defined $token->{name}) {
				$token->{name} = $token->{action};
				$token->{name} =~ s/\W+/-/g;
			}

			# Check the indent of the line to see where we are on the tree
			my ($indent) = $line =~ /^(\t*)/;
			$indent = length $indent;

			if ($indent == $#nodes+1) {
				my $curr = $nodes[-1];
				my $new = [ pop @$curr ];
				push @$curr, $new;
				push @nodes, $new;
			} elsif ($indent < $#nodes) {
				while ($indent != $#nodes) {
					pop @nodes;
				}
			} elsif ($indent != $#nodes) {
				Carp::carp "Malformed route: '$line'";
				next;
			}

			push @{ $nodes[-1] }, $token;
		}
	}

	$root;
}

sub process {
	my ($bridge, $tree) = @_;

	for my $node (@$tree) {
		my $token = ref $node eq 'ARRAY' ? shift @$node : $node;
		my $route = $bridge->route($token->{url})
		                    ->via($token->{verb})
		                      ->to($token->{action});
		if (exists $token->{name}) {
			$route->name($token->{name});
		}

		if (ref $node eq 'ARRAY') {
			$route->inline(1);
			process($route, $node);
		}
	}
}

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::PlainRoutes - Plaintext route definitions for Mojolicious
apps

=head1 SYNOPSIS

Blah blah blah

=head1 AUTHOR

Cameron Thornton <cthor@cpan.org>

=head1 SUPPORT

Use the issue tracker on the Github repository for bugs/feature requests:

    https://github.com/RogerDodger/Mojolicious-Plugin-PlainRoutes/issues

=head1 LICENSE AND COPYRIGHT

Copyright 2014 Cameron Thornton.

This program is free software; you can redistribute it and/or modify it
under the terms of Perl version 5.

=cut
