package WWW::Google::Contacts::Meta::Attribute::Trait::XmlField;

use Moose::Role;

has xml_key => (
    isa      => 'Str',
    is       => 'ro',
    required => 1,
);

# Allow attributes to have custom code for transforming to xml
has to_xml => (
    isa       => 'CodeRef',
    is        => 'ro',
    predicate => 'has_to_xml',
);

has is_element => (
    isa       => 'Bool',
    is        => 'ro',
    default   => sub { 0 },
);

has include_in_xml => (
    isa       => 'Bool',
    is        => 'ro',
    default   => sub { 1 },
);

no Moose::Role;

package Moose::Meta::Attribute::Custom::Trait::XmlField;
sub register_implementation {'WWW::Google::Contacts::Meta::Attribute::Trait::XmlField'}

1;
