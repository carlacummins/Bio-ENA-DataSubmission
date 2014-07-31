package Bio::ENA::DataSubmission::XML;

# ABSTRACT: module for parsing, appending and writing spreadsheets for ENA manifests

=head1 NAME

Bio::ENA::DataSubmission::XML

=head1 SYNOPSIS

	use Bio::ENA::DataSubmission::XML;
	


=head1 METHODS

parse, validate, update

=head1 CONTACT

path-help@sanger.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';
use Moose;

use Bio::ENA::DataSubmission::Exception;
use Bio::ENA::DataSubmission::XMLSimple;
use XML::Simple;
use XML::LibXML;
use LWP;
use Switch;
use Data::Dumper;

has 'xml'     => ( is => 'rw', isa => 'Str',      required => 0 );
has 'url'     => ( is => 'rw', isa => 'Str',      required => 0 );
has 'data'    => ( is => 'rw', isa => 'HashRef',  required => 0 );
has 'xsd'     => ( is => 'ro', isa => 'Str',      required => 0 );
has 'outfile' => ( is => 'rw', isa => 'Str',      required => 0 );
has 'root'    => ( is => 'ro', isa => 'Str',      required => 0, default    => 'root' );
has '_fields' => ( is => 'rw', isa => 'ArrayRef', required => 0, lazy_build => 1 );

sub _build__fields {
	# this will change with schema eventually
	my @f = qw(anonymized_name bio_material culture_collection	
					specimen_voucher collected_by collection_date country
					specific_host host_status identified_by isolation_source lat_lon
					lab_host environmental_sample mating_type isolate strain
					sub_species sub_strain serovar);
	return \@f;
}

sub validate {
	my $self = shift;
	my $xml  = $self->xml;
	my $xsd  = $self->xsd;

	( -e $xml ) or Bio::ENA::DataSubmission::Exception::FileNotFound->throw( error => "Can't find file: $xml\n" );
	( -r $xml ) or Bio::ENA::DataSubmission::Exception::CannotReadFile->throw( error => "Can't read file: $xml\n" );
	( -e $xsd ) or Bio::ENA::DataSubmission::Exception::FileNotFound->throw( error => "Can't find file: $xsd\n" );
	( -r $xsd ) or Bio::ENA::DataSubmission::Exception::CannotReadFile->throw( error => "Can't read file: $xsd\n" );

	my $p = XML::LibXML->new();
	my $doc = $p->parse_file( $xml );
	my $xsd_validator = XML::LibXML::Schema->new( location => $xsd );
	return ( $xsd_validator->validate( $doc ) ) ? 0 : 1;
}

sub update {
	my ( $self, $sample ) = @_;

	my $acc = $sample->{'sample_accession'};
	$self->url("http://www.ebi.ac.uk/ena/data/view/$acc&display=xml");
	my $xml = $self->parse_from_url;
	
	return undef unless( defined $xml->{SAMPLE} );

	# extract sample XML and remove unwanted values
	my $sample_xml = $xml->{SAMPLE};
	delete $sample_xml->[0]->{alias};
	delete $sample_xml->[0]->{center_name};
	delete $sample_xml->[0]->{SAMPLE_LINKS};

	# remove unwanted values from sample metadata
	delete $sample->{'sanger_sample_name'};
	
	my $v;
	foreach my $k ( keys $sample ){
		$v = $sample->{$k};
		$self->_update_fields( $sample_xml, $k, $v ) if ( defined $v && $v ne '' );
	}

	return $sample_xml->[0];
}

sub _update_fields {
	my ( $self, $xml, $key, $value ) = @_;

	my $found = 0;

	# first check basic data
	switch($key){
		case 'sample_accession'   { $xml->[0]->{accession}                           = $value; $found = 1 }
		case 'sample_alias'       { $xml->[0]->{alias}                               = $value; $found = 1 }
		case 'tax_id'             { $xml->[0]->{SAMPLE_NAME}->[0]->{TAXON_ID}        = [$value]; $found = 1 }
		case 'scientific_name'    { $xml->[0]->{SAMPLE_NAME}->[0]->{SCIENTIFIC_NAME} = [$value]; $found = 1 }
		case 'common_name'        { $xml->[0]->{SAMPLE_NAME}->[0]->{COMMON_NAME}     = [$value]; $found = 1 }
		case 'sample_title'       { $xml->[0]->{TITLE}                               = [$value]; $found = 1 }
		case 'sample_description' { $xml->[0]->{DESCRIPTION}                         = [$value]; $found = 1 }
	}

	# if not found, then check sample attributes list
	unless( $found ){
		my @attrs = @{ $xml->[0]->{SAMPLE_ATTRIBUTES}->[0]->{SAMPLE_ATTRIBUTE} };
		foreach my $a ( 0..$#attrs){
			#print STDERR "key: ";
			#print Dumper $attrs[$a]->{TAG};
			if ( $attrs[$a]->{TAG}->[0] eq $key ){
				$xml->[0]->{SAMPLE_ATTRIBUTES}->[0]->{SAMPLE_ATTRIBUTE}->[$a]->{VALUE} = [$value];
				$found = 1;
				last;
			}
		}
	}

	# if still not found, add it
	unless ( $found ){
		push( @{ $xml->[0]->{SAMPLE_ATTRIBUTES}->[0]->{SAMPLE_ATTRIBUTE} }, {'TAG' => [$key], 'VALUE' => [$value]} )
	}

}

sub parse_from_file {
	my $self = shift;
	my $xml = $self->xml;

	(defined $xml) or Bio::ENA::DataSubmission::Exception::InvalidInput->throw( error => "XML file must be passed to read\n" );
	(-e $xml && -r $xml) or Bio::ENA::DataSubmission::Exception::CannotReadFile->throw( error => "Cannot read $xml\n" );

	return XML::Simple->new()->XMLin($xml);
}

sub parse_from_url {
	my $self = shift;
	my $url = $self->url;

	my $ua = LWP::UserAgent->new;
	$ua->proxy(['http', 'https'], 'http://wwwcache.sanger.ac.uk:3128');
	my $req = HTTP::Request->new( GET => $url );
	my $res = $ua->request( $req );

	$res->is_success or Bio::ENA::DataSubmission::Exception::ConnectionFail->throw( error => "Could not connect to $url\n" );

	return (XML::Simple->new( ForceArray => 1 )->XMLin( $res->content ));
}

sub write {
	my $self    = shift;
	my $outfile = $self->outfile;
	my $data    = $self->data;

	system("touch $outfile &> /dev/null") == 0 or Bio::ENA::DataSubmission::Exception::CannotWriteFile->throw( error => "Cannot write file: $outfile\n" );

	my $writer = Bio::ENA::DataSubmission::XMLSimple->new( RootName => $self->root, XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>', NoAttr => 0 );
	
	my $out = $writer->XMLout( $data );
	open( OUT, '>', $outfile );
	print OUT $out;
	close OUT;
}

sub parse_xml_metadata{
	my ($self, $acc) = @_;

	$self->url("http://www.ebi.ac.uk/ena/data/view/$acc&display=xml");
	my $xml = $self->parse_from_url;
	my @fields = @{ $self->_fields };

	my %data;
	$data{'sample_title'} = $xml->[0]->{SAMPLE}->[0]->{TITLE}->[0] if (defined($xml->[0]->{SAMPLE}->[0]->{TITLE}->[0]));
	my $sample_name = $xml->[0]->{SAMPLE}->[0]->{SAMPLE_NAME}->[0] if (defined($xml->[0]->{SAMPLE}->[0]->{SAMPLE_NAME}->[0]));
	$data{'tax_id'} = $sample_name->{TAXON_ID}->[0] if (defined($sample_name->{TAXON_ID}->[0]));
	$data{'common_name'} = $sample_name->{COMMON_NAME}->[0] if (defined($sample_name->{COMMON_NAME}->[0]));
	$data{'scientific_name'} = $sample_name->{SCIENTIFIC_NAME}->[0] if (defined($sample_name->{SCIENTIFIC_NAME}->[0]));

	my @attributes = @{ $xml->[0]->{SAMPLE}->[0]->{SAMPLE_ATTRIBUTES}->[0]->{SAMPLE_ATTRIBUTE}->[0] } if (defined($xml->[0]->{SAMPLE}->[0]->{SAMPLE_ATTRIBUTES}->[0]->{SAMPLE_ATTRIBUTE}->[0]));
	foreach my $att ( @attributes ){
		my $tag = $att->{TAG}->[0];
		next unless( defined $tag );
		$tag = "specific_host" if ( $tag eq 'host' );
		$data{ $tag } = $att->{VALUE}->[0] if ( grep( /^$tag$/, @fields ) );
	}
	return \%data;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;