# Copyright (c) 2010  Mike Cardwell
#
# See LICENSE section in pod text below for usage and distribution rights.
#

package HTTPSEverywhere;

use strict;
use warnings;
use XML::LibXML;

sub new {
   my $class = shift;
   my %args  = @_;

   die "Missing rulesets arg" unless exists $args{rulesets};

   my $paths = ref($args{rulesets}) eq 'ARRAY' ? $args{rulesets} : [$args{rulesets}];

   my $self = bless {
      paths => $paths,
   }, $class;

   $self->read();

   return $self;
}

sub convert {
   my( $self, $url ) = @_;

   return $url unless $url =~ m#^http://(?:[^\@\/]+\@)?([-a-z0-9\.]+)(/.*)?$#i;
   my( $host, $uri ) = ( lc($1), $2||'/' );

   my $newurl = "http://$host$uri";

   ## Split the host into parts for the <target/> checks
     my $host_split = [split(/\./,$host)];

   ## Traverse each ruleset
     foreach my $name ( sort keys %{$self->{ruleset}} ){

        ## <target/>
          my $match_target = 1;
          foreach my $target (  @{$self->{ruleset}{$name}{targets}} ){
             $match_target = 0;

             next unless int(@$target) == int(@$host_split);
             for( my $n = int(@$target)-1; $n >= 0; --$n ){
                last unless $target->[$n] eq $host_split->[$n] || $target->[$n] eq '*';
                $match_target = 1 if $n == 0;
             }
             last if $match_target;
          }
          next unless $match_target;

        ## <exclusion/>
          my $exclude = 0;
          foreach my $exclusion ( @{$self->{ruleset}{$name}{exclusions}} ){
             if( $newurl =~ $exclusion ){
                $exclude = 1;
                last;
             }
          }
          next if $exclude;

        ## <rule/>
          foreach my $rule ( @{$self->{ruleset}{$name}{rules}} ){
             my @match = $newurl =~ $rule->{from};
             if( @match ){
                $newurl =~ s/$rule->{from}/$rule->{to}/;

                my $n = 0;
                foreach my $bit ( @match ){
                   ++$n; next unless defined $bit;
                   $newurl =~ s/\$$n/$bit/gsm;
                }

                return $newurl;
             }
          }
     }

   ## Didn't match anything. Return the original rule
     return $url;
}

sub read {
   my $self = shift;
   my @paths = int(@_) ? @_ : @{$self->{paths}};

   $self->{ruleset} = {};
   $self->_read($_) foreach @paths;
}

sub _read {
   my( $self, $path ) = @_;

   $path =~ s/\/+$//;

   opendir( my $dir, $path ) or die $!;
   foreach( readdir $dir ){
      my $file = $_;
      next unless $file =~ /\.xml$/;

      my $doc = XML::LibXML->load_xml( location => "$path/$file" ) or die $!;
      my $xml = $doc->documentElement;

      if( $xml->nodeName eq 'ruleset' ){
         next if $xml->getAttribute('default_off')||'';

         my $name = $xml->getAttribute('name')||'';

         my @targets;
         foreach my $target ( $xml->findnodes('/ruleset/target') ){
            push @targets, [split(/\./,lc($target->getAttribute('host')))];
         }

         my @exclusions;
         foreach my $exclusion ( $xml->findnodes('/ruleset/exclusion') ){
            my $pattern = $exclusion->getAttribute('pattern');
            push @exclusions, qr{$pattern}i;
         }

         my @rules;
         foreach my $rule ( $xml->findnodes('/ruleset/rule') ){
            my $from = $rule->getAttribute('from');
            push @rules, {
               from => qr{$from}i,
               to   => $rule->getAttribute('to'),
            };
         }

         $self->{ruleset}{$name} = {
            targets     => \@targets,
            exclusions  => \@exclusions,
            rules       => \@rules,
         };
      } else {
         die "Invalid XML in $path/$file\n";
      }
   }
   closedir $dir;
}

1;

__END__

=pod

=head1 NAME

HTTPSEverywhere -- Use the rulesets generated for HTTPS-Everywhere from
Perl.

=head1 DESCRIPTION

HTTPS Everywhere is a Firefox addon which forces users to use https for
certain websites. This Perl module was written to take advantage of the
rulesets generated for that project. You need to download the rules
separately.

Project page:

  https://www.eff.org/https-everywhere

Obtain the repository and rules from Git:

  git clone git://git.torproject.org/https-everywhere.git

This project is currently under heavy development and the format of
the rulesets are likely to change. This module may stop working
because of that. I will endeavour to keep it up to date with the
latest ruleset format.

=head1 EXAMPLES

  my $he = new HTTPSEverywhere(
     rulesets => [
        '/git/https-everywhere/src/chrome/content/rules',
     ],
  );
  my $url = $he->convert('http://gmail.com/foo');

  In this example, $url would contain https://mail.google.com/foo

=head1 METHODS

=over

=item B<new( rulesets => \@paths ))>

  "rulesets" contains a list of paths to the directory or directories
  containing the xml ruleset files

=item B<read( @paths )>

  Clears out the known rulesets and reads them from each of the
  directories in @paths. If @paths is not provided, it re-reads
  them from the paths specified in new().

=item B<convert( $url )>

  Returns the converted version of the URL. If no rules match the
  URL, the original URL is returned.

=back

=head1 COPYRIGHT

Copyright (c) 2010  Mike Cardwell

=head1 LICENSE

Licensed under the GNU General Public License. See
http://www.opensource.org/licenses/gpl-2.0.php

=head1 AUTHOR

Mike Cardwell - https://grepular.com/ 

Copyright (C) 2010  Mike Cardwell

=cut
