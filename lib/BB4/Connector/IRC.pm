package BB4::Connector::IRC;

use strict;
use warnings;

use POE;
use POE::Component::IRC;
use IRC::Utils qw/parse_user/;

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
				$self => [ qw/_start command_response irc_001 irc_public irc_msg irc_notice _default/ ],
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

	return;
}

sub command_response {
	my( $self, $heap, $response, $said ) = @_[OBJECT, HEAP, ARG0, ARG1];

	if( $said->{public} ) {
		$response = "$said->{nick}: $response";
	}

	warn "Attempting to privmsg $said->{channel} => $response\n";

	$heap->{irc}->yield( privmsg => $said->{channel} => $response );
}

sub irc_001 {
	my( $self, $heap ) = @_[OBJECT,HEAP];

	$heap->{irc}->yield( join => $_ ) for @{ $heap->{conf}->{channels} };

	return;
}

sub _said {
	my( $self, $heap ) = @_[OBJECT, HEAP];
	(caller 1)[3] =~ /::([^:]+)$/;
	my $caller = $1;

	my $said = {};
	my( $irc_user, $channels, $text ) = @_[ARG0 .. ARG2];

	@{$said}{qw/nick user host/} = parse_user( $irc_user );
	$said->{channel} = $channels->[0];
	$said->{body} = $text;

	$said->{self_nick} = $heap->{irc}->nick_name;
	if( $said->{body} =~ s/^\s*$said->{self_nick}\s*[,:-]?\s*// ) {
		$said->{addressed} = $said->{self_nick};
	}

	if( $caller eq 'irc_msg' ) {
		$said->{addressed} = 1;
		$said->{channel} = $said->{nick};
	}

	if( $caller eq 'irc_public' ) {
		$said->{public} = 1;
	}

	return $said;
}

sub irc_public {
	my( $self ) = $_[OBJECT];

	my $said = _said( @_ );

	if( $said->{body} =~ s/^\s*!\s*// or $said->{addressed} ) {
		$self->{bb4}->handle_command( $said->{body}, $said );
	}


	return;
} 
sub irc_msg {
	my( $self ) = $_[OBJECT];

	my $said = _said( @_ );

	$said->{body} =~ s/^\s*!\s*//;

	$self->{bb4}->handle_command( $said->{body}, $said );
} 
sub irc_notice {} 
sub _default {}

1;
