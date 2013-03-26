#
####   Course   ####
#
# A class to handle track and location data
#

#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------           Course          ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package Course;
use Geo::KML;
use warnings;
use strict;

sub new {
	my $package = shift @_;
	my %init = @_;
	my $croak;

	$init{debug} = undef unless (defined $init{debug} && $init{debug} > 0);

	croak("You must supply a 'kmlfile' when initializing this object\n") unless (defined $init{kmlfile});
	croak("The 'kmlfile' supplied was not valid\n") unless (-r $init{kmlfile});

	print "Loading requested KML file..." if $init{debug};
	my ($type, $data) = Geo::KML->from(shift @_);
	if ($$data{Document}{name}) {
		printf "[1;32m%s : OK[0m\n", $$data{Document}{name} if $init{debug};
	}
	else {
		croak("KML file had no document name");
	}

	print "Locating folder..." if $init{debug};
	my $folder = shift @{$$data{Document}{AbstractFeatureGroup}};
	if ($$folder{Folder}{name}) {
		printf "[1;32m%s : OK[0m\n", $$folder{Folder}{name} if $init{debug};
		$init{trackname} = $$folder{Folder}{name};
	}
	else {
		croak("KML file contained no folder. Maybe you didn't save from the folder level?");
	}

	my $zone = {};
	
	print "Extracting zone definitions..." if $init{debug};
	for my $placemark (@{$$folder{Folder}{AbstractFeatureGroup}}) {
		my $polyname = $$placemark{Placemark}{name};
		my $perimeter = $$placemark{Placemark}{Polygon}{outerBoundaryIs}{LinearRing}{coordinates};

		next unless ($perimeter); # Skip objects that aren't polygons

		$zone->{$polyname} = [];

		foreach my $coords (@$perimeter) {
			my ($lon, $lat) = (split(/,/, $coords))[0,1];
			push(@{$zone->{$polyname}}, {lon=>$lon, lat=>$lat} );
		}
	}
	if (scalar (keys %$zone) > 0) {
		printf "[1;32mOK: Loaded %d polygons[0m\n", scalar(keys %$zone) if $init{debug};
	}
	else {
		croak("Could not extract polygons from KML file; reason not known.");
	}

	$init{$zone} = $zone;

	bless \%init => $package;
}

1;
