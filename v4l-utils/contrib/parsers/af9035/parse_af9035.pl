#!/usr/bin/perl
use strict;
use Getopt::Long;

#   Copyright (C) 2014 Mauro Carvalho Chehab
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, version 2 of the License.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
# This small script parses USB dumps generated by several drivers,
# decoding USB bits.
#
# To use it, do:
# dmesg | ./parse_usb.pl
#
# Also, there are other utilities that produce similar outputs, and it
# is not hard to parse some USB analyzers log into the expected format.
#

my $debug = 0;
my $show_timestamp = 0;
my $hide_ir;
my $hide_fw;
my $hide_rd;
my $hide_wr;
my $hide_rw;
my $hide_i2c_rd;
my $hide_i2c_wr;
my $hide_i2c_rw;
my $hide_errors;
my $help;

my $helpmsg = "Use $0 [--debug] [--help] [--show_timestamp] [--hide-ir] [--hide-fw] [--hide-rd] [--hide-wr] [--hide-rw] [--hide-i2c-rd] [--hide-i2c-wr] [--hide-i2c-rw] [--hide-errors]\n";
my $argerr = "Invalid arguments.\n$helpmsg";

GetOptions(
	'show_timestamp' => \$show_timestamp,
	'hide_ir|hide-ir|hide-rc|hide_rc' => \$hide_ir,
	'hide_fw|hide-fw' => \$hide_fw,
	'hide_rd|hide-rd' => \$hide_rd,
	'hide_wr|hide-wr' => \$hide_wr,
	'hide_wr|hide-rw' => \$hide_rw,
	'hide_i2c_rd|hide-i2c-rd' => \$hide_i2c_rd,
	'hide_i2c_wr|hide-i2c-wr' => \$hide_i2c_wr,
	'hide_i2c_rw|hide-i2c-rw' => \$hide_i2c_rw,
	'hide_errors|hide-errors' => \$hide_errors,
	'debug|v|d' => \$debug,
	'h|help' => \$help,
) or die $argerr;

if ($help) {
	print $helpmsg;
	exit;
}

if ($hide_rw) {
	$hide_rd = 1;
	$hide_wr = 1;
}

if ($hide_i2c_rw) {
	$hide_i2c_rd = 1;
	$hide_i2c_wr = 1;
}

my $ctrl_ep = 0x02;
my $resp_ep = 0x81;

my %cmd_map = (
	0x00 => "CMD_MEM_RD",
	0x01 => "CMD_MEM_WR",
	0x02 => "CMD_I2C_RD",
	0x03 => "CMD_I2C_WR",
	0x04 => "CMD_EEPROM_READ",
	0x05 => "CMD_EEPROM_WRITE",
	0x18 => "CMD_IR_GET",
	0x21 => "CMD_FW_DL",
	0x22 => "CMD_FW_QUERYINFO",
	0x23 => "CMD_FW_BOOT",
	0x24 => "CMD_FW_DL_BEGIN",
	0x25 => "CMD_FW_DL_END",
	0x29 => "CMD_FW_SCATTER_WR",
	0x2a => "CMD_GENERIC_I2C_RD",
	0x2b => "CMD_GENERIC_I2C_WR",
);

my @stack;

sub print_send_recv($$$$$$)
{
	my ( $timestamp, $ep, $len, $seq, $status, $payload ) = @_;

	my $data = pop @stack;
	if (!$data) {
		return if ($hide_errors);
		$payload = ", recv_bytes = $payload" if ($payload && !($payload =~ /ERROR/));
		printf "Missing control cmd:\n";
		printf("\t%sRECV: len=%d, seq=%d, status=%d%s\n",
			$timestamp, $len, $seq, $status, $payload);
		return;
	}

	my ( $ctrl_ts, $ctrl_ep, $ctrl_len, $ctrl_seq, $ctrl_mbox, $ctrl_cmd, @ctrl_bytes ) = @$data;

	if ($len && !$status && $ctrl_seq != $seq) {
		return if ($hide_errors);
		$payload = ", recv_bytes = $payload" if ($payload && !($payload =~ /ERROR/));
		printf "Wrong sequence number:\n";
		printf("\t%sSEND: len=%d, seq %d, mbox=0x%02x, cmd=%s%s",
			$ctrl_ts, $ctrl_len, $ctrl_seq, $ctrl_mbox, $ctrl_cmd, $payload);
		$timestamp = "($timestamp)" if ($timestamp);
		printf(" RECV: len=%d, seq=%d, status=%d%s\n",
			$len, $seq, $status, $timestamp);
		print "\n";
		return;
	}

	$payload .= " - ERROR: af9035 status = $status" if ($status);

	if (scalar(@ctrl_bytes) >= 3 && ($ctrl_cmd =~ /CMD_GENERIC_I2C_(RD|WR)/)) {
		my @old = @ctrl_bytes;
		my $len = shift @ctrl_bytes;
		my $bus = shift @ctrl_bytes;
		my $addr = (shift @ctrl_bytes) >> 1;

		if (!scalar(@ctrl_bytes) && ($ctrl_cmd eq "CMD_GENERIC_I2C_RD")) {
			my @b = split(/ /, $payload);
			my $comment = "\t/* read: $payload */";

			printf "i2c_master_recv(bus%d, 0x%02x >> 1, &buf, %d);%s\n", $bus, $addr, scalar(@b), $comment if (!$hide_i2c_rd);
			return;
		} elsif ($ctrl_cmd eq "CMD_GENERIC_I2C_WR") {
			my $comment = "\t/* $payload */" if ($payload =~ /ERROR/);

			my $ctrl_pay;
			for (my $i =  0; $i < scalar(@ctrl_bytes); $i++) {
				if ($i == 0) {
					$ctrl_pay .= sprintf "0x%02x", $ctrl_bytes[$i];
				} else {
					$ctrl_pay .= sprintf ", 0x%02x", $ctrl_bytes[$i];
				}
			}

			printf "i2c_master_send(bus%d, 0x%02x >> 1, { %s }, %d);%s\n", $bus, $addr, $ctrl_pay, scalar(@ctrl_bytes), $comment if (!$hide_i2c_wr);
			return;
		}
		@ctrl_bytes = @old;
	}

	if (scalar(@ctrl_bytes) >= 3 && ($ctrl_cmd =~ /CMD_I2C_(RD|WR)/)) {
		my @old = @ctrl_bytes;
		my $len = shift @ctrl_bytes;
		my $addr = (shift @ctrl_bytes) >> 1;
		my $rlen = shift @ctrl_bytes;
		my $msb_raddr = shift @ctrl_bytes;
		my $lsb_raddr = shift @ctrl_bytes;

		if ($rlen == 2) {
			unshift(@ctrl_bytes, $lsb_raddr);
			unshift(@ctrl_bytes, $msb_raddr);
		} elsif ($rlen == 1) {
			unshift(@ctrl_bytes, $lsb_raddr);
		}

		if (!scalar(@ctrl_bytes) && ($ctrl_cmd eq "CMD_I2C_RD")) {
			my @b = split(/ /, $payload);
			my $comment = "\t/* read: $payload */";

			printf "i2c_master_recv(client, 0x%02x >> 1, &buf, %d);%s\n", $addr, scalar(@b), $comment if (!$hide_i2c_rd);
			return;
		} elsif ($ctrl_cmd eq "CMD_I2C_WR") {
			my $comment = "\t/* $payload */" if ($payload =~ /ERROR/);

			my $ctrl_pay;
			for (my $i =  0; $i < scalar(@ctrl_bytes); $i++) {
				if ($i == 0) {
					$ctrl_pay .= sprintf "0x%02x", $ctrl_bytes[$i];
				} else {
					$ctrl_pay .= sprintf ", 0x%02x", $ctrl_bytes[$i];
				}
			}

			printf "i2c_master_send(client, 0x%02x >> 1, { %s }, %d);%s\n", $addr, $ctrl_pay, scalar(@ctrl_bytes), $comment if (!$hide_i2c_wr);
			return;
		}
		@ctrl_bytes = @old;
	}

	if (scalar(@ctrl_bytes) >= 6 && ($ctrl_cmd eq "CMD_MEM_WR" || $ctrl_cmd eq "CMD_MEM_RD")) {
		my $wlen;

		$wlen = shift @ctrl_bytes;
		shift @ctrl_bytes;
		shift @ctrl_bytes;
		shift @ctrl_bytes;

		my $reg = $ctrl_mbox << 16;
		$reg |= (shift @ctrl_bytes) << 8;
		$reg |= (shift @ctrl_bytes);

		my $ctrl_pay;
		for (my $i =  0; $i < scalar(@ctrl_bytes); $i++) {
			if ($i == 0) {
				$ctrl_pay .= sprintf "0x%02x", $ctrl_bytes[$i];
			} else {
				$ctrl_pay .= sprintf ", 0x%02x", $ctrl_bytes[$i];
			}
		}

		if ($ctrl_cmd eq "CMD_MEM_WR") {
			return if ($hide_wr);
			my $comment = "\t/* $payload */" if ($payload =~ /ERROR/);

			if (scalar(@ctrl_bytes) > 1) {
				printf "ret = af9035_wr_regs(d, 0x%04x, %d, { $ctrl_pay });$comment\n", $reg, scalar(@ctrl_bytes);
			} else {
				printf "ret = af9035_wr_reg(d, 0x%04x, $ctrl_pay);$comment\n", $reg;
			}
			return;
		} else {
			return if ($hide_rd);
			my $comment = "\t/* read: $payload */";
			if (scalar(@ctrl_bytes) > 0) {
				printf "ret = af9035_rd_regs(d, 0x%04x, %d, { $ctrl_pay }, $len, rbuf);$comment\n", $reg, scalar(@ctrl_bytes);
			} else {
				printf "ret = af9035_rd_reg(d, 0x%04x, &val);$comment\n", $reg;
			}
			return;
		}
	}

	if ($ctrl_cmd =~ /CMD_FW_(QUERYINFO|DL_BEGIN|DL_END|BOOT)/) {
		my $comment = "\t/* read: $payload */" if ($payload);
		printf "struct usb_req req = { $ctrl_cmd, $ctrl_mbox, $len, wbuf, sizeof(rbuf), rbuf }; ret = af9035_ctrl_msg(d, &req);$comment\n" if (!$hide_fw);
		return;
	}

	if ($ctrl_cmd eq "CMD_IR_GET") {
		my $comment = "\t/* read: $payload */" if ($payload);
		printf "struct usb_req req = { $ctrl_cmd, $ctrl_mbox, $len, wbuf, sizeof(rbuf), rbuf }; ret = af9035_ctrl_msg(d, &req);$comment\n" if (!$hide_ir);
		return;
	}

	my $ctrl_pay;
	for (my $i = 0; $i < scalar(@ctrl_bytes); $i++) {
		if ($i == 0) {
			$ctrl_pay .= sprintf "0x%02x", $ctrl_bytes[$i];
		} else {
			$ctrl_pay .= sprintf ", 0x%02x", $ctrl_bytes[$i];
		}
	}

	if ($ctrl_cmd eq "CMD_FW_DL") {
		printf "af9015_wr_fw_block(%d, { $ctrl_pay };\n", scalar(@ctrl_bytes) if (!$hide_fw);
		return;
	}


	$payload = ", recv_bytes = $payload" if ($payload && !($payload =~ /^ERROR/));
	$ctrl_pay = ", bytes = $ctrl_pay" if ($ctrl_pay);

	printf("%sSEND: len=%d, seq %d, mbox=0x%02x, cmd=%s%s%s",
		$ctrl_ts, $ctrl_len, $ctrl_seq, $ctrl_mbox, $ctrl_cmd, $ctrl_pay, $payload);
	if ($ctrl_cmd ne "CMD_FW_DL") {
		$timestamp = "($timestamp)" if ($timestamp);
		printf(" RECV: len=%d, seq=%d, status=%d%s",
			$len, $seq, $status, $timestamp) if ($status);
	}
	print "\n";
}

while (<>) {
	if (m/(\d+)\s+ms\s+(\d+)\s+ms\s+\((\d+)\s+us\s+EP\=([\da-fA-F]+).*[\<\>]+\s*(.*)/) {
		my $timestamp = sprintf "%09u ms %6u ms %7u us ", $1, $2, $3;
		my $ep = hex($4);
		my $payload = $5;

		printf("// %sEP=0x%02x: %s\n", $timestamp, $ep, $payload) if ($debug);

		next if (!$payload);

		$timestamp = "" if (!$show_timestamp);

		next if (!($ep == $ctrl_ep || $ep == $resp_ep));

		my @bytes = split(/ /, $payload);
		for (my $i = 0; $i < scalar(@bytes); $i++) {
			$bytes[$i] = hex($bytes[$i]);
		}

		my $len = shift @bytes;
		my ($mbox, $cmd, $seq, $status);

		# Discount checksum and header length
		if ($ep == $ctrl_ep) {
			$mbox = shift @bytes;	# Actually, part of CMD
			$cmd = shift @bytes;
			$seq = shift @bytes;

			if (defined($cmd_map{$cmd})) {
				$cmd = $cmd_map{$cmd};
			} else {
				$cmd = sprintf "unknown 0x%02x", $cmd;
			}

			$len -= 4 + 1;
		} else {
			$seq = shift @bytes;
			$status = shift @bytes;

			$len -= 3 + 1;
		}
		my $checksum = pop @bytes;
		$checksum |= (pop @bytes) << 8;

		if ($ep == $ctrl_ep) {
			my @data = ( $timestamp, $ep, $len, $seq, $mbox, $cmd, @bytes );
			push @stack, \@data;

			if ($cmd eq "CMD_FW_DL") {
				print_send_recv($timestamp, $ep, 0, 0, 0, "");
			}

			next;
		}

		my $pay;
		# Print everything, except the checksum
		for (my $i = 0; $i < scalar(@bytes); $i++) {
			if (!$i) {
				$pay .= sprintf "0x%02x", $bytes[$i];
			} else {
				$pay .= sprintf ", 0x%02x", $bytes[$i];
			}
		}

		print_send_recv($timestamp, $ep, $len, $seq, $status, $pay);
	}
}
