#
####   RPiSerial   ####
#
# A few object classes to simplify low-level serial functions on the
# Raspberry Pi
#


#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------        SerialDevice       ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package RPiSerial::SerialDevice;
use warnings;
use strict;
use Carp;
use Device::BCM2835;
use Time::HiRes qw( nanosleep );
use Math::Round;

use Data::Dumper;


sub new {
	my $package = shift @_;
	my %init = @_;
	my $croak;

	# Required
	foreach my $i (qw/serial_pin clock_pin word_length/) {
		if (! defined $init{$i}) {
			$croak .= "Failed to initialize new \"$package\": No '" . $i . "' defined\n";
		}
		if (defined $init{$i} && $init{$i} < 1) {
			$croak .= "Failed to initialize new \"$package\": Invalid value for '" . $i . "'\n";
		}
	}

	croak($croak) if $croak;

	# Optional, with defaults
	$init{rpi_rev} = 2            unless (defined $init{rpi_rev} && $init{rpi_rev} == 1);
	$init{latch_pin} = 0          unless (defined $init{latch_pin} && $init{latch_pin} > 0);
	$init{oenable_pin} = 0        unless (defined $init{oenable_pin} && $init{oenable_pin} > 0);
	$init{clock_rate} = 1000000   unless (defined $init{clock_rate} && $init{clock_rate} > 0);
	$init{oenable_logic} = 0      unless (defined $init{oenable_logic} && $init{oenable_logic} > 0);
	$init{debug} = undef          unless (defined $init{debug} && $init{debug} > 0);
	
	# Always derived from clock_rate. Also used for hold times on latch, oenable, etc
	$init{clock_wait_ns} = round(1 / $init{clock_rate} / 2 * 10**9);

	no strict 'refs';
	# Replace the physical pin number with BCM firmware pin number
	foreach my $i (qw/ serial_pin clock_pin latch_pin oenable_pin /) {
		next unless ($init{$i}); # Skip the zeroes

		$init{$i} = &{sprintf("Device::BCM2835::RPI_GPIO_P1_%02d", $init{$i})};
		# In RPi rev1, physical pins 3 and 5 mapped to firmware pins 0 and 1.
		# In RPi rev2, the same physical pins map to firmware pins 2 and 3
		if ($init{rpi_rev} == 2 && $init{$i} < 2) {
			$init{$i} += 2;
		}

		# Set pin to output mode
		Device::BCM2835::gpio_fsel($init{$i}, Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
	}
	use strict 'refs';

	bless \%init => $package;
}

sub describeYourself {
	my $self = shift;
	my $myname = shift;
	printf "__%s__** Class: [1;32m%s[0m\n", $myname, blessed($self);
	print Dumper($self);
}

sub sendWord {
	my $self = shift;
	my $word = shift;

	my $debug = $self->{debug};

	print "[1;30m____** Serial :: Sending: 0b" if $debug;
	for (my $x = ($self->{word_length} - 1); $x > -1; $x--) {
		if ($word & (1<<$x)) { Device::BCM2835::gpio_set($self->{serial_pin}); print "1" if $debug; }
		else                 { Device::BCM2835::gpio_clr($self->{serial_pin}); print "0" if $debug; }
		Device::BCM2835::gpio_set($self->{clock_pin});
		nanosleep($self->{clock_wait_ns});
		Device::BCM2835::gpio_clr($self->{clock_pin});
		nanosleep($self->{clock_wait_ns});
	}
	if ($self->{latch_pin} > 0) {
		Device::BCM2835::gpio_set($self->{latch_pin});
		nanosleep($self->{clock_wait_ns});
		Device::BCM2835::gpio_clr($self->{latch_pin});
		nanosleep($self->{clock_wait_ns});
		print " (+latched)" if $debug;
	}
	print "[0m\n" if $debug;
}

sub outputEnable {
	my $self = shift;
	my $debug = $self->{debug};
	if ($self->{oenable_pin} > 0) {
		if ($self->oenable_logic > 0) { Device::BCM2835::gpio_set($self->{oenable_pin}); print "[1;30m____** Serial :: Pulled oenable HIGH to enable output[0m\n" if $debug; }
		else                          { Device::BCM2835::gpio_clr($self->{oenable_pin}); print "[1;30m____** Serial :: Pulled oenable LOW to enable output[0m\n" if $debug; }
		nanosleep($self->{clock_wait_ns});
	}
}

sub outputDisable {
	my $self = shift;
	my $debug = $self->{debug};
	if ($self->{oenable_pin} > 0) {
		if ($self->oenable_logic > 0) { Device::BCM2835::gpio_clr($self->{oenable_pin}); print "[1;30m____** Serial :: Pulled oenable LOW to disable output[0m\n" if ($debug); }
		else                          { Device::BCM2835::gpio_set($self->{oenable_pin}); print "[1;30m____** Serial :: Pulled oenable HIGH to disable output[0m\n" if ($debug); }
		nanosleep($self->{clock_wait_ns});
	}
}


#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------          SPIDevice        ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package RPiSerial::SPIDevice;

sub new {
	my $package = shift @_;
	my %init = @_;
	my $croak;

	# The RaspberryPi only supports 2 CS pins in SPI mode, so this assumes that you're using
	# a logic inverter and a shift register in a clever way to get more pins. Here we pass in
	# that shift register object (itself a SerialDevice), and which of its pins is connected
	# to your SPI Device.

	# Required
	foreach my $i (qw/ cs_broker cs_broker_pin /) {
		if (! defined $init{$i}) { $croak .= "Failed to initialize new \"$package\": No '" . $i . "' defined\n"; }
	}
	if (defined $init{cs_broker} && ref $init{cs_broker} ne "RPiSerial::SerialDevice") {
		$croak .= "The 'cs_broker' property must be a RPiSerial::SerialDevice object\n";
	}
	if (defined $init{cs_broker_pin} && ($init{cs_broker_pin} < 1 || $init{cs_broker_pin} > 8)) {
		$croak .= "The 'cs_broker_pin' property must be an integer between 1 and 8 inclusive\n";
	}

	croak($croak) if $croak;

	# Optional, with defaults
	$init{debug} = undef          unless (defined $init{debug} && $init{debug} > 0);

	bless \%init => $package;
}

sub tradeWords {
	my $self = shift;
	my $words = shift;
	my $debug = $self->{debug};
	# Prep the shift register defined as $cs_broker so that when the BCM2835 library
	# pulls the CS pin low, it will actually be triggering the output-enable pin of
	# the $cs_broker such that only our SPIDevice is pulled low. BATSHIT EVERYWHERE.
	$self->{cs_broker}->sendWord(1 << ($self->{cs_broker_pin}-1));

	# Now for the actual transmission
	my @sendWords;
	push(@sendWords, sprintf("%02X", $_)) for (@$words); 
	
	my $data = pack('H2' x scalar(@$words), @sendWords);

	print "[1;30m____** SPI :: Sending: " . (join(' ', unpack('H2' x scalar(@$words), $data))) . "[0m\n" if $debug;
	Device::BCM2835::spi_transfern($data);
	print "[1;30m____** SPI :: Received: " . (join(' ', unpack('H2' x scalar(@$words), $data))) . "[0m\n" if $debug;

	my @readWords;
	push(@readWords, hex($_)) foreach unpack('H2' x scalar(@$words), $data);
	return \@readWords;
}


#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------           ADXL345         ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package RPiSerial::ADXL345;
our @ISA = qw/RPiSerial::SPIDevice/;
use Math::Round;

sub initialize {
	my $self = shift;
	my $debug = $self->{debug};

	# Add some new properties
	$self->{bw_rate}     = 0b00001101 ; # 1600Hz datarate/800Hz bandwidth, 90uA
	$self->{data_format} = 0b00001011 ; # 4-wire, MSB, full-range (+/- 16g)
	$self->{int_enable}  = 0b00000000 ; # Shut off all interrupts
	$self->{fifo_ctl}    = 0b00000000 ; # Shut off FIFOs too
	$self->{power_ctl}   = 0b00001000 ; # No sleep, no standby. Wake up!
	
	print "[1;30m___** ADXL345 :: Writing init settings\n" if $debug;
	$self->tradeWords( [0x2C, $self->{bw_rate}] );
	$self->tradeWords( [0x31, $self->{data_format}] );
	$self->tradeWords( [0x2E, $self->{int_enable}] );
	$self->tradeWords( [0x38, $self->{fifo_ctl}] );
	$self->tradeWords( [0x2D, $self->{power_ctl}] );

	print "[1;30m___** ADXL345 :: Reading back init for verification[0m\n" if $debug;
	my $initCheck;
	$initCheck = $self->tradeWords([0x2C | 0b10000000, 0]);
	return undef unless ($$initCheck[1] == $self->{bw_rate});
	$initCheck = $self->tradeWords([0x31 | 0b10000000, 0]);
	return undef unless ($$initCheck[1] == $self->{data_format});
	$initCheck = $self->tradeWords([0x2E | 0b10000000, 0]);
	return undef unless ($$initCheck[1] == $self->{int_enable});
	$initCheck = $self->tradeWords([0x38 | 0b10000000, 0]);
	return undef unless ($$initCheck[1] == $self->{fifo_ctl});
	$initCheck = $self->tradeWords([0x2D | 0b10000000, 0]);
	return undef unless ($$initCheck[1] == $self->{power_ctl});
		
	print "[1;30m___** ADXL345 :: Zeroing out previous calibration[0m\n" if $debug;
	$self->tradeWords([0x1E, 0]);
	$self->tradeWords([0x1F, 0]);
	$self->tradeWords([0x20, 0]);

	print "[1;30m___** ADXL345 :: Taking new calibration measurements[0m\n" if $debug;
	my @samples = (0, 0, 0);
	foreach (1 .. 20) {
		my $reading = $self->measure;
		# Need to upscale the results from measure() from g's to LSBs (which are 1/256 of a g)
		for (my $z=0;$z<3;$z++) { $samples[$z] += $$reading[$z] * 256; }
	}
	$_ = round($_ / 20) foreach (@samples);
	printf "[1;30m___** ADXL345 :: Average readings (in LSBs) - X:%d  Y:%d  Z:%d[0m\n", @samples if $debug;

	print "[1;30m___** ADXL345 :: Calculating calibration offset[0m\n" if $debug;
	my @offsetLSB;
	$offsetLSB[0] = round($samples[0] / 4) * -1;
	$offsetLSB[1] = round($samples[1] / 4) * -1;
	$offsetLSB[2] = round( ($samples[2] - 256) / 4) * -1; # Assume Z-axis is vertical, where 'neutral' is 1.00
	printf "[1;30m___** ADXL345 :: Required adjustments (in adjustment-units) - X:%+d  Y:%+d  Z:%+d[0m\n", @offsetLSB if $debug;

	print "[1;30m___** ADXL345 :: Writing new calibration to offset registers[0m\n" if $debug;
	$self->tradeWords([0x1E, unpack('C', pack('c', $offsetLSB[0]))]);
	$self->tradeWords([0x1F, unpack('C', pack('c', $offsetLSB[1]))]);
	$self->tradeWords([0x20, unpack('C', pack('c', $offsetLSB[2]))]);
	
	return 1;
}

sub measure {
	my $self = shift;
	my $reading = $self->tradeWords([0x32 | 0b11000000, 0, 0, 0, 0, 0, 0]);
	my @samples = (
		unpack('s', pack('S', ($$reading[2]<<8) | $$reading[1])) / 256,
		unpack('s', pack('S', ($$reading[4]<<8) | $$reading[3])) / 256,
		unpack('s', pack('S', ($$reading[6]<<8) | $$reading[5])) / 256
	);
	return \@samples;
}



#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------          L3G4200D         ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package RPiSerial::L3G4200D;
our @ISA = qw/RPiSerial::SPIDevice/;

sub initialize {
	my $self = shift;
	my $debug = $self->{debug};

	# Add some new properties
	$self->{ctrl_reg1} = 0b11011111 ; # 800Hz output datarate, cut-off=35 (?), enable all axis
	$self->{ctrl_reg2} = 0b00000011 ; # 8Hz cut-off
	$self->{ctrl_reg4} = 0b00010000 ; # 4-wire, MSB, mid-range (500 degrees/sec)
	$self->{ctrl_reg5} = 0b10000000 ; # Reboot, disable all FIFOs and high-pass filters

	# Read the model ID to verify communications
	my $initCheck = $self->tradeWords([0x0F | 0b10000000, 0, 0, 0, 0]);
	return undef unless ($$initCheck[1] == 0xd3);

	print "[1;30m___** L3G4200D :: Writing init settings[0m\n" if $debug;
	$self->tradeWords( [0x20, $self->{ctrl_reg1}] );
	$self->tradeWords( [0x21, $self->{ctrl_reg2}] );
	$self->tradeWords( [0x23, $self->{ctrl_reg4}] );

	print "[1;30m___** L3G4200D :: Reading back init for verification[0m\n" if $debug;
	$initCheck = $self->tradeWords( [0x20 | 0b10000000, 0] );
	return undef unless ($$initCheck[1] == $self->{ctrl_reg1});
	$initCheck = $self->tradeWords( [0x21 | 0b10000000, 0] );
	return undef unless ($$initCheck[1] == $self->{ctrl_reg2});
	$initCheck = $self->tradeWords( [0x23 | 0b10000000, 0] );
	return undef unless ($$initCheck[1] == $self->{ctrl_reg4});
	
	return 1;
}

sub measure {
	my $self = shift;
	my $reading = $self->tradeWords([0x28 | 0b11000000, 0, 0, 0, 0, 0, 0]);
	my @samples = (
		# The scaling factor at the end is dictated by the sensitivity - check the datasheet
		unpack('s', pack('S', ($$reading[2]<<8) | $$reading[1])) * 0.0175,
		unpack('s', pack('S', ($$reading[4]<<8) | $$reading[3])) * 0.0175,
		unpack('s', pack('S', ($$reading[6]<<8) | $$reading[5])) * 0.0175
	);
	return \@samples;
}


#--------------------------------------------------#
#--------------------------------------------------#
#-----------                           ------------#
#-----------                           ------------#
#-----------           MCP3208         ------------#
#-----------                           ------------#
#-----------                           ------------#
#--------------------------------------------------#
#--------------------------------------------------#
package RPiSerial::MCP3208;
our @ISA = qw/RPiSerial::SPIDevice/;

sub initialize {
	my $self = shift;
	my $debug = $self->{debug};

	# Not really any initialization to speak of; just add a new property
	$self->{single_ended} = 1 ; # Set to 0 or undef to treat inputs
	                            # as pseudo-differential pairs

	return 1;
}

sub measure {
	my $self = shift;
	my $debug = $self->{debug};
	my $inputChannel = shift;
	return undef unless ($inputChannel > 0 && $inputChannel < 9);
	my $address = 1<<10 | ($inputChannel-1)<<6 ;
	if ($self->{single_ended}) { $address |= 1<<9; }
	printf "[1;30m____** MCP3208 :: 16-bit address string: 0b%016b[0m\n", $address if $debug;
	my $reading = $self->tradeWords( [ $address>>8, $address % (1<<8), 0 ] ); 
	return ( ($$reading[1]<<8) | $$reading[2] ) % 4096;
}

1;
