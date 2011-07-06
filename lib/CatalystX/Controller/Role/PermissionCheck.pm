package CatalystX::Controller::Role::PermissionCheck;

use Moose::Role;
use Try::Tiny;

## ABSTRACT: Provides an opinionated method for verifying permissions on a per-action basis by inspecting the user.

# Requires setup in the consuming class.
requires 'setup';

has 'access_check' => (
    is        => 'rw',
    isa       => 'CodeRef',
    predicate => 'has_access_check'
);

has 'permissions' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [ 'Hash' ],
    default => sub { { } },
    lazy    => 1,
    handles => {
        'get_permission_for_action' => 'get',
        'has_permissions' => 'count',
    }
);

has 'allow_by_default' => (
    is      => 'rw',
    isa     => 'Bool',
    default => sub { 1; },
    lazy    => 1,
);

=method setup

Before setup is called, this role inspects
C<< $c->stash->{context}->{permissions} >> for applicable roles.

It confirms permissions to access the action. This only works with
L<Catalyst::DispatchType::Chained> and will walk the entire chain and verify
access checks at each level.

=cut

after 'setup' => sub {
    my ( $self, $c ) = @_;
    my $namespace = $self->action_namespace($c);
    my $chain     = $c->dispatcher->expand_action($c->action);

    my @actions   = grep { $_->namespace eq $namespace } @{ $chain->chain };
    # XX This should crawl the entire action chain and iterate to find
    # permissions. But it doesn't, so supply a patch!
    my $action = $actions[-1] ? $actions[-1]->name : $c->action->name;

    my $perm = $self->get_permission_for_action( $action );
    if ( $c->req->method ne 'GET' and not defined $perm ) {
        # Not a GET request, so look up the $action_PUT style actions that
        # Catalyst::Controller::REST uses.
        $perm = $self->get_permission_for_action( $action . '_' . $c->req->method);
        $c->log->debug("Nothing on top level, checking req method: $action") if $c->debug;
    }
    # Still don't have permissions, look at setup
    if ( not defined $perm ) {
        $perm = $self->get_permission_for_action( 'setup' );
    }

    if ( not defined $perm and not $self->allow_by_default ) {
        $c->log->error("Action misconfiguration! allow_by_default is off but this action ($action) has no permissions configured (nor a setup action)");
        $c->detach('permission_denied');
    }
    elsif ( defined $perm and
            not grep { exists $c->stash->{context}->{permissions}->{$_} } @$perm
    ) {
        $c->log->info(
            "Access denied for user: " .
            ( $c->user_exists ? $c->user->name : 'anonymous' ) .
            ", require permissions @$perm for action $action, only has: " .
            join(', ', keys %{ $c->stash->{context}->{permissions} } )
        );
        $c->detach('permission_denied');
    }
};

no Moose::Role;
1;
