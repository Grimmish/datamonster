#!/usr/bin/perl

#
# CONFIG
#
my $_serverport = 1992;

#
# END CONFIG
#

use strict;
use warnings;

BEGIN {
	print "[1;32mInitializing...[0m\n";
}

use Data::Dumper;
use Time::HiRes qw ( time sleep );
#use IO::Handle;
use IO::Socket::INET;
use JSON qw ( encode_json );
use Fcntl;

use RPiSerial;
use GPSFeed;
use Course;
use Device::BCM2835;

$SIG{'INT'} = 'quit_signal';

#
# Pre-flight
#
my $dmlfile = shift @ARGV;
if (defined $dmlfile && -r "$dmlfile") {
	# Success!
}
else {
	&explode("ERROR: You must supply a rendered KML file (DML) with location information as the first argument.\n    Example: $0 myzones.dml\n\n");
}

Device::BCM2835::init() || die "Could not init library";
Device::BCM2835::spi_begin();
Device::BCM2835::spi_setBitOrder(Device::BCM2835::BCM2835_SPI_BIT_ORDER_MSBFIRST);
Device::BCM2835::spi_setDataMode(Device::BCM2835::BCM2835_SPI_MODE3);
Device::BCM2835::spi_setChipSelectPolarity(Device::BCM2835::BCM2835_SPI_CS1, LOW);
Device::BCM2835::spi_setClockDivider(Device::BCM2835::BCM2835_SPI_CLOCK_DIVIDER_128);
Device::BCM2835::spi_chipSelect(Device::BCM2835::BCM2835_SPI_CS1);

my $spi_cs_broker = new RPiSerial::SerialDevice(
	rpi_rev     => 2,
	debug       => 0,
	serial_pin  => 16,
	clock_pin   => 18,
	latch_pin   => 22,
	oenable_pin => 15,
	word_length => 8,
	clock_rate  => 1000000
);

print "[1;32m[[ Preparing accelerometer ]][0m\n";
my $accl = new RPiSerial::ADXL345( cs_broker => $spi_cs_broker, cs_broker_pin => 1, debug => 0);
$accl->initialize() or &explode("FAILURE: The accelerometer failed to initialize\n\n");
print "[1;32m[[ Accelerometer ready! ]][0m\n\n";

print "[1;32m[[ Preparing gyroscope ]][0m\n";
my $gyro = new RPiSerial::L3G4200D( cs_broker => $spi_cs_broker, cs_broker_pin => 2, debug => 0);
$gyro->initialize() or &explode("FAILURE: The gyroscope failed to initialize\n");
print "[1;32m[[ Gyroscope ready! ]][0m\n\n";

print "[1;32m[[ Preparing ADC ]][0m\n";
my $adc = new RPiSerial::MCP3208( cs_broker => $spi_cs_broker, cs_broker_pin => 3, debug => 0);
$adc->initialize();
print "[1;32m[[ ADC ready! ]][0m\n\n";

print "[1;32m[[ Loading and parsing zone data ]][0m\n";
my $track = new Course( dmlfile => $dmlfile, debug => 1 );
print "[1;32m[[ Zone data ready! ]][0m\n\n";

print "[1;32m[[ Starting dispatch server ]][0m\n";
my $dispatch = IO::Socket::INET->new(Listen     => 5,
                                     LocalAddr  => 'localhost',
                                     LocalPort  => $_serverport,
                                     Proto      => 'tcp',
                                     Reuse      => 1,
                                     Blocking   => 0) or &explode("FAILURE: Couldn't create TCP socket for dispatch server: $!");
print "[1;32m[[ Dispatch server ready! ]][0m\n\n";
my @clients;

print "[1;32m[[ Preparing GPS ]][0m\n";
my $gpsfeed = new GPSFeed( debug => 1 );
$_ = $gpsfeed->initialize();
if (! $$_[0]) {
	&explode("GPS failed to initialize: $$_[1]");
}
print "[1;32m[[ GPS ready! ]][0m\n\n";

my $session = int(time); # Unique identifier for current session

print "[1;30m================================================================================[0m\n";

#
# Rock on
#

# Values that persist across ticks
my $lapObj = {}; # Lap data object
my $referenceLap = {}; # Comparative lap data object
my $lapsThisSession = 1;
my $lasttime = 0;  # Used to determine delay since last position update
my $zoneHistory = [ "init", "" ];  # Last two zones
my $ticksInZone = 1;  # How many ticks have been recorded since entering the current zone
my $completedLaps = 0;  # The number of "full laps" completed in this session
my $laptime = 0.0; # In tenths/second
my $lapdistance = 0; # In feet

while (1) {
	$gpsfeed->update();
	my $readaccl = $accl->measure();
	my $readgyro = $gyro->measure();
	
	#my $compareTick = &compareTick($referenceLap, $$gpsjson{lon}, $$gpsjson{lat});

	if ($lasttime > 0) {
		$laptime += $gpsfeed->{timestamp} - $lasttime;
		$lapdistance += $gpsfeed->{distance};
	}
	$lasttime = $gpsfeed->{timestamp};
	$$lapObj{'lap time'} = $laptime;
	$$lapObj{'lap number'} = $lapsThisSession;

	my $currentzone = $track->whereAmI($gpsfeed->{lon}, $gpsfeed->{lat});

	if ($currentzone ne $$zoneHistory[0]) {
		#
		# NEW ZONE
		#

		if ($$zoneHistory[0] eq "init") {
			# Cold-start setup
			$lapObj = { session=>$session, track=>$track->{trackname}, 'full lap'=>0 };
			$laptime = 0;
		}

		###########
		### FIXME
		###
		### If this is an off-track zone (pit area, etc), flag this lap as not useable
		###
		if ($currentzone eq "Driveway") {
			$$lapObj{'full lap'} = 0;
		}

		###########
		### FIXME
		###
		### If this is the start/stop line, take appropriate action
		###
		if ($currentzone eq "Start") {
			# Fresh lap! Do some bookkeeping on the previous lap...
			if ($$lapObj{'full lap'}) {
				$completedLaps++ ;
			}

			# ...record it...
			&handleLap($lapObj);

			# ...then set up the new one.
			$lapObj = { session=>$session, track=>$track->{trackname}, 'full lap'=>1, tick=>[] };
			$lapsThisSession++;
			$laptime = 0;
			$lapdistance = 0;
		}
		pop(@$zoneHistory);
		unshift(@$zoneHistory, $currentzone);

		$ticksInZone = 1;
	}
	else {
		$ticksInZone++;
	}

	&handleTick({
		session => $session,
		fulllap => $$lapObj{'full lap'},
		lapnumber => $lapsThisSession,
		laptime => $laptime,
		dist => $lapdistance,
		walltime => time,
		gpstime => $gpsfeed->{timestamp},
		lat => $gpsfeed->{lat},
		lon => $gpsfeed->{lon},
		cz => $$zoneHistory[0],
		lz => $$zoneHistory[1],
		speed => $gpsfeed->{speedmph},
		tiz => $ticksInZone,
		accelx => $$readaccl[0],
		accely => $$readaccl[1],
		accelz => $$readaccl[2],
		gyrox => $$readgyro[0],
		gyroy => $$readgyro[1],
		gyroz => $$readgyro[2]
	});

}	



##                                          ##
##  (Subs)                                  #
##                                        ####
##                  #                     ####
##                  #                ###############
##       ###      ##################################################
##       ####  ########################################################
##       ################################################################
##       ####  ########################################################
##       ##       ##################################################
##
&explode("Abnormal end - should not be here!\n");

sub quit_signal {
	select STDOUT;
	print "\nQuitting!\n\n";

	$gpsfeed->shutdown() if (defined $gpsfeed);
	
	exit 0;
}

sub explode {
	my $message = shift @_;
	printf "\n[1;31m******* EXITING DUE TO ERROR: *******\n[1;37m$message[1;31m\n*************************************\n[0m";
	&quit_signal;
}

sub handleLap {
	my $lapObj = shift;
	foreach my $c (@clients) {
		$c->print(encode_json($lapObj) . "\n");
	}
}

sub handleTick {
	my $tickObj = shift;

	&refreshClients;
	foreach my $c (@clients) {
		$c->print(encode_json($tickObj) . "\n");
	}

	# Print to screen
	select STDOUT;
	printf "[Accel: [1;35m%+01.2f/%+01.2f[0m]", $$tickObj{accelx}, $$tickObj{accely}; 
	printf " [Zon: [1;32m%11.11s[0m] [TiZ: [1;34m%3d[0m] [LZn: [1;33m%11.11s[0m] ", $$tickObj{cz}, $$tickObj{tiz}, $$tickObj{lz};
	if ($$tickObj{fulllap} > 0) { printf "[Lap: [1;32m%3d[0m] ", $$tickObj{lapnumber}; }
	else                          { printf "[Lap: [1;31m%3d[0m] ", $$tickObj{lapnumber}; }
	printf "[Tim: [1;36m%5.2fs[0m]\n", $$tickObj{laptime};
}

sub refreshClients {
	# Grab another (potential) client. It might be empty, in which case it'll be pruned off below
	push(@clients, scalar $dispatch->accept());

	# Prune out disconnected clients (including, potentially, the empty connection we just PUSHed in)
	foreach my $c (@clients) {
		$c = undef unless ($c && $c->connected());
	}

	# Drop UNDEF clients
	my @rebuild = @clients;
	@clients = ();
	for (@rebuild) {
		push(@clients, $_) if ($_);
	}
}

