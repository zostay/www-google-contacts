package WWW::Google::Contacts::Type::Content;

use Moose;
use MooseX::Types::Moose qw( Str );
use WWW::Google::Contacts::Meta::Attribute::Trait;

extends 'WWW::Google::Contacts::Type::Base';

has value => (
    isa       => Str,
    is        => 'rw',
    traits    => [ 'XmlField' ],
    xml_key   => 'content',
    predicate => 'has_value',
    required  => 1,
);

no Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__