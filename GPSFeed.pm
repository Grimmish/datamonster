#
####   GPSFeed   ####
#
# A class to simply working with GPSd
#

#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------           GPSFeed         ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package GPSFeed;
use warnings;
use strict;
use Carp;
use IO::Socket::INET;
use JSON qw( decode_json );
use Time::Local 'timelocal_nocheck';

sub new {
	my $package = shift @_;
	my %init = @_;

	$init{debug} = undef unless (defined $init{debug} && $init{debug} > 0);

	$init{lon} = 0;
	$init{lat} = 0;
	$init{timestamp} = 0;
	$init{speedmph} = 0;
	$init{distance} = 0;

	bless \%init => $package;
}

sub initialize {
	my $self = shift;
	my $debug = $self->{debug};

	print "Connecting to GPSd..." if $debug;
	$self->{gpsd} = IO::Socket::INET->new('localhost:2947')
		or return [ undef, "Could not connect to GPSd on localhost:2947: $@" ];
	print "[1;32mOK[0m\n" if $debug;

	print "Validating GPSd version...";
	my $greeting = $self->{gpsd}->getline();
	my $json = decode_json($greeting);
	if ($json) { print "[1;32m", $$json{release}, "[0m\n" if $debug; }
	else       { return [ undef, "Made connection to GPSd, but did not receive greeting string" ]; } 

	print "Activating GPS data feed..." if $debug;
	$self->{gpsd}->print("?WATCH={\"enable\":true,\"json\":true}\n");
	until ($$json{class} eq "DEVICES") {
		my $rawtext = $self->{gpsd}->getline();
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
			my $rawtext = $self->{gpsd}->getline();
			$json = decode_json($rawtext);
		}
		alarm 0;
	};
	if ($@) {
		return [ undef, "Waited $gpstimeout seconds, but got no usable information location from the GPS" ];
	}
	else {
		printf "[1;32mLon[[1;37m%+3.6f°[1;32m], Lat[[1;37m%+3.6f°[1;32m], Alt[[1;37m%3.0fft[1;32m][0m\n", $$json{lon}, $$json{lat}, $$json{alt} * 3.28084 if $debug;
	}
	
	$self->{lon} = $$json{lon};
	$self->{lat} = $$json{lat};
	$self->{speedmph} = $$json{speed} * 2.23694;
	$self->{timestamp} = $self->parseRFC3339($$json{"time"});

	return [ 1 ] ;
}

sub refresh {
	my $self = shift;

	my $rawtext = $self->{gpsd}->getline();
	my $gpsjson = decode_json($rawtext);

	# GPSd occasionally transmits a status update instead of a location. Fast-forward
	# until we get a location update (if necessary).
	until ($$gpsjson{class} eq "TPV") {
		$rawtext = $self->{gpsd}->getline();
		$gpsjson = decode_json($rawtext);
	}

	$self->{lon} = $$gpsjson{lon};
	$self->{lat} = $$gpsjson{lat};
	$self->{speedmph} = $$gpsjson{speed} * 2.23694;
	$self->{distance} = ($self->parseRFC3339($$gpsjson{"time"}) - $self->{timestamp}) * $self->{speedmph} * 1.46667; # MPH to feet

	$self->{timestamp} = $self->parseRFC3339($$gpsjson{"time"});
}

sub parseRFC3339 {
	my $self = shift;
	my $rfcdate = shift;

	$rfcdate =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d\.?\d*)[A-Z]$/;
	return Time::Local::timegm($6, $5, $4, $3, $2 - 1, $1);
}

sub shutdown {
	my $self = shift;
	my $debug = $self->{debug};
	print "Cancelling GPSd WATCH..." if $debug;
	$self->{gpsd}->print("?WATCH={\"enable\":false}\n");
	print "[1;32mOK[0m\n" if $debug;

	print "Dropping GPSd connection..." if $debug;
	if ($self->{gpsd}->close()) { print "[1;32mOK[0m\n" if $debug; }
	else                        { print "[1;31mFailed![0m\n" if $debug; }
}

1;
