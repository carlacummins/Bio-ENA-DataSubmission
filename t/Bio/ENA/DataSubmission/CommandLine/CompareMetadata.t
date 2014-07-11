#!/usr/bin/env perl
BEGIN { unshift( @INC, './lib' ) }

BEGIN {
    use Test::Most;
	use Test::Output;
	use Test::Exception;
}

use Moose;
use File::Compare;
use File::Path qw( remove_tree);
use Cwd;
use File::Temp;
use Data::Dumper;

my $temp_directory_obj = File::Temp->newdir(DIR => getcwd, CLEANUP => 0 );
my $tmp = $temp_directory_obj->dirname();

use_ok('Bio::ENA::DataSubmission::CommandLine::CompareMetadata');

my ($obj, @args);

#----------------------#
# test illegal options #
#----------------------#

@args = ();
$obj = Bio::ENA::DataSubmission::CommandLine::CompareMetadata->new( args => \@args );
throws_ok {$obj->run} 'Bio::ENA::DataSubmission::Exception::InvalidInput', 'dies without arguments';

@args = ( '-o', 't/data/fakefile.txt');
$obj = Bio::ENA::DataSubmission::CommandLine::CompareMetadata->new( args => \@args );
throws_ok {$obj->run} 'Bio::ENA::DataSubmission::Exception::InvalidInput', 'dies without file input';

@args = ('-f', 'not/a/file');
$obj = Bio::ENA::DataSubmission::CommandLine::CompareMetadata->new( args => \@args );
throws_ok {$obj->run} 'Bio::ENA::DataSubmission::Exception::FileNotFound', 'dies with invalid input file path';

@args = ('-f', 't/data/compare_manifest.xls', '-o', 'not/a/file');
$obj = Bio::ENA::DataSubmission::CommandLine::CompareMetadata->new( args => \@args );
throws_ok {$obj->run} 'Bio::ENA::DataSubmission::Exception::CannotWriteFile', 'dies with invalid output file path';


#--------------#
# test methods #
#--------------#

@args = ('-f', 't/data/compare_manifest.xls', '-o', "$tmp/comparison_report.xls");
$obj = Bio::ENA::DataSubmission::CommandLine::CompareMetadata->new( args => \@args );

# test parsing of XML
my %exp = (
	tax_id           => '1496',
	scientific_name  => '[Clostridium] difficile',
	common_name      => 'Clostridium difficile',
	sample_title     => '[Clostridium] difficile',
	collection_date  => '2007',
	country          => 'USA: AZ',
	specific_host    => 'Free living',
	isolation_source => 'Food',
	strain           => '2007223'
);
is_deeply $obj->_parse_xml('ERS001491'), \%exp, 'XML parsed correctly';

# compare metadata
my %data1 = %exp;
$data1{'sample_accession'} = "ERS001491";
$data1{'sanger_sample_name'} = "2007223";
my %data2 = %data1;
$data2{'tax_id'} = '1111';
$data2{'specific_host'} = 'Human';

my @exp = ( 
	['ERS001491', '2007223', 'specific_host', 'Free living', 'Human'],
	['ERS001491', '2007223', 'tax_id', '1496', '1111']
);
my @got = $obj->_compare_metadata(\%data1, \%data2);
is_deeply \@exp, \@got, 'Correct fields identified as incongruous';

# test reporting
my @errors = @exp;
ok( $obj->_report(\@errors), 'Report write ok' );
ok( -e "$tmp/comparison_report.xls", 'Report exists' );
ok(
	compare( 't/data/comparison_report.xls', "$tmp/comparison_report.xls" ),
	'Report correct'
);

# test reporting without any errors
@args = ('-f', 't/data/compare_manifest.xls', '-o', "$tmp/comparison_report2.xls");
$obj = Bio::ENA::DataSubmission::CommandLine::CompareMetadata->new( args => \@args );

my @no_errors;
ok( $obj->_report(\@no_errors), 'Report write ok' );
ok( -e "$tmp/comparison_report2.xls", 'Report exists' );
ok(
	compare( 't/data/comparison_report2.xls', "$tmp/comparison_report2.xls" ),
	'Report correct'
);

#remove_tree($tmp);
done_testing();

# sub parse_csv{
# 	my $filename = shift;

# 	my @data;
# 	open(FH, $filename);
# 	while ( my $line = <FH> ){
# 		chomp $line;
# 		my @parts = split(",", $line);
# 		push(@data, \@parts);
# 	}
# 	return \@data;
# }