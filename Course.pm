#
####   Course   ####
#
# A class to handle track and location data
#
# TRIVIAL EDIT TO TEST GITHUB

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
use Storable qw ( retrieve );
use warnings;
use strict;

sub new {
	my $package = shift @_;
	my %init = @_;

	$init{debug} = undef unless (defined $init{debug} && $init{debug} > 0);

	croak("You must supply a 'dmlfile' when initializing this object\n") unless (defined $init{dmlfile});
	croak("The 'dmlfile' supplied was not valid\n") unless (-r $init{dmlfile});

	print "Loading requested DML file..." if $init{debug};
	my $dmlload = retrieve($init{dmlfile});
	croak("The 'dmlfile' supplied could not be parsed\n") unless (defined $dmlload);

	foreach my $key (keys %$dmlload) {
		$init{$key} = $$dmlload{$key};
	}

	bless \%init => $package;
}

sub whereAmI {
	my $self = shift;
	my $debug = $self->{debug};

	my $lon = shift;
	my $lat = shift;

	ZONE: foreach my $id (keys %{$self->{zone}}) {
		my @shape = @{$self->{zone}->{$id}};
		for (my $pt = 0; $pt < $#shape; $pt++) {
			# Reference: http://paulbourke.net/geometry/insidepoly/
			my $comp = (($lat - $shape[$pt]{lat}) * ($shape[$pt+1]{lon} - $shape[$pt]{lon})) - (($lon - $shape[$pt]{lon}) * ($shape[$pt+1]{lat} - $shape[$pt]{lat}));
			next ZONE if ($comp < 0);
		}

		# None of the boundaries were rejected; thus, we are in this zone
		return $id;
	}

	# All of the zones were rejected; we are not in a zone
	return "";
	
}

1;
