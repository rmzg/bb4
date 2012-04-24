package BB4::ConfigParser;

use strict;
use warnings;

use Regexp::Common;

sub parse_file {
	my( $self, $file_name ) = @_;

	open my $fh, "<", $file_name 
		or die "Error: Failed to open $file_name for parsing as a config file\n";

	my %config;
	my $current_section;

	while( defined( my $line = <$fh> ) ) {
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;

		next unless $line =~ /\S/;

		if( $line =~ /^\[([\w-]+)\s*($RE{quoted})?\s*\]$/ ) {

			$current_section = $config{ $1 } ||= {};

			if( $2 ) { 
				my $subsection = $2;
				$subsection =~ s/^.//;
				$subsection =~ s/.$//;
				$subsection =~ s/\\(.)/$1/sg;

				$current_section = $current_section->{ $subsection } ||= {};
			}
		}

		elsif( $line =~ /^([\w-]+)\s*=\s*(\S+|$RE{quoted})\s*$/ ) {
			my( $key, $value ) = ($1,$2);

			if( $value =~ s/^\s*['"`]// ) {
				$value =~ s/['"`]\s*$//;
				$value =~ s/\\(.)/$1/sg;
			}

			$current_section->{ $key } = $value;
		}

		else {
			die "Error: Failed to parse config file [$file_name] line: $line\n";
		}
	}

	return \%config;
}

1;
