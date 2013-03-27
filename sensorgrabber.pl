#!/usr/bin/perl

#
# CONFIG
#
my $_configFIFOpath = "./var/sensorgrabber.fifo";
my $_sqlitepath = "./sqlite/datamonster.db";
#
# END CONFIG
#

use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw ( time sleep );
use IO::Handle;
use Fcntl;

use RPiSerial;
use GPSFeed;
use Course;
use Device::BCM2835;

$SIG{'INT'} = 'quit_signal';

#
# Pre-flight
#
my $kmlfile = shift @ARGV;
if (defined $kmlfile && -r "$kmlfile") {
	# Success!
}
else {
	&explode("ERROR: You must supply a KML file with location information as the first argument.\n    Example: $0 myzones.kml\n\n");
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

print "\n[1;32m[[ Preparing accelerometer ]][0m\n";
my $accl = new RPiSerial::ADXL345( cs_broker => $spi_cs_broker, cs_broker_pin => 1, debug => 0);
$accl->initialize() or &explode("FAILURE: The accelerometer failed to initialize\n\n");
print "[1;32m[[ Accelerometer ready! ]][0m\n\n";

print "\n[1;32m[[ Preparing gyroscope ]][0m\n";
my $gyro = new RPiSerial::L3G4200D( cs_broker => $spi_cs_broker, cs_broker_pin => 2, debug => 0);
$gyro->initialize() or &explore("FAILURE: The gyroscope failed to initialize\n");
print "[1;32m[[ Gyroscope ready! ]][0m\n\n";

print "\n[1;32m[[ Preparing ADC ]][0m\n";
my $adc = new RPiSerial::MCP3208( cs_broker => $spi_cs_broker, cs_broker_pin => 3, debug => 0);
$adc->initialize();
print "[1;32m[[ ADC ready! ]][0m\n\n";

print "\n[1;32m[[ Preparing GPS ]][0m\n";
my $gpsfeed = new GPSFeed( debug => 0 );
$_ = $gpsfeed->initialize();
if (! $$_[0]) {
	&explode("GPS failed to initialize: $$_[1]");
}
print "[1;32m[[ GPS ready! ]][0m\n\n";

print "\n[1;32m[[ Loading and parsing zone data ]][0m\n";
my $track = new Course( kmlfile => $kmlfile, debug => 1 );
print "[1;32m[[ Zone data ready! ]][0m\n\n";

print "\n[1;32m[[ Opening FIFO output pipe ]][0m\n";
sysopen(my $fifo, $_configFIFOpath, O_NONBLOCK|O_RDWR)
	or &explode("Couldn't open FIFO pipe: $!");
print "[1;32m[[ FIFO ready! ]][0m\n\n";
$| = 1;

print "\n[1;32m[[ Opening SQLite datafile ]][0m\n";
my $sqlitedb = DBI->connect("dbi:SQLite:dbname=" . $_sqlitepath, "", "") || &explode("SQLite DB unavailable");
print "[1;32m[[ SQLite ready! ]][0m\n\n";

print "\n\n[1;30m================================================================================[0m\n";

#
# Rock on
#

# Values that persist across ticks
my $session = int(time); # Unique identifier for current session
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

	if ($currentzone ne $zoneHistory[0]) {
		#
		# NEW ZONE
		#

		if ($currentzone eq "init") {
			# Cold-start setup
			$lapObj = { session=>$session, track=>$trackname, 'full lap'=>0 };
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
			$lapObj = { session=>$session, track=>$trackname, 'full lap'=>1, tick=>[] };
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
		laptime => $laptime,
		dist => $lapdistance,
		walltime => time,
		gpstime => $gpsfeed->{timestamp},
		lat => $gpsfeed->{lat},
		lon => $gpsfeed->{lon},
		cz => $currentZone,
		lz => $lastZone,
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
	print "\nQuitting!\n\n";

	if (defined $lapDB) {
		print "Writing last lap to database...";
		$$lapObj{'full lap'} = 0;
		$lapDB->insert($lapObj);
		print "[1;32mOK[0m\n";

		print "Closing database connection...";
		undef $lapDB;
		$sqlitedb->disconnect;
		#undef $mongoCollection;
		#undef $mongoConnector;
		print "[1;32mOK[0m\n";
	}

	$gpsfeed->shutdown();
	
	exit 0;
}

sub explode {
	my $message = shift @_;
	printf "\n[1;31m******* EXITING DUE TO ERROR: *******\n[1;37m$message[1;31m\n*************************************\n[0m";
	&quit_signal;
}

sub handleLap {
	my $lapObj = shift;
}

sub handleTick {
	my $tickObj = shift;

	# Write JSON summary to pipe
	select $fifo; $| = 1;
	print $fifo "{ \"tick\":{";
	foreach my $key (keys %$tickObj) {
		printf $fifo "\"%s\":\"%s\",", $key, $$tickObj{$key};
	}
	print $fifo "}}\n";
}
