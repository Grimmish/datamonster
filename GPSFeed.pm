#
####   Location   ####
#
# A class to simply location functions
#

package Location::GPSFeed;
use warnings;
use strict;
use Carp;
use IO::Socket::INET;
use JSON qw( decode_json );
use Math::Trig;

sub new {
	my $package = shift @_;
	my %init = @_;

	$init{debug} = undef unless (defined $init{debug} && $init{debug} > 0);

	bless \%init => $package;
}

sub initialize {
	my $self = shift;
	my $debug = $self->{debug};

	print "Connecting to GPSd..." if $debug;
	$self{gpsd} = IO::Socket::INET->new('localhost:2947')
		or return [ undef, "Could not connect to GPSd on localhost:2947: $@" ];
	print "[1;32mOK[0m\n" if $debug;

	print "Validating GPSd version...";
	my $greeting = <$self{gpsd}>;
	my $json = decode_json($greeting);
	if ($json) { print "[1;32m", $$json{release}, "[0m\n" if $debug; }
	else       { return [ undef, "Made connection to GPSd, but did not receive greeting string" ]; } 

	print "Activating GPS data feed..." if $debug;
	print $self{gpsd} "?WATCH={\"enable\":true,\"json\":true}\n";
	until ($$json{class} eq "DEVICES") {
		my $rawtext = <$self{gpsd}>;
		$json = decode_json($rawtext);
	}

	if (scalar @{$$json{devices}} == 0) {
		return [ undef, "There is no (functional) GPS device connected to the system" ];
	}
	else {
		my $gpsdev = shift @{$$json{devices}};

		unless (defined ($$gpsdev{activated})) {
			return [ undef, "There is no GPS device connected to the system" ];
		}

		printf "[1;32m%s[0m\n", $$gpsdev{path} . " @ " . $$gpsdev{bps} . "bps" if $debug;
	}

	my $gpstimeout = 20;
	print "Waiting for good data ($gpstimeout secs max)..." if $debug;
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm $gpstimeout;
		until ($$json{mode} && $$json{mode} == 3) {
			my $rawtext = <$self{gpsd}>;
			$json = decode_json($rawtext);
		}
		alarm 0;
	};
	if ($@) {
		return [ undef, "Waited $gpstimeout seconds, but got no usable information location from the GPS" ];
	}
	else {
		printf "[1;32mLon[[1;37m%3.6f°[1;32m], Lat[[1;37m%3.6f°[1;32m], Alt[[1;37m%3.0fft[1;32m][0m\n", $$json{lon}, $$json{lat}, $$json{alt} * 3.28084 if $debug;
	}
	
	return [ 1 ] ;
}

sub loadKML {
	my $self = shift;
	my $debug = $self->{debug};

	my $returnset = {};
	my $trackname;
	

