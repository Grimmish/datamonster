#!/usr/bin/perl

#
# Demonstration of using the classes from RPiSerial.pm to
# do useful work.
#

use warnings;
use strict;
use RPiSerial;
use Device::BCM2835;
use Time::HiRes qw( time sleep usleep );

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

my $accl = new RPiSerial::ADXL345( cs_broker => $spi_cs_broker, cs_broker_pin => 1, debug => 0);
$accl->initialize() or die "ABORTING, couldn't initialize the accelerometer\n";

my $gyro = new RPiSerial::L3G4200D( cs_broker => $spi_cs_broker, cs_broker_pin => 2, debug => 0);
$gyro->initialize() or die "ABORTING, couldn't initialize the gyroscope\n";

my $adc = new RPiSerial::MCP3208( cs_broker => $spi_cs_broker, cs_broker_pin => 3, debug => 0);

my $samples = 120;
my $sleepwait = 0.1;

for (1 .. $samples) {
	printf "Reading:    ";
	my $temp = $adc->measure(8);
	printf "ADC: [1;35m%4d/4096[0m     ", $temp;
	$temp = $gyro->measure();
	printf "Gyro: [1;36mX:%4.0f Y:%4.0f Z:%4.0f[0m     ", @$temp;
	$temp = $accl->measure();
	printf "Accl: [1;34mX:%+4.1f Y:%+4.1f Z:%+4.1f[0m", @$temp;
	print "\n";
	sleep ($sleepwait);
}

Device::BCM2835::spi_end();
exit 0;
