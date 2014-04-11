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

	$self->process($app->routes, $tree);
}

sub tokenise {
	my ($self, $input) = @_;

	if (ref $input eq 'GLOB') {
		$input = do { local $/; <$input> };
	} elsif (ref $input) {
		Carp::carp "Non-filehandle reference passed to tokenise";
		return [];
	}

	return $self->_tokenise($input);
}

sub _tokenise {
	my ($self, $input) = @_;

	$input =~ s/\r\n/\n/g;
	$input =~ s/\n\r/\n/g;
	$input =~ s/\r/\n/g;

	my %grammar = (
		comment    => qr{\# [^\n]*}x,
		verb       => qr{ ANY | DELETE | GET | PATCH | POST | PUT }x,
		path       => qr{ / [^#\s]*}x,
		arrow      => qr{ -> }x,
		scope      => qr( { | } )x,
		action     => qr{ [\w\-:]* \. \w* }x,
		name       => qr{ \( (\w+) \) }x,
		eol        => qr{ \n }x,
		space      => qr{ [^\S\n]+ }x,
	);

	my @words = grep { defined && length }
	              split m{( $grammar{comment}
	                      | $grammar{verb}
	                      | $grammar{path}
	                      | $grammar{arrow}
	                      | $grammar{scope}
	                      | $grammar{action}
	                      | $grammar{name}
	                      | $grammar{eol}
	                      | $grammar{space}
	                      )}x, $input;

	# Include the lexical category with the word, e.g., map:
	#   "/foo" -> { text => "/foo", category => "path" }
	my @annotatedWords;
	for my $word (@words) {
		my @cats = grep { $word =~ /^$grammar{$_}$/ } keys %grammar;

		if (@cats > 1) {
			warn "$word has multiple lexical categories: @cats";
		}

		push @annotatedWords, { text => $word, category => $cats[0] // '' };
	}

	# Add special EOF word to act as a clause terminator if necessary
	push @annotatedWords, { text => '', category => 'eof' };

	my $root    = [];
	my @nodes   = ($root);
	my %clause  = ();
	my $context = 'default';

	for (@annotatedWords) {
		my %word = %$_;

		# While in comment context, the parser checks for newlines and
		# otherwise does nothing.
		if ($context eq 'comment') {
			if ($word{category} eq 'eol') {
				$context = 'default';
			}
		}

		# The comment indicator puts the parser into comment context and
		# otherwise does nothing.
		elsif ($word{category} eq 'comment') {
			$context = 'comment';
		}

		# Whitespace is ignored
		elsif ($word{category} eq 'space' || $word{category} eq 'eol') {}

		# First word in clause must be a HTTP verb
		elsif (!exists $clause{verb}) {
			if ($word{category} eq 'verb') {
				$clause{verb} = $word{text};
			}

			# It's possible we encounter the EOF word here, either because
			# there are no clauses in the file or the last clause was
			# terminated by the end of a scope. Anything else is still a
			# syntax error.
			elsif ($word{category} ne 'eof') {
				_syntax_error("verb", $word{text});
			}
		}

		# Second word must be a path part
		elsif (!exists $clause{path}) {
			if ($word{category} eq 'path') {
				$clause{path} = $word{text};
			} else {
				_syntax_error("path", $word{text});
			}
		}

		# Third word must be an action, optionally preceded by an arrow (->)
		elsif (!exists $clause{action}) {
			if (!exists $clause{arrow} && $word{category} eq 'arrow') {
				$clause{arrow} = 1;
			} elsif ($word{category} eq 'action') {
				$clause{action} = lcfirst $word{text};
				$clause{action} =~ s/\./#/;

				# The clause needn't carry this useless information after this
				# point.
				delete $clause{arrow};
			} else {
				_syntax_error("action", $word{text});
			}
		}

		# The final word should be some kind of terminator: scope indicators,
		# the beginning of a new clause (i.e., a verb), or the end of input.
		else {
			# An optional name for the clause can be appended before the
			# terminator.
			if (!exists $clause{name} && $word{category} eq 'name') {
				$clause{name} = $word{text};
			}

			# The clause is terminated by a new scope. This is also only time
			# that a new scope is syntactically valid. Something like
			#
			#   ANY /foo -> Foo.bridge {}
			#
			# is a syntax error, because the '}' is not preceded by a complete
			# clause. This is acceptable because it makes no sense to have a
			# bridge with no endpoints.
			elsif ($word{category} eq 'scope') {
				# A new scope means that the preceding clause is a bridge, and
				# therefore the head of a new branch in the tree.
				if ($word{text} eq '{') {
					my $newNode = [];
					push @{ $nodes[-1] }, $newNode;
					push @nodes, $newNode;
				}

				# Exiting a scope means that the preceding clause is the last
				# clause in a bridge. We have to add it before popping the
				# node.
				elsif ($word{text} eq '}') {
					# Can't exit a scope if we haven't entered one
					if (@nodes == 1) {
						_syntax_error("verb", $word{text});
					}

					push @{ $nodes[-1] }, { %clause };
					%clause = ();

					pop @nodes;
				}
			}

			# The clause is terminated by the start of a new one
			elsif ($word{category} eq 'verb') {
				push @{ $nodes[-1] }, { %clause };
				%clause = ( verb => $word{text} );
			}

			# Last chance, the clause is terminated by eof
			elsif ($word{category} eq 'eof') {
				push @{ $nodes[-1] }, { %clause };
				%clause = ();
			}

			else {
				_syntax_error("terminator", $word{text});
			}
		}
	}

	$root;
}

sub process {
	my ($self, $bridge, $tree) = @_;

	for my $node (@$tree) {
		my $token = ref $node eq 'ARRAY' ? shift @$node : $node;
		my $route = $bridge->route($token->{path})
		                     ->via($token->{verb})
		                      ->to($token->{action});

		if (exists $token->{name}) {
			$route->name($token->{name});
		} elsif ($self->autoname) {
			$route->name($token->{action} =~ s/\W+/-/rg);
		}

		if (ref $node eq 'ARRAY') {
			$route->inline(1);
			$self->process($route, $node);
		}
	}
}

sub _syntax_error {
	my ($expected, $found) = @_;
	Carp::croak "Syntax error in routes file:\n"
	          . "  Expected: $expected\n"
	          . "  Found:    `$found`\n";
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
