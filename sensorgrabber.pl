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
use IO::Pipe;
use Time::HiRes qw ( time sleep );
use DBI;
use DBD::SQLite;
use Socket;
use IO::Handle;
use Fcntl;
use POSIX "fmod";
use Math::Trig;

use RPiSerial;
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
my ($zonedata, $trackname) = &loadKML($kmlfile);
print "[1;32m[[ Zone data ready! ]][0m\n\n";

print "\n[1;32m[[ Opening FIFO pipe to NodeJS ]][0m\n";
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
my $currentZone = "init";  # Name of current zone (if any)
my $lastZone = "";     # Name of last zone (if any)
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
		$laptime += time - $lasttime;
		$lapdistance += $gpsfeed->{distance};
	}
	$lasttime = time;
	$$lapObj{'lap time'} = $laptime;
	$$lapObj{'lap number'} = $lapsThisSession;

	if ($currentZone ne &whereAmI($$gpsjson{lon}, $$gpsjson{lat}, $zonedata)) {
		if ($currentZone eq "init") {
			# Cold-start setup
			$lapObj = { session=>$session, track=>$trackname, 'full lap'=>0, tick=>[] };
			$laptime = 0;
		}

		if (&whereAmI($$gpsjson{lon}, $$gpsjson{lat}, $zonedata) eq "Driveway") { #FIXME
			$$lapObj{'full lap'} = 0;
		}

		if (&whereAmI($$gpsjson{lon}, $$gpsjson{lat}, $zonedata) eq "Start") {
			# Fresh lap! Do some bookkeeping on the previous lap...
			if ($$lapObj{'full lap'}) {
				$completedLaps++ ;
				%$referenceLap = %$lapObj;
			}

			# ...record it...
			$lapDB->insert($lapObj);

			# ...then set up the new one.
			$lapObj = { session=>$session, track=>$trackname, 'full lap'=>1, tick=>[] };
			$lapsThisSession++;
			$laptime = 0;
			$lapdistance = 0;
		}
		$lastZone = $currentZone;
		$currentZone = &whereAmI($$gpsjson{lon}, $$gpsjson{lat}, $zonedata);
		$ticksInZone = 1;
	}
	else {
		$ticksInZone++;
	}

	select STDOUT;
	if (defined $acceldata[0]) { printf "[Accel: [1;35m%+01.2f/%+01.2f/%+01.2f[0m]", @acceldata; }
	else                       { printf "[Accel: [1;35m--.--/--.--/--.--[0m]"; }


	printf " [Zon: [1;32m%11.11s[0m] [LZn: [1;33m%11.11s[0m] ",
		$currentZone, $lastZone;

	if ($$lapObj{'full lap'} > 0) {
		printf "[Lap: [1;32m%3d[0m] ", $lapsThisSession;
	}
	else {
		printf "[Lap: [1;31m%3d[0m] ", $lapsThisSession;
	}

	printf "[Tim: [1;36m%5.1fs[0m]\n", $laptime;

	push(@{$$lapObj{tick}},
		{
			laptime => $laptime,
			dist => $lapdistance,
			walltime => time,
			lat => $$gpsjson{lat},
			lon => $$gpsjson{lon},
			cz => $currentZone,
			lz => $lastZone,
			speed => $speedMPH,
			tiz => $ticksInZone,
			accelx => $acceldata[0],
			accely => $acceldata[1],
			accelz => $acceldata[2]
		});

	select $fifo; $| = 1;
	
	printf $fifo "lapcompare/%+05.1f\n", ($laptime - $$compareTick{laptime}) if (defined $compareTick);

	printf $fifo "laptime/%s\ncurrentzone/%s\n",
		sprintf("%02d:%04.1f", int($laptime / 60), fmod($laptime, 60)),
		$currentZone;

	printf $fifo "\naccelx/%s\naccely/%s\n", $acceldata[0], $acceldata[1] if (defined $acceldata[0]);

}	




