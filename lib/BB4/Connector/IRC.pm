package BB4::Connector::IRC;

use strict;
use warnings;

use POE;
use POE::Component::IRC;
use Data::Dumper;

sub new {
	my( $class, $bb4 ) = @_;

	my $self = bless { bb4 => $bb4 }, $class;

	$self->_launch_irc_components;

	return $self;
}

sub _launch_irc_components {
	my( $self ) = @_;

	for my $conf ( @{ $self->{bb4}->{config}->{irc} } ) {

		$self->_validate_conf( $conf );

		push @{ $self->{session} }, POE::Session->create(
			object_states => [
				$self => [ qw/_start irc_001 irc_public irc_msg irc_notice _default/ ],
			],
			heap => { conf => $conf },
		);
	}
}

sub _validate_conf {
	my( $self, $conf ) = @_;
	
	die "Error: Invalid config: ", Dumper($conf), "\n"
		unless $conf->{server} and $conf->{nick};
	
	if( not exists $conf->{port} ) {
		$conf->{port} = '6667';
	}

	if( not exists $conf->{irc_name} ) {
		$conf->{irc_name} = $conf->{nick};
	}

	if( not ref $conf->{channels} ) {
		
		$conf->{channels} = [ split /,/, $conf->{channels} ];
	}
	return; 
}
	

sub _start {
	my( $self, $heap ) = @_[OBJECT,HEAP];
	my $c = $heap->{conf};
	
	$heap->{irc} = POE::Component::IRC->spawn( 
		Server => $c->{server},
		Port => $c->{port},
		Password => $c->{server_password},
		Nick => $c->{nick},
		Username => $c->{irc_name},
	);

	$heap->{irc}->yield( connect => {} );

	warn "Yielded connect\n";

	return;
}

sub irc_001 {
	my( $self, $heap ) = @_[OBJECT,HEAP];

	warn "GOT 001\n";

	$heap->{irc}->yield( join => $_ ) for @{ $heap->{conf}->{channels} };

	return;
}

sub irc_public {} 
sub irc_msg {} 
sub irc_notice {} 
sub _default {}

1;
