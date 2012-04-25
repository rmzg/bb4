package BB4::PluginHandler;

use POE;
use POE::Session;
use POE::Wheel::SocketFactory;
use POE::Wheel::ReadWrite;
use POE::Filter::Line;
use POE::Wheel::Run;

use Regexp::Common;
use UUID;

use strict;
use warnings;

sub new {
	my( $class, $bb4 ) = @_;

	my $self = bless { bb4 => $bb4, plugin_dir => "./plugins" }, $class;

	$self->{session} = POE::Session->create(
		object_states => [
			$self => [ qw/
				_start

				handle_command
				execute_commands
				invoke_target
				wheel_command_output

				wheel_run_stdout
				wheel_run_stderr
				wheel_run_error
				wheel_run_close
				
				server_error
				client_accept
				client_error
				client_input
			/ ]
		]
	);

	return $self;
}

sub yield {
	my( $self, @args ) = @_;

	POE::Kernel->post( $self->{session}->ID, @args );
}

sub _start {
	my( $self ) = $_[OBJECT];

	$self->{server} = POE::Wheel::SocketFactory->new(
		Reuse => 1,
		BindPort => 56780,
		BindAddress => "127.0.0.1",

		SuccessEvent => "client_accept",
		FailureEvent => "server_error",
	);
}

##########################################################
# The main remote entry point
##########################################################
sub handle_command {
	my( $self, $kernel, $sender, $command_line, $tag ) = @_[OBJECT, KERNEL, SENDER, ARG0, ARG1];
	
	UUID::generate( my $cmd_id );
	
	$self->{open_commands}->{ $cmd_id } = {
		sender => $sender,
		original_command_line => $command_line,
		current_command_line => $command_line,
		cmd_id => $cmd_id,
		tag => $tag,
		stdout => "",
		stderr => "",
		previous_eoc => "",
	};

	$kernel->yield( execute_commands => $cmd_id );

	return;
}

sub execute_commands {
	my( $self, $kernel, $cmd_id ) = @_[OBJECT, KERNEL, ARG0];
	my $cmd_struct = $self->{open_commands}->{ $cmd_id };

	my $command_line = $cmd_struct->{current_command_line};

	warn "execute_commands: [$command_line]\n";

	my $EOC = qr/[;|&]/;

	if( $command_line !~ /\S/ ) { #Empty command_line

		$kernel->yield( wheel_command_output => $cmd_id );
		return;
	}

	my $eoc = "";
	if( $command_line =~ s/^\s*($EOC)// ) {
		$eoc = $1;
	}

	my @args;
	while( $command_line =~ s/^\s*(\w+|$RE{quoted})// ) {

		push @args, $1;

		if( $args[-1] =~ s/^\s*(['"])// ) {
			$args[-1] =~ s/$1\s*$//;
		}

		$args[-1] =~ s/\\(.)/$1/g;
	}
	$cmd_struct->{current_command_line} = $command_line;

	if( $eoc eq '|' and length $cmd_struct->{stdout} ) {
		push @args, delete $cmd_struct->{stdout}
	}

	my $target = shift @args;

	$kernel->yield( invoke_target => $cmd_id, $target, \@args );
}

sub invoke_target {
	my( $self, $kernel, $cmd_id, $target, $args ) = @_[OBJECT, KERNEL, ARG0..ARG2];
	my $cmd_struct = $self->{open_commands}->{ $cmd_id };

	unless( $target ) {
		$cmd_struct->{stderr} .= "Invalid command!";
		$kernel->yield( wheel_command_output => $cmd_id );
		return;
	}

	# Minor sanitization!
	(my $file_target = $target ) =~ s/\.\.//g;
	my $exe = "$self->{plugin_dir}/$file_target";

	if( not -x $exe  ) {
		my $flag = 0;
		for( glob "$exe.*" ) {

			if( -x $_ ) {
				$exe = $_;
				$flag = 1;
				last;
			}
		}

		unless( $flag ) {
			$cmd_struct->{stderr} .= "Failed to find executable for $target";
			$kernel->yield( execute_commands => $cmd_struct->{cmd_id} );
			return;
		}
	}

	if( $exe ) {
		$self->_launch_wheel_run( [ $exe, @$args], $cmd_struct, $kernel );
	}
	else {
		$self->_invoke_service( $exe, $args, $cmd_struct, $kernel );
	}

	return;
}

sub _invoke_service {
	my( $self, $target, $args, $cmd_struct, $kernel ) = @_;


}

sub wheel_command_output {
	my( $self, $kernel, $cmd_id, $tag ) = @_[OBJECT, KERNEL, ARG0];
	my $cmd_struct = delete $self->{open_commands}->{ $cmd_id };

	my $output = "";

	if( defined $cmd_struct->{stderr} ) {
		$output .= $cmd_struct->{stderr};
	}

	if( length $cmd_struct->{stdout} ) { 
		$output .= $cmd_struct->{stdout};
	}

	$kernel->post( $cmd_struct->{sender}, command_response => $output, $cmd_struct->{tag} );

	return;
}

sub _launch_wheel_run {
	my( $self, $prog, $cmd_struct, $kernel ) = @_;

		my $wheel_run = POE::Wheel::Run->new( 
			Program => $prog,
			StdoutEvent => 'wheel_run_stdout',
			StderrEvent => 'wheel_run_stderr',
			ErrorEvent => 'wheel_run_error',
			CloseEvent => 'wheel_run_close',
		);

		# Store the wheel by ->ID and ->PID because the 'close' event gets the
		# wheel ID and the 'signal' event gets the wheel PID. Sigh.
		$self->{open_wheel_runs}->{wheel_id}->{ $wheel_run->ID } = {
			wheel => $wheel_run,
			cmd_struct => $cmd_struct,
		};
		$self->{open_wheel_runs}->{wheel_pid}->{ $wheel_run->PID } = $self->{open_wheel_runs}->{wheel_id}->{ $wheel_run->ID };

		$kernel->sig_child( $wheel_run->PID, "wheel_run_signal" );

		return $wheel_run;
}


##########################################################
# Wheel Run Events
##########################################################

sub wheel_run_stdout {
	my( $self, $line, $wheel_id ) = @_[OBJECT, ARG0, ARG1];
	
	$self->{open_wheel_runs}->{wheel_id}->{ $wheel_id }->{cmd_struct}->{stdout} .= "$line ";

	return;
}

sub wheel_run_stderr {
	my( $self, $line, $wheel_id ) = @_[OBJECT, ARG0, ARG1];

	$self->{open_wheel_runs}->{wheel_id}->{ $wheel_id }->{cmd_struct}->{stderr} .= "stderr:$line ";

	return;
}

sub wheel_run_close {
	my( $self, $kernel, $wheel_id ) = @_[OBJECT, KERNEL, ARG0];

	my $wheel_struct = delete $self->{open_wheel_runs}->{wheel_id}->{ $wheel_id };
	#Wheel might have been already deleted by wheel_run_signal
	if( $wheel_struct ) {
		my $cmd_struct = $wheel_struct->{cmd_struct};

		$kernel->yield( execute_commands => $cmd_struct->{cmd_id} );

		delete $self->{open_wheel_runs}->{wheel_pid}->{ $wheel_struct->{wheel}->PID };
	}

	return;
}

sub wheel_run_signal {
	my( $self, $kernel, $wheel_pid, $signal ) = @_[OBJECT, KERNEL, ARG1, ARG2];

	my $wheel_struct = delete $self->{open_wheel_runs}->{wheel_pid}->{ $wheel_pid };
	#Wheel might have been already deleted by wheel_run_close
	if( $wheel_struct ) {
		my $cmd_struct = $wheel_struct->{cmd_struct};

		$cmd_struct->{stderr} .= "Killed by $signal";

		$kernel->yield( execute_commands => $cmd_struct->{cmd_id} );

		delete $self->{open_wheel_runs}->{wheel_id}->{ $wheel_struct->{wheel}->ID };
	}

	return;
}

sub wheel_run_error {
	my( $self, $err_str, $wheel_id ) = @_[OBJECT, ARG2, ARG3];

	if( $err_str ) {
		warn "ERROR: $wheel_id: $err_str\n";
	}
}

##########################################################
# Server Related Handlers
##########################################################
sub server_error {
	my( $self, $operation, $errnum, $errstr) = @_[OBJECT, ARG0, ARG1, ARG2];

	die "Server $operation error $errnum: $errstr\n";

	delete $self->{server};
	return;
}

sub client_accept {
	my( $self, $socket ) = @_[OBJECT, ARG0];

	my $wheel = POE::Wheel::ReadWrite->new( 
		Handle => $socket,
		InputEvent => 'client_input',
		ErrorEvent => 'client_error',

		Filter => POE::Filter::Line->new,
	);

	$self->{server_wheels}->{ $wheel->ID() } = $wheel;
	
	return;
}

sub client_error {
	my( $self, $wheel_id ) = @_[OBJECT, ARG3];

	delete $self->{server_wheels}->{ $wheel_id };

	return;
}

sub client_input {
	my( $self, $input, $wheel_id ) = @_[OBJECT, ARG0, ARG1];

	$self->{server_wheels}->{ $wheel_id}->put("I see: [$input]");

	return;
}

1;
