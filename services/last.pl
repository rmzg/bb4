#!/usr/bin/perl

use IO::Socket::INET;
use JSON qw/decode_json encode_json/;
use strict;
use Data::Dumper;

my $s = IO::Socket::INET->new( "127.0.0.1:56780" ) or die $!;

my $register = encode_json({ type => "REGISTER", command_name => "last", events => [ "irc-public" ] });

print $s "$register\n";

my @queue;
while( <$s> ) {
	my $struct = decode_json( $_ );

	if( $struct->{command} ) {
		my $last_idx = $struct->{args}->[0] || 1;
		$last_idx++;
		my $cmd_id = $struct->{cmd_id};

		my $text = $queue[ -$last_idx ];

		my $resp = encode_json({ type => "RESPONSE", cmd_id => $cmd_id, body => $text });

		print $s "$resp\n";
	}

	elsif( $struct->{type} eq 'event' ) {
		push @queue, "<$struct->{nick}> $struct->{raw_body}";
		if( @queue > 1000 ) { shift @queue; }
	}
}
