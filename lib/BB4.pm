package BB4;

use strict;
use warnings;

use POE;

use BB4::ConfigParser;

sub new {
	my( $class, %config ) = @_;

	my $self = bless {}, $class;

	$self->_parse_config( \%config );
	$self->_load_config;
	$self->_load_plugin_handler;
	$self->_load_connectors;

	return $self;
}

sub _parse_config {
	my( $self, $conf ) = @_;
	
	$self->{config_dir} = $conf->{config_directory} || "../etc";
}

sub _load_config {
	my( $self ) = @_;
	my $dir = $self->{config_dir};

	if( not -d $dir ) {
		die "Error: Failed to find config directory [$dir]\n";
	}

	my @conf_files = glob "$dir/*.conf";

	if( not @conf_files ) {
		die "Error: [$dir] is empty of *.conf files\n";
	}

	for( @conf_files ) {
		my $conf = BB4::ConfigParser->parse_file( $_ );

		if( $conf->{irc} ) {
			push @{ $self->{config}->{irc} }, $conf->{irc};
		}
	}
}

sub _load_plugin_handler {
	my( $self ) = @_;
}

sub _load_connectors {
	my( $self ) = @_;

	for my $inc_path ( @INC ) {
		for my $module_file ( glob "$inc_path/BB4/Connector/*.pm" ) {

			my $package_name = $module_file;

			$package_name =~ s{^$inc_path/}{};
			$package_name =~ s{/}{::}g;
			$package_name =~ s/\.pm$//;
			
			eval { require $module_file };
			if( $@ ) { warn "Warning: Failed to load $package_name from $module_file: $@\n"; next; }

			eval { $self->{ connectors }->{ $package_name } = $package_name->new( $self ) };
			if( $@ ) { warn "Warning: Failed to instantiate $package_name\n"; }
		}
	}
}

sub start {
	POE::Kernel->run;
}

1;
