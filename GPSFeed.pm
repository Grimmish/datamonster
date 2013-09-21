#
####   GPSFeed   ####
#
# A class to simply pulling raw GPS NMEA data
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
use Time::Local 'timelocal_nocheck';
use FileHandle;
use Data::Dumper;

sub new {
	my $package = shift @_;
	my %init = @_;

	unless (defined $init{devpath} && -r $init{devpath}) {
		croak("The GPS device path was not specified, or the given path is not readable");
	}

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

	print "Opening GPS device file for reading...\n" if $debug;
	$self->{devfeed} = FileHandle->new("< " . $self->{devpath});

	if (! defined $self->{devfeed}) {
		return [ undef, "Failed to open GPS device path: $@" ];
	}

	my $gpstimeout = 10;
	print "Waiting for usable NMEA position sentence ($gpstimeout secs max)...\n" if $debug;
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm $gpstimeout;
		my $grabline = "";
		until ($grabline =~ /^\$GPRMC,.*?,A,/) {
			$grabline = $self->{devfeed}->getline();
		}
		alarm 0;

		my $parsedNMEA = $self->decodeNMEA($grabline);
		$self->{lon} = $$parsedNMEA{lon};
		$self->{lat} = $$parsedNMEA{lat};
		$self->{speedmph} = $$parsedNMEA{speed};
		$self->{timestamp} = $$parsedNMEA{"time"};
	};
	if ($@) {
		return [ undef, "Waited $gpstimeout seconds, but got no usable information location from the GPS" ];
	}
	else {
		printf "[1;32mLon[[1;37m%+3.6f[1;32m], Lat[[1;37m%+3.6f[1;32m], Time[[1;37m%s[1;32m][0m\n", $self->{lon}, $self->{lat}, scalar(localtime($self->{timestamp})) if $debug;
	}

	return [ 1 ] ;
}

sub update {
	my $self = shift;

	my $parsedNMEA;
	my $rawtext = $self->{devfeed}->getline();

	# The GPS throws lots of "sentences" for stuff like status, number
	# of satellites in view, etc. We only care about $GPRMC lines, which
	# are position fixes, so we may need to grab a few lines before we
	# get what we want.
	until ($parsedNMEA) {
		$parsedNMEA = $self->decodeNMEA($self->{devfeed}->getline());
	}

	$self->{lon} = $$parsedNMEA{lon};
	$self->{lat} = $$parsedNMEA{lat};
	$self->{speedmph} = $$parsedNMEA{speed};
	$self->{distance} = ($$parsedNMEA{"time"} - $self->{timestamp}) * $self->{speedmph} * 1.46667; # MPH to feet

	$self->{timestamp} = $$parsedNMEA{"time"};
}

sub parseRFC3339 {
	my $self = shift;
	my $rfcdate = shift;

	$rfcdate =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d\.?\d*)[A-Z]$/;
	return Time::Local::timegm(0, $5, $4, $3, $2 - 1, $1) + $6;
}

sub decodeNMEA {
	my $self = shift;
	my $rawNMEA = shift;

	unless ($rawNMEA =~ /^\$GPRMC,.*?,A,/) {
		return undef;
	}

	chomp ($rawNMEA);
	my $return = {};

	my @nmea = split(',', $rawNMEA);

	#
	# NMEA RMC sentences: http://aprs.gids.nl/nmea/#rmc 
	#
	my $x = $nmea[3];
	$x =~ s/^\d+(\d\d\.\d+)$/$1/;
	if ($nmea[4] =~ /n/i) { $$return{lon} = ($nmea[3] - $x) + ($x / 60); }
	else                  { $$return{lon} = 1 - (($nmea[3] - $x) + ($x / 60)); }

	$x = $nmea[5];
	$x =~ s/^\d+(\d\d\.\d+)$/$1/;
	if ($nmea[6] =~ /w/i) { $$return{lat} = ($nmea[5] - $x) + ($x / 60); }
	else                  { $$return{lat} = 1 - (($nmea[5] - $x) + ($x / 60)); }

	($nmea[9] . $nmea[1]) =~ /(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d\.?\d*)/;
	$$return{"time"} = Time::Local::timegm(0, $5, $4, $1, $2 - 1, $3) + $6;

	$$return{speed} = $nmea[7] * 1.15078;

	return $return;
}

sub shutdown {
	my $self = shift;
	my $debug = $self->{debug};

	print "Closing GPS device feed..." if $debug;
	if ($self->{gpsfeed}->close()) { print "[1;32mOK[0m\n" if $debug; }
	else                           { print "[1;31mFailed![0m\n" if $debug; }
}

1;
