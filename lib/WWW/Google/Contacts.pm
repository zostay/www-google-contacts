package WWW::Google::Contacts;

# ABSTRACT: Google Contacts Data API

use warnings;
use strict;
use Carp qw/croak/;
use URI::Escape;
use LWP::UserAgent;
use Net::Google::AuthSub;
use XML::Simple ();
use HTTP::Request;

sub new {
    my $class = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    unless ( $args->{ua} ) {
        my $ua_args = delete $args->{ua_args} || {};
        $args->{ua} = LWP::UserAgent->new(%$ua_args);
    }
    $args->{authsub} ||= Net::Google::AuthSub->new(service => 'cp');
    $args->{xmls} ||= XML::Simple->new();
    $args->{debug} ||= 0;
    $args->{'GData-Version'} = 3.0;
    
    bless $args, $class;
}

sub login {
    my ($self, $email, $pass) = @_;

    $email ||= $self->{email};
    $pass  ||= $self->{pass};
    $email or croak 'login(email, pass)';
    $pass  or croak 'login(email, pass)';

    return 1 if $self->{_is_authed} and $self->{_is_authed} eq $email;

    my $resp = $self->{authsub}->login($email, $pass);
    unless ( $resp and $resp->is_success ) {
        return 0;
    }
    
    $self->{email} = $email;
    $self->{pass}  = $pass;
    $self->{_is_authed} = $email;
    return 1;
}

sub create_contact {
    my $self = shift;
    my $contact = scalar @_ % 2 ? shift : { @_ };
    
    $self->login() or croak 'Authentication failed';
    
    my $data = {
        'atom:entry' => {
            'xmlns:atom' => 'http://www.w3.org/2005/Atom',
            'xmlns:gd'   => 'http://schemas.google.com/g/2005',
            'atom:category' => {
                'scheme' => 'http://schemas.google.com/g/2005#kind',
                'term'   => 'http://schemas.google.com/contact/2008#contact'
            },
            'gd:name' => {
                'gd:givenName'  => [ $contact->{givenName} ],
                'gd:familyName' => [ $contact->{familyName} ],
                'gd:fullName'   => [ $contact->{fullName} ],
            },
            'atom:content' => {
                type => 'text',
                content => $contact->{Notes},
            },
            'gd:email' => [
                {
                    rel => 'http://schemas.google.com/g/2005#work',
                    primary => 'true',
                    address => $contact->{primaryMail},
                    displayName => $contact->{displayName},
                }
            ],
        },
    };
    if ( $contact->{secondaryMail} ) {
        push @{ $data->{'atom:entry'}->{'gd:email'} }, {
            rel => 'http://schemas.google.com/g/2005#home',
            address => $contact->{secondaryMail},
        }
    }
    my $xml = $self->{xmls}->XMLout($data, KeepRoot => 1);
    print STDERR $xml . "\n" if $self->{debug};
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'Content-Type'} = 'application/atom+xml';
    $headers{'GData-Version'} = $self->{'GData-Version'};
    my $url = 'http://www.google.com/m8/feeds/contacts/default/full';
    my $resp =$self->{ua}->post( $url, %headers, Content => $xml );
    print STDERR $resp->content . "\n" if $self->{debug};
    return ($resp->code == 201) ? 1 : 0;
}

sub get_contacts {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    $self->login() or croak 'Authentication failed';
    
    $args->{'alt'} = 'atom'; # must be atom
    $args->{'max-results'} ||= 9999;
    my $group = delete $args->{group} || 'full';
    my $url = sprintf( 'http://www.google.com/m8/feeds/contacts/default/%s?v=3.0', uri_escape($group) );
    foreach my $key (keys %$args) {
        $url .= '&' . uri_escape($key) . '=' . uri_escape($args->{$key});
    }
    my $resp =$self->{ua}->get( $url, $self->{authsub}->auth_params );
    my $content = $resp->content;
    print STDERR $content . "\n" if $self->{debug};
    my $data = $self->{xmls}->XMLin($content, ForceArray => ['entry', 'gd:email', 'gContact:groupMembershipInfo'], SuppressEmpty => undef);
    
    my @contacts;
    foreach my $id (keys %{ $data->{entry} } ) {
        my $d = $data->{entry}->{$id};
        $d->{id} = $id;
        $d->{name} = $d->{'gd:name'};
        $d->{email} = $d->{'gd:email'};
        $d->{groupMembershipInfo} = $d->{'gContact:groupMembershipInfo'};
        push @contacts, $d;
    }
    
    return @contacts;
}

sub get_contact {
    my ($self, $id) = @_;
    
    $self->login() or croak 'Authentication failed';
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'GData-Version'} = $self->{'GData-Version'};
    my $resp =$self->{ua}->get( $id, %headers );
    print $resp->content . "\n" if $self->{debug};
    my $data = $self->{xmls}->XMLin($resp->content, SuppressEmpty => undef);
    return $data;
}

sub update_contact {
    my ($self, $id, $contact) = @_;
    
    $self->login() or croak 'Authentication failed';

    my $data = {
        'atom:entry' => {
            'xmlns:atom' => 'http://www.w3.org/2005/Atom',
            'xmlns:gd'   => 'http://schemas.google.com/g/2005',
            'atom:category' => {
                'scheme' => 'http://schemas.google.com/g/2005#kind',
                'term'   => 'http://schemas.google.com/contact/2008#contact'
            },
            id => [ $id ],
            'gd:name' => {
                'gd:givenName'  => [ $contact->{givenName} ],
                'gd:familyName' => [ $contact->{familyName} ],
                'gd:fullName'   => [ $contact->{fullName} ],
            },
            'atom:content' => {
                type => 'text',
                content => $contact->{Notes},
            },
            'gd:email' => [
                {
                    rel => 'http://schemas.google.com/g/2005#work',
                    primary => 'true',
                    address => $contact->{primaryMail},
                    displayName => $contact->{displayName},
                }
            ],
            'link' => [
                {
                    rel  => 'self',
                    type => 'application/atom+xml',
                    href => $id,
                },
                {
                    rel  => 'edit',
                    type => 'application/atom+xml',
                    href => $id,
                },
            ],
        },
    };
    if ( $contact->{secondaryMail} ) {
        push @{ $data->{'atom:entry'}->{'gd:email'} }, {
            rel => 'http://schemas.google.com/g/2005#home',
            address => $contact->{secondaryMail},
        }
    }
    if ( $contact->{groupMembershipInfo} ) {
        $data->{'atom:entry'}->{'gContact:groupMembershipInfo'} = {
            deleted => 'false',
            href => $contact->{groupMembershipInfo}
        };
    }
    my $xml = $self->{xmls}->XMLout($data, KeepRoot => 1);
    print $xml . "\n" if $self->{debug};
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'Content-Type'} = 'application/atom+xml';
    $headers{'GData-Version'} = $self->{'GData-Version'};
    $headers{'If-Match'} = '*';
    $headers{'X-HTTP-Method-Override'} = 'PUT';
    my $resp =$self->{ua}->post( $id, %headers, Content => $xml );
    print $resp->content . "\n" if $self->{debug};
    return ($resp->code == 200) ? 1 : 0;
}

sub delete_contact {
    my ($self, $id) = @_;
    
    $self->_delete($id);
}

sub get_groups {
    my $self = shift;
    my $args = scalar @_ % 2 ? shift : { @_ };

    $self->login() or croak 'Authentication failed';
    
    $args->{'alt'} = 'atom'; # must be atom
    $args->{'max-results'} ||= 9999;
    my $url  = 'http://www.google.com/m8/feeds/groups/default/full?v=3.0';
    foreach my $key (keys %$args) {
        $url .= '&' . uri_escape($key) . '=' . uri_escape($args->{$key});
    }
    my $resp =$self->{ua}->get( $url, $self->{authsub}->auth_params );
    my $content = $resp->content;
    print $content . "\n" if $self->{debug};
    my $data = $self->{xmls}->XMLin($content, SuppressEmpty => undef);
    
    my @groups;
    foreach my $id (keys %{ $data->{entry} } ) {
        my $d = $data->{entry}->{$id};
        push @groups, {
            id => $id,
            title   => $d->{title},
            updated => $d->{updated},
            exists $d->{'gContact:systemGroup'} ? ('gContact:systemGroup' => $d->{'gContact:systemGroup'}->{'id'}) : (),
        };
    }
    
    return @groups;
}

sub get_group {
    my ($self, $id) = @_;
    
    $self->login() or croak 'Authentication failed';
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'GData-Version'} = $self->{'GData-Version'};
    my $resp =$self->{ua}->get( $id, %headers );
    print $resp->content . "\n" if $self->{debug};
    my $data = $self->{xmls}->XMLin($resp->content, SuppressEmpty => undef);
    return $data;
}

sub create_group {
    my $self = shift;
    my $contact = scalar @_ % 2 ? shift : { @_ };
    
    $self->login() or croak 'Authentication failed';

    my $data = {
        'atom:entry' => {
            'xmlns:atom' => 'http://www.w3.org/2005/Atom',
            'xmlns:gd'   => 'http://schemas.google.com/g/2005',
            'atom:category' => {
                'scheme' => 'http://schemas.google.com/g/2005#kind',
                'term'   => 'http://schemas.google.com/contact/2008#group'
            },
            'atom:title' => {
                type => 'text',
                content => $contact->{title},
            }
        },
    };
    my $xml = $self->{xmls}->XMLout($data, KeepRoot => 1);
    print $xml . "\n" if $self->{debug};
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'Content-Type'} = 'application/atom+xml';
    $headers{'GData-Version'} = $self->{'GData-Version'};
    my $url = 'http://www.google.com/m8/feeds/groups/default/full';
    my $resp =$self->{ua}->post( $url, %headers, Content => $xml );
    print $resp->content . "\n" if $self->{debug};
    return ($resp->code == 201) ? 1 : 0;
}

sub update_group {
    my ($self, $id, $args) = @_;
    
    $self->login() or croak 'Authentication failed';

    my $data = {
        'atom:entry' => {
            'xmlns:atom' => 'http://www.w3.org/2005/Atom',
            'xmlns:gd'   => 'http://schemas.google.com/g/2005',
            'atom:category' => {
                'scheme' => 'http://schemas.google.com/g/2005#kind',
                'term'   => 'http://schemas.google.com/contact/2008#group'
            },
            id => [ $id ],
            'atom:title' => {
                type => 'text',
                content => $args->{title},
            },
            'link' => [
                {
                    rel  => 'self',
                    type => 'application/atom+xml',
                    href => $id,
                },
                {
                    rel  => 'edit',
                    type => 'application/atom+xml',
                    href => $id,
                },
            ],
        },
    };
    my $xml = $self->{xmls}->XMLout($data, KeepRoot => 1);
    print $xml . "\n" if $self->{debug};
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'Content-Type'} = 'application/atom+xml';
    $headers{'GData-Version'} = $self->{'GData-Version'};
    $headers{'If-Match'} = '*';
    $headers{'X-HTTP-Method-Override'} = 'PUT';
    my $resp =$self->{ua}->post( $id, %headers, Content => $xml );
    print $resp->content . "\n" if $self->{debug};
    return ($resp->code == 200) ? 1 : 0;
}

sub delete_group {
    my ($self, $id) = @_;
    
    $self->_delete($id);
}

sub _delete {
    my ($self, $id) = @_;
    
    $self->login() or croak 'Authentication failed';
    
    my %headers = $self->{authsub}->auth_params;
    $headers{'If-Match'} = '*';
    $headers{'X-HTTP-Method-Override'} = 'DELETE';
    $headers{'GData-Version'} = $self->{'GData-Version'};
    my $resp =$self->{ua}->post($id, %headers);
    return $resp->code == 200 ? 1 : 0;
}

1;
__END__

=head1 SYNOPSIS

    use WWW::Google::Contacts;

    my $gcontacts = WWW::Google::Contacts->new();
    $gcontacts->login('fayland@gmail.com', 'pass') or die 'login failed';
    
    # create contact
    my $status = $gcontacts->create_contact( {
        givenName => 'FayTestG',
        familyName => 'FayTestF',
        fullName   => 'Fayland Lam',
        Notes     => 'just a note',
        primaryMail => 'primary@example.com',
        displayName => 'FayTest Dis',
        secondaryMail => 'secndary@test.com', # optional
    } );
    print "Create OK" if $status;
    
    my @contacts = $gcontacts->get_contacts;
    foreach my $contact (@contacts) {
        my @emails = map { $_->{address} } @{ $contact->{email} };
        print "$contact->{name}->{'gd:fullName'}: " . join(', ', @emails) . "\n";
        $gcontacts->delete_contact($contact->{id})
            if $contact->{name}->{'gd:givenName'} eq 'Test';
    }

=head1 DESCRIPTION

This module implements 'Google Contacts Data API' according L<http://code.google.com/apis/contacts/docs/3.0/developers_guide_protocol.html>

=head2 METHODS

=over 4

=item * new/login

    my $gcontacts = WWW::Google::Contacts->new();
    $gcontacts->login('fayland@gmail.com', 'pass') or die 'login failed';

=item * create_contact

    $gcontacts->create_contact( {
        givenName => 'FayTestG',
        familyName => 'FayTestF',
        fullName   => 'Fayland Lam',
        Notes     => 'just a note',
        primaryMail => 'primary@example.com',
        displayName => 'FayTest Dis',
        secondaryMail => 'secndary@test.com', # optional
    } );

return 1 if created

=item * get_contacts

    my @contacts = $gcontacts->get_contacts;
    my @contacts = $gcontacts->get_contacts( {
        group => 'thin', # default to 'full'
    } )
    my @contacts = $gcontacts->get_contacts( {
        updated-min => '2007-03-16T00:00:00',
        start-index => 10,
        max-results => 99, # default as 9999
    } );

get contacts from this account.

C<group> refers L<http://code.google.com/apis/contacts/docs/2.0/reference.html#Projections>

C<start-index>, C<max_results> etc refer L<http://code.google.com/apis/contacts/docs/2.0/reference.html#Parameters>

=item * get_contact($id)

    my $contact = $gcontacts->get_contact('http://www.google.com/m8/feeds/contacts/account%40gmail.com/base/1');

get a contact by B<id>

=item * update_contact

    my $status = $gcontacts->update_contact('http://www.google.com/m8/feeds/contacts/account%40gmail.com/base/123623e48cb4e70a', {
        givenName => 'FayTestG2',
        familyName => 'FayTestF2',
        fullName   => 'Fayland Lam2',
        Notes     => 'just a note2',
        primaryMail => 'primary@example2.com',
        displayName => 'FayTest2 Dis',
        secondaryMail => 'secndary@test62.com', # optional
    } );

update a contact

=item * delete_contact($id)

    my $status = $gcontacts->delete_contact('http://www.google.com/m8/feeds/contacts/account%40gmail.com/base/1');

The B<id> is from C<get_contacts>.

=item * create_group

    my $status = $gcontacts->create_group( { title => 'Test Group' } );

Create a new group

=item * get_groups

    my @groups = $gcontacts->get_groups;
    my @groups = $gcontacts->get_groups( {
        updated-min => '2007-03-16T00:00:00',
        start-index => 10,
        max-results => 99, # default as 9999
    } );

Get all groups.

=item * get_group($id)

    my $group = $gcontacts->get_group('http://www.google.com/m8/feeds/groups/account%40gmail.com/base/6e744e7d0a4b398c');

get a group by B<id>

=item * update_group($id, { title => $title })

    my $status = $gcontacts->update_group( 'http://www.google.com/m8/feeds/groups/account%40gmail.com/base/6e744e7d0a4b398c', { title => 'New Test Group 66' } );

Update a group

=item * delete_group

    my $status = $gcontacts->delete_contact('http://www.google.com/m8/feeds/groups/account%40gmail.com/base/6e744e7d0a4b398c');

=back

=head2 ACKNOWLEDGE

John Clyde - who share me with his code about Contacts API