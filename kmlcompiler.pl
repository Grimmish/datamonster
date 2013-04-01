#!/usr/bin/perl
# 
# kmlcompiler
#
# Parses KML files for use with Datamonster and pre-parses them into a format that
# the modest-CPU RPi can read in and start using much faster.
#

use warnings;
use strict;

BEGIN {
	print "Initializing...\n";
}

use Data::Dumper;
use Geo::KML;
sub usage {
	print <<'___END';

USAGE:
	kmlcompiler.pl INFILE.kml OUTFILE.dml

___END
	exit 1;
}

usage() if ( (scalar @ARGV != 2) or (! -r $ARGV[0])) ;

my $infile = shift @ARGV;
my $outfile = shift @ARGV;

my $exportObj = {};

$| = 1;
print "Reading and parsing KML file...";
my ($type, $data) = Geo::KML->from($infile);
if ($$data{Document}{name}) {
	printf "[1;32m%s : OK[0m\n", $$data{Document}{name};
}
else {
	croak("KML file had no document name");
}

print "Locating folder..." ;
my $folder = shift @{$$data{Document}{AbstractFeatureGroup}};
if ($$folder{Folder}{name}) {
	printf "[1;32m%s : OK[0m\n", $$folder{Folder}{name};
	$$exportObj{trackname} = $$folder{Folder}{name};
}
else {
	croak("KML file contained no folder. Maybe you didn't save from the folder level?");
}

my $zone = {};
	
print "Extracting zone definitions...\n";
for my $placemark (@{$$folder{Folder}{AbstractFeatureGroup}}) {
	my $polyname = $$placemark{Placemark}{name};
	my $perimeter = $$placemark{Placemark}{Polygon}{outerBoundaryIs}{LinearRing}{coordinates};

	next unless ($perimeter); # Skip objects that aren't polygons

	$zone->{$polyname} = [];

	foreach my $coords (@$perimeter) {
		my ($lon, $lat) = (split(/,/, $coords))[0,1];
		push(@{$zone->{$polyname}}, {lon=>$lon, lat=>$lat} );
	}
	print "    ZONE: $polyname\n";
}
if (scalar (keys %$zone) > 0) {
	printf "[1;32mOK: Loaded %d polygons[0m\n", scalar(keys %$zone);
}
else {
	croak("Could not extract polygons from KML file; reason not known.");
}

$$exportObj{zone} = $zone;

print "\n";

open(my $export, ">", $outfile) or die "Couldn't open the output file ($outfile): $!\n";
print $export Dumper($exportObj);
close($export);

print "Wrote output file. All done!\n\n";
