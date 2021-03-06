@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/bin/env perl
#line 15

# This program is copyright 2010-2011 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.

use strict;
use warnings FATAL => 'all';

our $VERSION = '1.0.2';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7477 $ =~ m/(\d+)/g, 0));

# ###########################################################################
# OptionParser package 7102
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/OptionParser.pm
#   trunk/common/t/OptionParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package OptionParser;

use strict;
use warnings FATAL => 'all';
use List::Util qw(max);
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Getopt::Long;

my $POD_link_re = '[LC]<"?([^">]+)"?>';

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($program_name) = $PROGRAM_NAME =~ m/([.A-Za-z-]+)$/;
   $program_name ||= $PROGRAM_NAME;
   my $home = $ENV{HOME} || $ENV{HOMEPATH} || $ENV{USERPROFILE} || '.';

   my %attributes = (
      'type'       => 1,
      'short form' => 1,
      'group'      => 1,
      'default'    => 1,
      'cumulative' => 1,
      'negatable'  => 1,
   );

   my $self = {
      head1             => 'OPTIONS',        # These args are used internally
      skip_rules        => 0,                # to instantiate another Option-
      item              => '--(.*)',         # Parser obj that parses the
      attributes        => \%attributes,     # DSN OPTIONS section.  Tools
      parse_attributes  => \&_parse_attribs, # don't tinker with these args.

      %args,

      strict            => 1,  # disabled by a special rule
      program_name      => $program_name,
      opts              => {},
      got_opts          => 0,
      short_opts        => {},
      defaults          => {},
      groups            => {},
      allowed_groups    => {},
      errors            => [],
      rules             => [],  # desc of rules for --help
      mutex             => [],  # rule: opts are mutually exclusive
      atleast1          => [],  # rule: at least one opt is required
      disables          => {},  # rule: opt disables other opts 
      defaults_to       => {},  # rule: opt defaults to value of other opt
      DSNParser         => undef,
      default_files     => [
         "/etc/maatkit/maatkit.conf",
         "/etc/maatkit/$program_name.conf",
         "$home/.maatkit.conf",
         "$home/.$program_name.conf",
      ],
      types             => {
         string => 's', # standard Getopt type
         int    => 'i', # standard Getopt type
         float  => 'f', # standard Getopt type
         Hash   => 'H', # hash, formed from a comma-separated list
         hash   => 'h', # hash as above, but only if a value is given
         Array  => 'A', # array, similar to Hash
         array  => 'a', # array, similar to hash
         DSN    => 'd', # DSN
         size   => 'z', # size with kMG suffix (powers of 2^10)
         time   => 'm', # time, with an optional suffix of s/h/m/d
      },
   };

   return bless $self, $class;
}

sub get_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   my @specs = $self->_pod_to_specs($file);
   $self->_parse_specs(@specs);

   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   if ( $contents =~ m/^=head1 DSN OPTIONS/m ) {
      MKDEBUG && _d('Parsing DSN OPTIONS');
      my $dsn_attribs = {
         dsn  => 1,
         copy => 1,
      };
      my $parse_dsn_attribs = sub {
         my ( $self, $option, $attribs ) = @_;
         map {
            my $val = $attribs->{$_};
            if ( $val ) {
               $val    = $val eq 'yes' ? 1
                       : $val eq 'no'  ? 0
                       :                 $val;
               $attribs->{$_} = $val;
            }
         } keys %$attribs;
         return {
            key => $option,
            %$attribs,
         };
      };
      my $dsn_o = new OptionParser(
         description       => 'DSN OPTIONS',
         head1             => 'DSN OPTIONS',
         dsn               => 0,         # XXX don't infinitely recurse!
         item              => '\* (.)',  # key opts are a single character
         skip_rules        => 1,         # no rules before opts
         attributes        => $dsn_attribs,
         parse_attributes  => $parse_dsn_attribs,
      );
      my @dsn_opts = map {
         my $opts = {
            key  => $_->{spec}->{key},
            dsn  => $_->{spec}->{dsn},
            copy => $_->{spec}->{copy},
            desc => $_->{desc},
         };
         $opts;
      } $dsn_o->_pod_to_specs($file);
      $self->{DSNParser} = DSNParser->new(opts => \@dsn_opts);
   }

   return;
}

sub DSNParser {
   my ( $self ) = @_;
   return $self->{DSNParser};
};

sub get_defaults_files {
   my ( $self ) = @_;
   return @{$self->{default_files}};
}

sub _pod_to_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";

   my @specs = ();
   my @rules = ();
   my $para;

   local $INPUT_RECORD_SEPARATOR = '';
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=head1 $self->{head1}/;
      last;
   }

   while ( $para = <$fh> ) {
      last if $para =~ m/^=over/;
      next if $self->{skip_rules};
      chomp $para;
      $para =~ s/\s+/ /g;
      $para =~ s/$POD_link_re/$1/go;
      MKDEBUG && _d('Option rule:', $para);
      push @rules, $para;
   }

   die "POD has no $self->{head1} section" unless $para;

   do {
      if ( my ($option) = $para =~ m/^=item $self->{item}/ ) {
         chomp $para;
         MKDEBUG && _d($para);
         my %attribs;

         $para = <$fh>; # read next paragraph, possibly attributes

         if ( $para =~ m/: / ) { # attributes
            $para =~ s/\s+\Z//g;
            %attribs = map {
                  my ( $attrib, $val) = split(/: /, $_);
                  die "Unrecognized attribute for --$option: $attrib"
                     unless $self->{attributes}->{$attrib};
                  ($attrib, $val);
               } split(/; /, $para);
            if ( $attribs{'short form'} ) {
               $attribs{'short form'} =~ s/-//;
            }
            $para = <$fh>; # read next paragraph, probably short help desc
         }
         else {
            MKDEBUG && _d('Option has no attributes');
         }

         $para =~ s/\s+\Z//g;
         $para =~ s/\s+/ /g;
         $para =~ s/$POD_link_re/$1/go;

         $para =~ s/\.(?:\n.*| [A-Z].*|\Z)//s;
         MKDEBUG && _d('Short help:', $para);

         die "No description after option spec $option" if $para =~ m/^=item/;

         if ( my ($base_option) =  $option =~ m/^\[no\](.*)/ ) {
            $option = $base_option;
            $attribs{'negatable'} = 1;
         }

         push @specs, {
            spec  => $self->{parse_attributes}->($self, $option, \%attribs), 
            desc  => $para
               . (defined $attribs{default} ? " (default $attribs{default})" : ''),
            group => ($attribs{'group'} ? $attribs{'group'} : 'default'),
         };
      }
      while ( $para = <$fh> ) {
         last unless $para;
         if ( $para =~ m/^=head1/ ) {
            $para = undef; # Can't 'last' out of a do {} block.
            last;
         }
         last if $para =~ m/^=item /;
      }
   } while ( $para );

   die "No valid specs in $self->{head1}" unless @specs;

   close $fh;
   return @specs, @rules;
}

sub _parse_specs {
   my ( $self, @specs ) = @_;
   my %disables; # special rule that requires deferred checking

   foreach my $opt ( @specs ) {
      if ( ref $opt ) { # It's an option spec, not a rule.
         MKDEBUG && _d('Parsing opt spec:',
            map { ($_, '=>', $opt->{$_}) } keys %$opt);

         my ( $long, $short ) = $opt->{spec} =~ m/^([\w-]+)(?:\|([^!+=]*))?/;
         if ( !$long ) {
            die "Cannot parse long option from spec $opt->{spec}";
         }
         $opt->{long} = $long;

         die "Duplicate long option --$long" if exists $self->{opts}->{$long};
         $self->{opts}->{$long} = $opt;

         if ( length $long == 1 ) {
            MKDEBUG && _d('Long opt', $long, 'looks like short opt');
            $self->{short_opts}->{$long} = $long;
         }

         if ( $short ) {
            die "Duplicate short option -$short"
               if exists $self->{short_opts}->{$short};
            $self->{short_opts}->{$short} = $long;
            $opt->{short} = $short;
         }
         else {
            $opt->{short} = undef;
         }

         $opt->{is_negatable}  = $opt->{spec} =~ m/!/        ? 1 : 0;
         $opt->{is_cumulative} = $opt->{spec} =~ m/\+/       ? 1 : 0;
         $opt->{is_required}   = $opt->{desc} =~ m/required/ ? 1 : 0;

         $opt->{group} ||= 'default';
         $self->{groups}->{ $opt->{group} }->{$long} = 1;

         $opt->{value} = undef;
         $opt->{got}   = 0;

         my ( $type ) = $opt->{spec} =~ m/=(.)/;
         $opt->{type} = $type;
         MKDEBUG && _d($long, 'type:', $type);


         $opt->{spec} =~ s/=./=s/ if ( $type && $type =~ m/[HhAadzm]/ );

         if ( (my ($def) = $opt->{desc} =~ m/default\b(?: ([^)]+))?/) ) {
            $self->{defaults}->{$long} = defined $def ? $def : 1;
            MKDEBUG && _d($long, 'default:', $def);
         }

         if ( $long eq 'config' ) {
            $self->{defaults}->{$long} = join(',', $self->get_defaults_files());
         }

         if ( (my ($dis) = $opt->{desc} =~ m/(disables .*)/) ) {
            $disables{$long} = $dis;
            MKDEBUG && _d('Deferring check of disables rule for', $opt, $dis);
         }

         $self->{opts}->{$long} = $opt;
      }
      else { # It's an option rule, not a spec.
         MKDEBUG && _d('Parsing rule:', $opt); 
         push @{$self->{rules}}, $opt;
         my @participants = $self->_get_participants($opt);
         my $rule_ok = 0;

         if ( $opt =~ m/mutually exclusive|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{mutex}}, \@participants;
            MKDEBUG && _d(@participants, 'are mutually exclusive');
         }
         if ( $opt =~ m/at least one|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{atleast1}}, \@participants;
            MKDEBUG && _d(@participants, 'require at least one');
         }
         if ( $opt =~ m/default to/ ) {
            $rule_ok = 1;
            $self->{defaults_to}->{$participants[0]} = $participants[1];
            MKDEBUG && _d($participants[0], 'defaults to', $participants[1]);
         }
         if ( $opt =~ m/restricted to option groups/ ) {
            $rule_ok = 1;
            my ($groups) = $opt =~ m/groups ([\w\s\,]+)/;
            my @groups = split(',', $groups);
            %{$self->{allowed_groups}->{$participants[0]}} = map {
               s/\s+//;
               $_ => 1;
            } @groups;
         }
         if( $opt =~ m/accepts additional command-line arguments/ ) {
            $rule_ok = 1;
            $self->{strict} = 0;
            MKDEBUG && _d("Strict mode disabled by rule");
         }

         die "Unrecognized option rule: $opt" unless $rule_ok;
      }
   }

   foreach my $long ( keys %disables ) {
      my @participants = $self->_get_participants($disables{$long});
      $self->{disables}->{$long} = \@participants;
      MKDEBUG && _d('Option', $long, 'disables', @participants);
   }

   return; 
}

sub _get_participants {
   my ( $self, $str ) = @_;
   my @participants;
   foreach my $long ( $str =~ m/--(?:\[no\])?([\w-]+)/g ) {
      die "Option --$long does not exist while processing rule $str"
         unless exists $self->{opts}->{$long};
      push @participants, $long;
   }
   MKDEBUG && _d('Participants for', $str, ':', @participants);
   return @participants;
}

sub opts {
   my ( $self ) = @_;
   my %opts = %{$self->{opts}};
   return %opts;
}

sub short_opts {
   my ( $self ) = @_;
   my %short_opts = %{$self->{short_opts}};
   return %short_opts;
}

sub set_defaults {
   my ( $self, %defaults ) = @_;
   $self->{defaults} = {};
   foreach my $long ( keys %defaults ) {
      die "Cannot set default for nonexistent option $long"
         unless exists $self->{opts}->{$long};
      $self->{defaults}->{$long} = $defaults{$long};
      MKDEBUG && _d('Default val for', $long, ':', $defaults{$long});
   }
   return;
}

sub get_defaults {
   my ( $self ) = @_;
   return $self->{defaults};
}

sub get_groups {
   my ( $self ) = @_;
   return $self->{groups};
}

sub _set_option {
   my ( $self, $opt, $val ) = @_;
   my $long = exists $self->{opts}->{$opt}       ? $opt
            : exists $self->{short_opts}->{$opt} ? $self->{short_opts}->{$opt}
            : die "Getopt::Long gave a nonexistent option: $opt";

   $opt = $self->{opts}->{$long};
   if ( $opt->{is_cumulative} ) {
      $opt->{value}++;
   }
   else {
      $opt->{value} = $val;
   }
   $opt->{got} = 1;
   MKDEBUG && _d('Got option', $long, '=', $val);
}

sub get_opts {
   my ( $self ) = @_; 

   foreach my $long ( keys %{$self->{opts}} ) {
      $self->{opts}->{$long}->{got} = 0;
      $self->{opts}->{$long}->{value}
         = exists $self->{defaults}->{$long}       ? $self->{defaults}->{$long}
         : $self->{opts}->{$long}->{is_cumulative} ? 0
         : undef;
   }
   $self->{got_opts} = 0;

   $self->{errors} = [];

   if ( @ARGV && $ARGV[0] eq "--config" ) {
      shift @ARGV;
      $self->_set_option('config', shift @ARGV);
   }
   if ( $self->has('config') ) {
      my @extra_args;
      foreach my $filename ( split(',', $self->get('config')) ) {
         eval {
            push @extra_args, $self->_read_config_file($filename);
         };
         if ( $EVAL_ERROR ) {
            if ( $self->got('config') ) {
               die $EVAL_ERROR;
            }
            elsif ( MKDEBUG ) {
               _d($EVAL_ERROR);
            }
         }
      }
      unshift @ARGV, @extra_args;
   }

   Getopt::Long::Configure('no_ignore_case', 'bundling');
   GetOptions(
      map    { $_->{spec} => sub { $self->_set_option(@_); } }
      grep   { $_->{long} ne 'config' } # --config is handled specially above.
      values %{$self->{opts}}
   ) or $self->save_error('Error parsing options');

   if ( exists $self->{opts}->{version} && $self->{opts}->{version}->{got} ) {
      printf("%s  Ver %s Distrib %s Changeset %s\n",
         $self->{program_name}, $main::VERSION, $main::DISTRIB, $main::SVN_REV)
            or die "Cannot print: $OS_ERROR";
      exit 0;
   }

   if ( @ARGV && $self->{strict} ) {
      $self->save_error("Unrecognized command-line options @ARGV");
   }

   foreach my $mutex ( @{$self->{mutex}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$mutex;
      if ( @set > 1 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$mutex}[ 0 .. scalar(@$mutex) - 2] )
                 . ' and --'.$self->{opts}->{$mutex->[-1]}->{long}
                 . ' are mutually exclusive.';
         $self->save_error($err);
      }
   }

   foreach my $required ( @{$self->{atleast1}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$required;
      if ( @set == 0 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$required}[ 0 .. scalar(@$required) - 2] )
                 .' or --'.$self->{opts}->{$required->[-1]}->{long};
         $self->save_error("Specify at least one of $err");
      }
   }

   $self->_check_opts( keys %{$self->{opts}} );
   $self->{got_opts} = 1;
   return;
}

sub _check_opts {
   my ( $self, @long ) = @_;
   my $long_last = scalar @long;
   while ( @long ) {
      foreach my $i ( 0..$#long ) {
         my $long = $long[$i];
         next unless $long;
         my $opt  = $self->{opts}->{$long};
         if ( $opt->{got} ) {
            if ( exists $self->{disables}->{$long} ) {
               my @disable_opts = @{$self->{disables}->{$long}};
               map { $self->{opts}->{$_}->{value} = undef; } @disable_opts;
               MKDEBUG && _d('Unset options', @disable_opts,
                  'because', $long,'disables them');
            }

            if ( exists $self->{allowed_groups}->{$long} ) {

               my @restricted_groups = grep {
                  !exists $self->{allowed_groups}->{$long}->{$_}
               } keys %{$self->{groups}};

               my @restricted_opts;
               foreach my $restricted_group ( @restricted_groups ) {
                  RESTRICTED_OPT:
                  foreach my $restricted_opt (
                     keys %{$self->{groups}->{$restricted_group}} )
                  {
                     next RESTRICTED_OPT if $restricted_opt eq $long;
                     push @restricted_opts, $restricted_opt
                        if $self->{opts}->{$restricted_opt}->{got};
                  }
               }

               if ( @restricted_opts ) {
                  my $err;
                  if ( @restricted_opts == 1 ) {
                     $err = "--$restricted_opts[0]";
                  }
                  else {
                     $err = join(', ',
                               map { "--$self->{opts}->{$_}->{long}" }
                               grep { $_ } 
                               @restricted_opts[0..scalar(@restricted_opts) - 2]
                            )
                          . ' or --'.$self->{opts}->{$restricted_opts[-1]}->{long};
                  }
                  $self->save_error("--$long is not allowed with $err");
               }
            }

         }
         elsif ( $opt->{is_required} ) { 
            $self->save_error("Required option --$long must be specified");
         }

         $self->_validate_type($opt);
         if ( $opt->{parsed} ) {
            delete $long[$i];
         }
         else {
            MKDEBUG && _d('Temporarily failed to parse', $long);
         }
      }

      die "Failed to parse options, possibly due to circular dependencies"
         if @long == $long_last;
      $long_last = @long;
   }

   return;
}

sub _validate_type {
   my ( $self, $opt ) = @_;
   return unless $opt;

   if ( !$opt->{type} ) {
      $opt->{parsed} = 1;
      return;
   }

   my $val = $opt->{value};

   if ( $val && $opt->{type} eq 'm' ) {  # type time
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a time value');
      my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
      if ( !$suffix ) {
         my ( $s ) = $opt->{desc} =~ m/\(suffix (.)\)/;
         $suffix = $s || 's';
         MKDEBUG && _d('No suffix given; using', $suffix, 'for',
            $opt->{long}, '(value:', $val, ')');
      }
      if ( $suffix =~ m/[smhd]/ ) {
         $val = $suffix eq 's' ? $num            # Seconds
              : $suffix eq 'm' ? $num * 60       # Minutes
              : $suffix eq 'h' ? $num * 3600     # Hours
              :                  $num * 86400;   # Days
         $opt->{value} = ($prefix || '') . $val;
         MKDEBUG && _d('Setting option', $opt->{long}, 'to', $val);
      }
      else {
         $self->save_error("Invalid time suffix for --$opt->{long}");
      }
   }
   elsif ( $val && $opt->{type} eq 'd' ) {  # type DSN
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a DSN');
      my $prev = {};
      my $from_key = $self->{defaults_to}->{ $opt->{long} };
      if ( $from_key ) {
         MKDEBUG && _d($opt->{long}, 'DSN copies from', $from_key, 'DSN');
         if ( $self->{opts}->{$from_key}->{parsed} ) {
            $prev = $self->{opts}->{$from_key}->{value};
         }
         else {
            MKDEBUG && _d('Cannot parse', $opt->{long}, 'until',
               $from_key, 'parsed');
            return;
         }
      }
      my $defaults = $self->{DSNParser}->parse_options($self);
      $opt->{value} = $self->{DSNParser}->parse($val, $prev, $defaults);
   }
   elsif ( $val && $opt->{type} eq 'z' ) {  # type size
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a size value');
      $self->_parse_size($opt, $val);
   }
   elsif ( $opt->{type} eq 'H' || (defined $val && $opt->{type} eq 'h') ) {
      $opt->{value} = { map { $_ => 1 } split(/(?<!\\),\s*/, ($val || '')) };
   }
   elsif ( $opt->{type} eq 'A' || (defined $val && $opt->{type} eq 'a') ) {
      $opt->{value} = [ split(/(?<!\\),\s*/, ($val || '')) ];
   }
   else {
      MKDEBUG && _d('Nothing to validate for option',
         $opt->{long}, 'type', $opt->{type}, 'value', $val);
   }

   $opt->{parsed} = 1;
   return;
}

sub get {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{value};
}

sub got {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{got};
}

sub has {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   return defined $long ? exists $self->{opts}->{$long} : 0;
}

sub set {
   my ( $self, $opt, $val ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   $self->{opts}->{$long}->{value} = $val;
   return;
}

sub save_error {
   my ( $self, $error ) = @_;
   push @{$self->{errors}}, $error;
   return;
}

sub errors {
   my ( $self ) = @_;
   return $self->{errors};
}

sub usage {
   my ( $self ) = @_;
   warn "No usage string is set" unless $self->{usage}; # XXX
   return "Usage: " . ($self->{usage} || '') . "\n";
}

sub descr {
   my ( $self ) = @_;
   warn "No description string is set" unless $self->{description}; # XXX
   my $descr  = ($self->{description} || $self->{program_name} || '')
              . "  For more details, please use the --help option, "
              . "or try 'perldoc $PROGRAM_NAME' "
              . "for complete documentation.";
   $descr = join("\n", $descr =~ m/(.{0,80})(?:\s+|$)/g)
      unless $ENV{DONT_BREAK_LINES};
   $descr =~ s/ +$//mg;
   return $descr;
}

sub usage_or_errors {
   my ( $self, $file, $return ) = @_;
   $file ||= $self->{file} || __FILE__;

   if ( !$self->{description} || !$self->{usage} ) {
      MKDEBUG && _d("Getting description and usage from SYNOPSIS in", $file);
      my %synop = $self->_parse_synopsis($file);
      $self->{description} ||= $synop{description};
      $self->{usage}       ||= $synop{usage};
      MKDEBUG && _d("Description:", $self->{description},
         "\nUsage:", $self->{usage});
   }

   if ( $self->{opts}->{help}->{got} ) {
      print $self->print_usage() or die "Cannot print usage: $OS_ERROR";
      exit 0 unless $return;
   }
   elsif ( scalar @{$self->{errors}} ) {
      print $self->print_errors() or die "Cannot print errors: $OS_ERROR";
      exit 0 unless $return;
   }

   return;
}

sub print_errors {
   my ( $self ) = @_;
   my $usage = $self->usage() . "\n";
   if ( (my @errors = @{$self->{errors}}) ) {
      $usage .= join("\n  * ", 'Errors in command-line arguments:', @errors)
              . "\n";
   }
   return $usage . "\n" . $self->descr();
}

sub print_usage {
   my ( $self ) = @_;
   die "Run get_opts() before print_usage()" unless $self->{got_opts};
   my @opts = values %{$self->{opts}};

   my $maxl = max(
      map {
         length($_->{long})               # option long name
         + ($_->{is_negatable} ? 4 : 0)   # "[no]" if opt is negatable
         + ($_->{type} ? 2 : 0)           # "=x" where x is the opt type
      }
      @opts);

   my $maxs = max(0,
      map {
         length($_)
         + ($self->{opts}->{$_}->{is_negatable} ? 4 : 0)
         + ($self->{opts}->{$_}->{type} ? 2 : 0)
      }
      values %{$self->{short_opts}});

   my $lcol = max($maxl, ($maxs + 3));
   my $rcol = 80 - $lcol - 6;
   my $rpad = ' ' x ( 80 - $rcol );

   $maxs = max($lcol - 3, $maxs);

   my $usage = $self->descr() . "\n" . $self->usage();

   my @groups = reverse sort grep { $_ ne 'default'; } keys %{$self->{groups}};
   push @groups, 'default';

   foreach my $group ( reverse @groups ) {
      $usage .= "\n".($group eq 'default' ? 'Options' : $group).":\n\n";
      foreach my $opt (
         sort { $a->{long} cmp $b->{long} }
         grep { $_->{group} eq $group }
         @opts )
      {
         my $long  = $opt->{is_negatable} ? "[no]$opt->{long}" : $opt->{long};
         my $short = $opt->{short};
         my $desc  = $opt->{desc};

         $long .= $opt->{type} ? "=$opt->{type}" : "";

         if ( $opt->{type} && $opt->{type} eq 'm' ) {
            my ($s) = $desc =~ m/\(suffix (.)\)/;
            $s    ||= 's';
            $desc =~ s/\s+\(suffix .\)//;
            $desc .= ".  Optional suffix s=seconds, m=minutes, h=hours, "
                   . "d=days; if no suffix, $s is used.";
         }
         $desc = join("\n$rpad", grep { $_ } $desc =~ m/(.{0,$rcol})(?:\s+|$)/g);
         $desc =~ s/ +$//mg;
         if ( $short ) {
            $usage .= sprintf("  --%-${maxs}s -%s  %s\n", $long, $short, $desc);
         }
         else {
            $usage .= sprintf("  --%-${lcol}s  %s\n", $long, $desc);
         }
      }
   }

   $usage .= "\nOption types: s=string, i=integer, f=float, h/H/a/A=comma-separated list, d=DSN, z=size, m=time\n";

   if ( (my @rules = @{$self->{rules}}) ) {
      $usage .= "\nRules:\n\n";
      $usage .= join("\n", map { "  $_" } @rules) . "\n";
   }
   if ( $self->{DSNParser} ) {
      $usage .= "\n" . $self->{DSNParser}->usage();
   }
   $usage .= "\nOptions and values after processing arguments:\n\n";
   foreach my $opt ( sort { $a->{long} cmp $b->{long} } @opts ) {
      my $val   = $opt->{value};
      my $type  = $opt->{type} || '';
      my $bool  = $opt->{spec} =~ m/^[\w-]+(?:\|[\w-])?!?$/;
      $val      = $bool              ? ( $val ? 'TRUE' : 'FALSE' )
                : !defined $val      ? '(No value)'
                : $type eq 'd'       ? $self->{DSNParser}->as_string($val)
                : $type =~ m/H|h/    ? join(',', sort keys %$val)
                : $type =~ m/A|a/    ? join(',', @$val)
                :                    $val;
      $usage .= sprintf("  --%-${lcol}s  %s\n", $opt->{long}, $val);
   }
   return $usage;
}

sub prompt_noecho {
   shift @_ if ref $_[0] eq __PACKAGE__;
   my ( $prompt ) = @_;
   local $OUTPUT_AUTOFLUSH = 1;
   print $prompt
      or die "Cannot print: $OS_ERROR";
   my $response;
   eval {
      require Term::ReadKey;
      Term::ReadKey::ReadMode('noecho');
      chomp($response = <STDIN>);
      Term::ReadKey::ReadMode('normal');
      print "\n"
         or die "Cannot print: $OS_ERROR";
   };
   if ( $EVAL_ERROR ) {
      die "Cannot read response; is Term::ReadKey installed? $EVAL_ERROR";
   }
   return $response;
}

if ( MKDEBUG ) {
   print '# ', $^X, ' ', $], "\n";
   my $uname = `uname -a`;
   if ( $uname ) {
      $uname =~ s/\s+/ /g;
      print "# $uname\n";
   }
   printf("# %s  Ver %s Distrib %s Changeset %s line %d\n",
      $PROGRAM_NAME, ($main::VERSION || ''), ($main::DISTRIB || ''),
      ($main::SVN_REV || ''), __LINE__);
   print('# Arguments: ',
      join(' ', map { my $a = "_[$_]_"; $a =~ s/\n/\n# /g; $a; } @ARGV), "\n");
}

sub _read_config_file {
   my ( $self, $filename ) = @_;
   open my $fh, "<", $filename or die "Cannot open $filename: $OS_ERROR\n";
   my @args;
   my $prefix = '--';
   my $parse  = 1;

   LINE:
   while ( my $line = <$fh> ) {
      chomp $line;
      next LINE if $line =~ m/^\s*(?:\#|\;|$)/;
      $line =~ s/\s+#.*$//g;
      $line =~ s/^\s+|\s+$//g;
      if ( $line eq '--' ) {
         $prefix = '';
         $parse  = 0;
         next LINE;
      }
      if ( $parse
         && (my($opt, $arg) = $line =~ m/^\s*([^=\s]+?)(?:\s*=\s*(.*?)\s*)?$/)
      ) {
         push @args, grep { defined $_ } ("$prefix$opt", $arg);
      }
      elsif ( $line =~ m/./ ) {
         push @args, $line;
      }
      else {
         die "Syntax error in file $filename at line $INPUT_LINE_NUMBER";
      }
   }
   close $fh;
   return @args;
}

sub read_para_after {
   my ( $self, $file, $regex ) = @_;
   open my $fh, "<", $file or die "Can't open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';
   my $para;
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=pod$/m;
      last;
   }
   while ( $para = <$fh> ) {
      next unless $para =~ m/$regex/;
      last;
   }
   $para = <$fh>;
   chomp($para);
   close $fh or die "Can't close $file: $OS_ERROR";
   return $para;
}

sub clone {
   my ( $self ) = @_;

   my %clone = map {
      my $hashref  = $self->{$_};
      my $val_copy = {};
      foreach my $key ( keys %$hashref ) {
         my $ref = ref $hashref->{$key};
         $val_copy->{$key} = !$ref           ? $hashref->{$key}
                           : $ref eq 'HASH'  ? { %{$hashref->{$key}} }
                           : $ref eq 'ARRAY' ? [ @{$hashref->{$key}} ]
                           : $hashref->{$key};
      }
      $_ => $val_copy;
   } qw(opts short_opts defaults);

   foreach my $scalar ( qw(got_opts) ) {
      $clone{$scalar} = $self->{$scalar};
   }

   return bless \%clone;     
}

sub _parse_size {
   my ( $self, $opt, $val ) = @_;

   if ( lc($val || '') eq 'null' ) {
      MKDEBUG && _d('NULL size for', $opt->{long});
      $opt->{value} = 'null';
      return;
   }

   my %factor_for = (k => 1_024, M => 1_048_576, G => 1_073_741_824);
   my ($pre, $num, $factor) = $val =~ m/^([+-])?(\d+)([kMG])?$/;
   if ( defined $num ) {
      if ( $factor ) {
         $num *= $factor_for{$factor};
         MKDEBUG && _d('Setting option', $opt->{y},
            'to num', $num, '* factor', $factor);
      }
      $opt->{value} = ($pre || '') . $num;
   }
   else {
      $self->save_error("Invalid size for --$opt->{long}");
   }
   return;
}

sub _parse_attribs {
   my ( $self, $option, $attribs ) = @_;
   my $types = $self->{types};
   return $option
      . ($attribs->{'short form'} ? '|' . $attribs->{'short form'}   : '' )
      . ($attribs->{'negatable'}  ? '!'                              : '' )
      . ($attribs->{'cumulative'} ? '+'                              : '' )
      . ($attribs->{'type'}       ? '=' . $types->{$attribs->{type}} : '' );
}

sub _parse_synopsis {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   MKDEBUG && _d("Parsing SYNOPSIS in", $file);

   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $para;
   1 while defined($para = <$fh>) && $para !~ m/^=head1 SYNOPSIS/;
   die "$file does not contain a SYNOPSIS section" unless $para;
   my @synop;
   for ( 1..2 ) {  # 1 for the usage, 2 for the description
      my $para = <$fh>;
      push @synop, $para;
   }
   close $fh;
   MKDEBUG && _d("Raw SYNOPSIS text:", @synop);
   my ($usage, $desc) = @synop;
   die "The SYNOPSIS section in $file is not formatted properly"
      unless $usage && $desc;

   $usage =~ s/^\s*Usage:\s+(.+)/$1/;
   chomp $usage;

   $desc =~ s/\n/ /g;
   $desc =~ s/\s{2,}/ /g;
   $desc =~ s/\. ([A-Z][a-z])/.  $1/g;
   $desc =~ s/\s+$//;

   return (
      description => $desc,
      usage       => $usage,
   );
};

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End OptionParser package
# ###########################################################################

# ###########################################################################
# DSNParser package 7388
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/DSNParser.pm
#   trunk/common/t/DSNParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package DSNParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 0;
$Data::Dumper::Quotekeys = 0;

eval {
   require DBI;
};
my $have_dbi = $EVAL_ERROR ? 0 : 1;


sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(opts) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      opts => {}  # h, P, u, etc.  Should come from DSN OPTIONS section in POD.
   };
   foreach my $opt ( @{$args{opts}} ) {
      if ( !$opt->{key} || !$opt->{desc} ) {
         die "Invalid DSN option: ", Dumper($opt);
      }
      MKDEBUG && _d('DSN option:',
         join(', ',
            map { "$_=" . (defined $opt->{$_} ? ($opt->{$_} || '') : 'undef') }
               keys %$opt
         )
      );
      $self->{opts}->{$opt->{key}} = {
         dsn  => $opt->{dsn},
         desc => $opt->{desc},
         copy => $opt->{copy} || 0,
      };
   }
   return bless $self, $class;
}

sub prop {
   my ( $self, $prop, $value ) = @_;
   if ( @_ > 2 ) {
      MKDEBUG && _d('Setting', $prop, 'property');
      $self->{$prop} = $value;
   }
   return $self->{$prop};
}

sub parse {
   my ( $self, $dsn, $prev, $defaults ) = @_;
   if ( !$dsn ) {
      MKDEBUG && _d('No DSN to parse');
      return;
   }
   MKDEBUG && _d('Parsing', $dsn);
   $prev     ||= {};
   $defaults ||= {};
   my %given_props;
   my %final_props;
   my $opts = $self->{opts};

   foreach my $dsn_part ( split(/,/, $dsn) ) {
      if ( my ($prop_key, $prop_val) = $dsn_part =~  m/^(.)=(.*)$/ ) {
         $given_props{$prop_key} = $prop_val;
      }
      else {
         MKDEBUG && _d('Interpreting', $dsn_part, 'as h=', $dsn_part);
         $given_props{h} = $dsn_part;
      }
   }

   foreach my $key ( keys %$opts ) {
      MKDEBUG && _d('Finding value for', $key);
      $final_props{$key} = $given_props{$key};
      if (   !defined $final_props{$key}
           && defined $prev->{$key} && $opts->{$key}->{copy} )
      {
         $final_props{$key} = $prev->{$key};
         MKDEBUG && _d('Copying value for', $key, 'from previous DSN');
      }
      if ( !defined $final_props{$key} ) {
         $final_props{$key} = $defaults->{$key};
         MKDEBUG && _d('Copying value for', $key, 'from defaults');
      }
   }

   foreach my $key ( keys %given_props ) {
      die "Unknown DSN option '$key' in '$dsn'.  For more details, "
            . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
            . "for complete documentation."
         unless exists $opts->{$key};
   }
   if ( (my $required = $self->prop('required')) ) {
      foreach my $key ( keys %$required ) {
         die "Missing required DSN option '$key' in '$dsn'.  For more details, "
               . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
               . "for complete documentation."
            unless $final_props{$key};
      }
   }

   return \%final_props;
}

sub parse_options {
   my ( $self, $o ) = @_;
   die 'I need an OptionParser object' unless ref $o eq 'OptionParser';
   my $dsn_string
      = join(',',
          map  { "$_=".$o->get($_); }
          grep { $o->has($_) && $o->get($_) }
          keys %{$self->{opts}}
        );
   MKDEBUG && _d('DSN string made from options:', $dsn_string);
   return $self->parse($dsn_string);
}

sub as_string {
   my ( $self, $dsn, $props ) = @_;
   return $dsn unless ref $dsn;
   my %allowed = $props ? map { $_=>1 } @$props : ();
   return join(',',
      map  { "$_=" . ($_ eq 'p' ? '...' : $dsn->{$_})  }
      grep { defined $dsn->{$_} && $self->{opts}->{$_} }
      grep { !$props || $allowed{$_}                   }
      sort keys %$dsn );
}

sub usage {
   my ( $self ) = @_;
   my $usage
      = "DSN syntax is key=value[,key=value...]  Allowable DSN keys:\n\n"
      . "  KEY  COPY  MEANING\n"
      . "  ===  ====  =============================================\n";
   my %opts = %{$self->{opts}};
   foreach my $key ( sort keys %opts ) {
      $usage .= "  $key    "
             .  ($opts{$key}->{copy} ? 'yes   ' : 'no    ')
             .  ($opts{$key}->{desc} || '[No description]')
             . "\n";
   }
   $usage .= "\n  If the DSN is a bareword, the word is treated as the 'h' key.\n";
   return $usage;
}

sub get_cxn_params {
   my ( $self, $info ) = @_;
   my $dsn;
   my %opts = %{$self->{opts}};
   my $driver = $self->prop('dbidriver') || '';
   if ( $driver eq 'Pg' ) {
      $dsn = 'DBI:Pg:dbname=' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(h P));
   }
   else {
      $dsn = 'DBI:mysql:' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(F h P S A))
         . ';mysql_read_default_group=client';
   }
   MKDEBUG && _d($dsn);
   return ($dsn, $info->{u}, $info->{p});
}

sub fill_in_dsn {
   my ( $self, $dbh, $dsn ) = @_;
   my $vars = $dbh->selectall_hashref('SHOW VARIABLES', 'Variable_name');
   my ($user, $db) = $dbh->selectrow_array('SELECT USER(), DATABASE()');
   $user =~ s/@.*//;
   $dsn->{h} ||= $vars->{hostname}->{Value};
   $dsn->{S} ||= $vars->{'socket'}->{Value};
   $dsn->{P} ||= $vars->{port}->{Value};
   $dsn->{u} ||= $user;
   $dsn->{D} ||= $db;
}

sub get_dbh {
   my ( $self, $cxn_string, $user, $pass, $opts ) = @_;
   $opts ||= {};
   my $defaults = {
      AutoCommit         => 0,
      RaiseError         => 1,
      PrintError         => 0,
      ShowErrorStatement => 1,
      mysql_enable_utf8 => ($cxn_string =~ m/charset=utf8/i ? 1 : 0),
   };
   @{$defaults}{ keys %$opts } = values %$opts;

   if ( $opts->{mysql_use_result} ) {
      $defaults->{mysql_use_result} = 1;
   }

   if ( !$have_dbi ) {
      die "Cannot connect to MySQL because the Perl DBI module is not "
         . "installed or not found.  Run 'perl -MDBI' to see the directories "
         . "that Perl searches for DBI.  If DBI is not installed, try:\n"
         . "  Debian/Ubuntu  apt-get install libdbi-perl\n"
         . "  RHEL/CentOS    yum install perl-DBI\n"
         . "  OpenSolaris    pgk install pkg:/SUNWpmdbi\n";

   }

   my $dbh;
   my $tries = 2;
   while ( !$dbh && $tries-- ) {
      MKDEBUG && _d($cxn_string, ' ', $user, ' ', $pass, ' {',
         join(', ', map { "$_=>$defaults->{$_}" } keys %$defaults ), '}');

      eval {
         $dbh = DBI->connect($cxn_string, $user, $pass, $defaults);

         if ( $cxn_string =~ m/mysql/i ) {
            my $sql;

            $sql = 'SELECT @@SQL_MODE';
            MKDEBUG && _d($dbh, $sql);
            my ($sql_mode) = $dbh->selectrow_array($sql);

            $sql = 'SET @@SQL_QUOTE_SHOW_CREATE = 1'
                 . '/*!40101, @@SQL_MODE=\'NO_AUTO_VALUE_ON_ZERO'
                 . ($sql_mode ? ",$sql_mode" : '')
                 . '\'*/';
            MKDEBUG && _d($dbh, $sql);
            $dbh->do($sql);

            if ( my ($charset) = $cxn_string =~ m/charset=(\w+)/ ) {
               $sql = "/*!40101 SET NAMES $charset*/";
               MKDEBUG && _d($dbh, ':', $sql);
               $dbh->do($sql);
               MKDEBUG && _d('Enabling charset for STDOUT');
               if ( $charset eq 'utf8' ) {
                  binmode(STDOUT, ':utf8')
                     or die "Can't binmode(STDOUT, ':utf8'): $OS_ERROR";
               }
               else {
                  binmode(STDOUT) or die "Can't binmode(STDOUT): $OS_ERROR";
               }
            }

            if ( $self->prop('set-vars') ) {
               $sql = "SET " . $self->prop('set-vars');
               MKDEBUG && _d($dbh, ':', $sql);
               $dbh->do($sql);
            }
         }
      };
      if ( !$dbh && $EVAL_ERROR ) {
         MKDEBUG && _d($EVAL_ERROR);
         if ( $EVAL_ERROR =~ m/not a compiled character set|character set utf8/ ) {
            MKDEBUG && _d('Going to try again without utf8 support');
            delete $defaults->{mysql_enable_utf8};
         }
         elsif ( $EVAL_ERROR =~ m/locate DBD\/mysql/i ) {
            die "Cannot connect to MySQL because the Perl DBD::mysql module is "
               . "not installed or not found.  Run 'perl -MDBD::mysql' to see "
               . "the directories that Perl searches for DBD::mysql.  If "
               . "DBD::mysql is not installed, try:\n"
               . "  Debian/Ubuntu  apt-get install libdbd-mysql-perl\n"
               . "  RHEL/CentOS    yum install perl-DBD-MySQL\n"
               . "  OpenSolaris    pgk install pkg:/SUNWapu13dbd-mysql\n";
         }
         if ( !$tries ) {
            die $EVAL_ERROR;
         }
      }
   }

   MKDEBUG && _d('DBH info: ',
      $dbh,
      Dumper($dbh->selectrow_hashref(
         'SELECT DATABASE(), CONNECTION_ID(), VERSION()/*!50038 , @@hostname*/')),
      'Connection info:',      $dbh->{mysql_hostinfo},
      'Character set info:',   Dumper($dbh->selectall_arrayref(
                     'SHOW VARIABLES LIKE "character_set%"', { Slice => {}})),
      '$DBD::mysql::VERSION:', $DBD::mysql::VERSION,
      '$DBI::VERSION:',        $DBI::VERSION,
   );

   return $dbh;
}

sub get_hostname {
   my ( $self, $dbh ) = @_;
   if ( my ($host) = ($dbh->{mysql_hostinfo} || '') =~ m/^(\w+) via/ ) {
      return $host;
   }
   my ( $hostname, $one ) = $dbh->selectrow_array(
      'SELECT /*!50038 @@hostname, */ 1');
   return $hostname;
}

sub disconnect {
   my ( $self, $dbh ) = @_;
   MKDEBUG && $self->print_active_handles($dbh);
   $dbh->disconnect;
}

sub print_active_handles {
   my ( $self, $thing, $level ) = @_;
   $level ||= 0;
   printf("# Active %sh: %s %s %s\n", ($thing->{Type} || 'undef'), "\t" x $level,
      $thing, (($thing->{Type} || '') eq 'st' ? $thing->{Statement} || '' : ''))
      or die "Cannot print: $OS_ERROR";
   foreach my $handle ( grep {defined} @{ $thing->{ChildHandles} } ) {
      $self->print_active_handles( $handle, $level + 1 );
   }
}

sub copy {
   my ( $self, $dsn_1, $dsn_2, %args ) = @_;
   die 'I need a dsn_1 argument' unless $dsn_1;
   die 'I need a dsn_2 argument' unless $dsn_2;
   my %new_dsn = map {
      my $key = $_;
      my $val;
      if ( $args{overwrite} ) {
         $val = defined $dsn_1->{$key} ? $dsn_1->{$key} : $dsn_2->{$key};
      }
      else {
         $val = defined $dsn_2->{$key} ? $dsn_2->{$key} : $dsn_1->{$key};
      }
      $key => $val;
   } keys %{$self->{opts}};
   return \%new_dsn;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End DSNParser package
# ###########################################################################

# ###########################################################################
# VersionParser package 6667
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/VersionParser.pm
#   trunk/common/t/VersionParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package VersionParser;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub parse {
   my ( $self, $str ) = @_;
   my $result = sprintf('%03d%03d%03d', $str =~ m/(\d+)/g);
   MKDEBUG && _d($str, 'parses to', $result);
   return $result;
}

sub version_ge {
   my ( $self, $dbh, $target ) = @_;
   if ( !$self->{$dbh} ) {
      $self->{$dbh} = $self->parse(
         $dbh->selectrow_array('SELECT VERSION()'));
   }
   my $result = $self->{$dbh} ge $self->parse($target) ? 1 : 0;
   MKDEBUG && _d($self->{$dbh}, 'ge', $target, ':', $result);
   return $result;
}

sub innodb_version {
   my ( $self, $dbh ) = @_;
   return unless $dbh;
   my $innodb_version = "NO";

   my ($innodb) =
      grep { $_->{engine} =~ m/InnoDB/i }
      map  {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         \%hash;
      }
      @{ $dbh->selectall_arrayref("SHOW ENGINES", {Slice=>{}}) };
   if ( $innodb ) {
      MKDEBUG && _d("InnoDB support:", $innodb->{support});
      if ( $innodb->{support} =~ m/YES|DEFAULT/i ) {
         my $vars = $dbh->selectrow_hashref(
            "SHOW VARIABLES LIKE 'innodb_version'");
         $innodb_version = !$vars ? "BUILTIN"
                         :          ($vars->{Value} || $vars->{value});
      }
      else {
         $innodb_version = $innodb->{support};  # probably DISABLED or NO
      }
   }

   MKDEBUG && _d("InnoDB version:", $innodb_version);
   return $innodb_version;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End VersionParser package
# ###########################################################################

# ###########################################################################
# Daemon package 6255
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Daemon.pm
#   trunk/common/t/Daemon.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Daemon;

use strict;
use warnings FATAL => 'all';

use POSIX qw(setsid);
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(o) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o = $args{o};
   my $self = {
      o        => $o,
      log_file => $o->has('log') ? $o->get('log') : undef,
      PID_file => $o->has('pid') ? $o->get('pid') : undef,
   };

   check_PID_file(undef, $self->{PID_file});

   MKDEBUG && _d('Daemonized child will log to', $self->{log_file});
   return bless $self, $class;
}

sub daemonize {
   my ( $self ) = @_;

   MKDEBUG && _d('About to fork and daemonize');
   defined (my $pid = fork()) or die "Cannot fork: $OS_ERROR";
   if ( $pid ) {
      MKDEBUG && _d('I am the parent and now I die');
      exit;
   }

   $self->{PID_owner} = $PID;
   $self->{child}     = 1;

   POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
   chdir '/'       or die "Cannot chdir to /: $OS_ERROR";

   $self->_make_PID_file();

   $OUTPUT_AUTOFLUSH = 1;

   if ( -t STDIN ) {
      close STDIN;
      open  STDIN, '/dev/null'
         or die "Cannot reopen STDIN to /dev/null: $OS_ERROR";
   }

   if ( $self->{log_file} ) {
      close STDOUT;
      open  STDOUT, '>>', $self->{log_file}
         or die "Cannot open log file $self->{log_file}: $OS_ERROR";

      close STDERR;
      open  STDERR, ">&STDOUT"
         or die "Cannot dupe STDERR to STDOUT: $OS_ERROR"; 
   }
   else {
      if ( -t STDOUT ) {
         close STDOUT;
         open  STDOUT, '>', '/dev/null'
            or die "Cannot reopen STDOUT to /dev/null: $OS_ERROR";
      }
      if ( -t STDERR ) {
         close STDERR;
         open  STDERR, '>', '/dev/null'
            or die "Cannot reopen STDERR to /dev/null: $OS_ERROR";
      }
   }

   MKDEBUG && _d('I am the child and now I live daemonized');
   return;
}

sub check_PID_file {
   my ( $self, $file ) = @_;
   my $PID_file = $self ? $self->{PID_file} : $file;
   MKDEBUG && _d('Checking PID file', $PID_file);
   if ( $PID_file && -f $PID_file ) {
      my $pid;
      eval { chomp($pid = `cat $PID_file`); };
      die "Cannot cat $PID_file: $OS_ERROR" if $EVAL_ERROR;
      MKDEBUG && _d('PID file exists; it contains PID', $pid);
      if ( $pid ) {
         my $pid_is_alive = kill 0, $pid;
         if ( $pid_is_alive ) {
            die "The PID file $PID_file already exists "
               . " and the PID that it contains, $pid, is running";
         }
         else {
            warn "Overwriting PID file $PID_file because the PID that it "
               . "contains, $pid, is not running";
         }
      }
      else {
         die "The PID file $PID_file already exists but it does not "
            . "contain a PID";
      }
   }
   else {
      MKDEBUG && _d('No PID file');
   }
   return;
}

sub make_PID_file {
   my ( $self ) = @_;
   if ( exists $self->{child} ) {
      die "Do not call Daemon::make_PID_file() for daemonized scripts";
   }
   $self->_make_PID_file();
   $self->{PID_owner} = $PID;
   return;
}

sub _make_PID_file {
   my ( $self ) = @_;

   my $PID_file = $self->{PID_file};
   if ( !$PID_file ) {
      MKDEBUG && _d('No PID file to create');
      return;
   }

   $self->check_PID_file();

   open my $PID_FH, '>', $PID_file
      or die "Cannot open PID file $PID_file: $OS_ERROR";
   print $PID_FH $PID
      or die "Cannot print to PID file $PID_file: $OS_ERROR";
   close $PID_FH
      or die "Cannot close PID file $PID_file: $OS_ERROR";

   MKDEBUG && _d('Created PID file:', $self->{PID_file});
   return;
}

sub _remove_PID_file {
   my ( $self ) = @_;
   if ( $self->{PID_file} && -f $self->{PID_file} ) {
      unlink $self->{PID_file}
         or warn "Cannot remove PID file $self->{PID_file}: $OS_ERROR";
      MKDEBUG && _d('Removed PID file');
   }
   else {
      MKDEBUG && _d('No PID to remove');
   }
   return;
}

sub DESTROY {
   my ( $self ) = @_;

   $self->_remove_PID_file() if ($self->{PID_owner} || 0) == $PID;

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Daemon package
# ###########################################################################

# ###########################################################################
# PodParser package 7053
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/PodParser.pm
#   trunk/common/t/PodParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package PodParser;


use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

my %parse_items_from = (
   'OPTIONS'     => 1,
   'DSN OPTIONS' => 1,
   'RULES'       => 1,
);

my %item_pattern_for = (
   'OPTIONS'     => qr/--(.*)/,
   'DSN OPTIONS' => qr/\* (.)/,
   'RULES'       => qr/(.*)/,
);

my %section_has_rules = (
   'OPTIONS'     => 1,
   'DSN OPTIONS' => 0,
   'RULES'       => 0,
);

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      current_section => '',
      current_item    => '',
      in_list         => 0,
      items           => {},  # keyed off SECTION
      magic           => {},  # keyed off SECTION->magic ident (without MAGIC_)
      magic_ident     => '',  # set when next para is a magic para
   };
   return bless $self, $class;
}
 
sub get_items {
   my ( $self, $section ) = @_;
   return $section ? $self->{items}->{$section} : $self->{items};
}

sub get_magic {
   my ( $self, $section ) = @_;
   return $section ? $self->{magic}->{$section} : $self->{magic};
}

sub parse_from_file {
   my ( $self, $file ) = @_;
   return unless $file;

   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   my $para;

   1 while defined($para = <$fh>) && $para !~ m/^=pod/;
   die "$file does not contain =pod" unless $para;

   while ( defined($para = <$fh>) && $para !~ m/^=cut/ ) {
      if ( $para =~ m/^=(head|item|over|back)/ ) {
         my ($cmd, $name) = $para =~ m/^=(\w+)(?:\s+(.+))?/;
         $name ||= '';
         MKDEBUG && _d('cmd:', $cmd, 'name:', $name);
         $self->command($cmd, $name);
      }
      else {
         $self->textblock($para);
      }
   }

   close $fh;
}

sub command {
   my ( $self, $cmd, $name ) = @_;
   
   $name =~ s/\s+\Z//m;  # Remove \n and blank line after name.
   
   if  ( $cmd eq 'head1' && $parse_items_from{$name} ) {
      MKDEBUG && _d('In section', $name);
      $self->{current_section} = $name;
      $self->{items}->{$name}  = {};
   }
   elsif ( $cmd eq 'over' ) {
      MKDEBUG && _d('Start items in', $self->{current_section});
      $self->{in_list} = 1;
   }
   elsif ( $cmd eq 'item' ) {
      my $pat = $item_pattern_for{ $self->{current_section} };
      my ($item) = $name =~ m/$pat/;
      if ( $item ) {
         MKDEBUG && _d($self->{current_section}, 'item:', $item);
         $self->{items}->{ $self->{current_section} }->{$item} = {
            desc => '',  # every item should have a desc
         };
         $self->{current_item} = $item;
      }
      else {
         warn "Item $name does not match $pat";
      }
   }
   elsif ( $cmd eq '=back' ) {
      MKDEBUG && _d('End items');
      $self->{in_list} = 0;
   }
   else {
      $self->{current_section} = '';
      $self->{in_list}         = 0;
   }
   
   return;
}

sub textblock {
   my ( $self, $para ) = @_;

   return unless $self->{current_section} && $self->{current_item};

   my $section = $self->{current_section};
   my $item    = $self->{items}->{$section}->{ $self->{current_item} };

   $para =~ s/\s+\Z//;

   if ( $para =~ m/^[a-z]\w+[:;] / ) {
      MKDEBUG && _d('Item attributes:', $para);
      map {
         my ($attrib, $val) = split(/: /, $_);
         $item->{$attrib} = defined $val ? $val : 1;
      } split(/; /, $para);
   }
   else {
      if ( $self->{magic_ident} ) {

         my ($leading_space) = $para =~ m/^(\s+)/;
         my $indent          = length($leading_space || '');
         if ( $indent ) {
            $para =~ s/^\s{$indent}//mg;
            $para =~ s/\s+$//;
            MKDEBUG && _d("MAGIC", $self->{magic_ident}, "para:", $para);
            $self->{magic}->{$self->{current_section}}->{$self->{magic_ident}}
               = $para;
         }
         else {
            MKDEBUG && _d("MAGIC", $self->{magic_ident},
               "para is not indented; treating as normal para");
         }

         $self->{magic_ident} = '';  # must unset this!
      }

      MKDEBUG && _d('Item desc:', substr($para, 0, 40),
         length($para) > 40 ? '...' : '');
      $para =~ s/\n+/ /g;
      $item->{desc} .= $para;

      if ( $para =~ m/MAGIC_(\w+)/ ) {
         $self->{magic_ident} = $1;  # XXX
         MKDEBUG && _d("MAGIC", $self->{magic_ident}, "follows");
      }
   }

   return;
}

sub verbatim {
   my ( $self, $para ) = @_;
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End PodParser package
# ###########################################################################

# ###########################################################################
# TextResultSetParser package 6898
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TextResultSetParser.pm
#   trunk/common/t/TextResultSetParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TextResultSetParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my %value_for = (
      'NULL' => undef,  # DBI::selectall_arrayref() does this
      ($args{value_for} ? %{$args{value_for}} : ()),
   );
   my $self = {
      %args,
      value_for => \%value_for,
   };
   return bless $self, $class;
}

sub _parse_tabular {
   my ( $text, @cols ) = @_;
   my %row;
   my @vals = $text =~ m/\| +([^\|]*?)(?= +\|)/msg;
   return (undef, \@vals) unless @cols;
   @row{@cols} = @vals;
   return (\%row, undef);
}

sub _parse_tab_sep {
   my ( $text, @cols ) = @_;
   my %row;
   my @vals = split(/\t/, $text);
   return (undef, \@vals) unless @cols;
   @row{@cols} = @vals;
   return (\%row, undef);
}

sub parse_vertical_row {
   my ( $self, $text ) = @_;
   my %row = $text =~ m/^\s*(\w+):(?: ([^\n]*))?/msg;
   if ( $self->{NAME_lc} ) {
      my %lc_row = map {
         my $key = lc $_;
         $key => $row{$_};
      } keys %row;
      return \%lc_row;
   }
   else {
      return \%row;
   }
}

sub parse {
   my ( $self, $text ) = @_;
   my $result_set;

   if ( $text =~ m/^\+---/m ) { # standard "tabular" output
      MKDEBUG && _d('Result set text is standard tabular');
      my $line_pattern  = qr/^(\| .*)[\r\n]+/m;
      $result_set
         = $self->parse_horizontal_row($text, $line_pattern, \&_parse_tabular);
   }
   elsif ( $text =~ m/^\w+\t\w+/m ) { # tab-separated
      MKDEBUG && _d('Result set text is tab-separated');
      my $line_pattern  = qr/^(.*?\t.*)[\r\n]+/m;
      $result_set
         = $self->parse_horizontal_row($text, $line_pattern, \&_parse_tab_sep);
   }
   elsif ( $text =~ m/\*\*\* \d+\. row/ ) { # "vertical" output
      MKDEBUG && _d('Result set text is vertical (\G)');
      foreach my $row ( split_vertical_rows($text) ) {
         push @$result_set, $self->parse_vertical_row($row);
      }
   }
   else {
      my $text_sample = substr $text, 0, 300;
      my $remaining   = length $text > 300 ? (length $text) - 300 : 0;
      chomp $text_sample;
      die "Cannot determine if text is tabular, tab-separated or vertical:\n"
         . "$text_sample\n"
         . ($remaining ? "(not showing last $remaining bytes of text)\n" : "");
   }

   if ( $self->{value_for} ) {
      foreach my $result_set ( @$result_set ) {
         foreach my $key ( keys %$result_set ) {
            next unless defined $result_set->{$key};
            $result_set->{$key} = $self->{value_for}->{ $result_set->{$key} }
               if exists $self->{value_for}->{ $result_set->{$key} };
         }
      }
   }

   return $result_set;
}


sub parse_horizontal_row {
   my ( $self, $text, $line_pattern, $sub ) = @_;
   my @result_sets = ();
   my @cols        = ();
   foreach my $line ( $text =~ m/$line_pattern/g ) {
      my ( $row, $cols ) = $sub->($line, @cols);
      if ( $row ) {
         push @result_sets, $row;
      }
      else {
         @cols = map { $self->{NAME_lc} ? lc $_ : $_ } @$cols;
      }
   }
   return \@result_sets;
}

sub split_vertical_rows {
   my ( $text ) = @_;
   my $ROW_HEADER = '\*{3,} \d+\. row \*{3,}';
   my @rows = $text =~ m/($ROW_HEADER.*?)(?=$ROW_HEADER|\z)/omgs;
   return @rows;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TextResultSetParser package
# ###########################################################################

# ###########################################################################
# Advisor package 6830
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Advisor.pm
#   trunk/common/t/Advisor.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Advisor;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(match_type) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      %args,
      rules          => [],  # Rules from all advisor modules.
      rule_index_for => {},  # Maps rules by ID to their array index in $rules.
      rule_info      => {},  # ID, severity, description, etc. for each rule.
   };

   return bless $self, $class;
}

sub load_rules {
   my ( $self, $advisor ) = @_;
   return unless $advisor;
   MKDEBUG && _d('Loading rules from', ref $advisor);

   my $i = scalar @{$self->{rules}};

   RULE:
   foreach my $rule ( $advisor->get_rules() ) {
      my $id = $rule->{id};
      if ( $self->{ignore_rules}->{"$id"} ) {
         MKDEBUG && _d("Ignoring rule", $id);
         next RULE;
      }
      die "Rule $id already exists and cannot be redefined"
         if defined $self->{rule_index_for}->{$id};
      push @{$self->{rules}}, $rule;
      $self->{rule_index_for}->{$id} = $i++;
   }

   return;
}

sub load_rule_info {
   my ( $self, $advisor ) = @_;
   return unless $advisor;
   MKDEBUG && _d('Loading rule info from', ref $advisor);
   my $rules = $self->{rules};
   foreach my $rule ( @$rules ) {
      my $id = $rule->{id};
      if ( $self->{ignore_rules}->{"$id"} ) {
         die "Rule $id was loaded but should be ignored";
      }
      my $rule_info = $advisor->get_rule_info($id);
      next unless $rule_info;
      die "Info for rule $id already exists and cannot be redefined"
         if $self->{rule_info}->{$id};
      $self->{rule_info}->{$id} = $rule_info;
   }
   return;
}


sub run_rules {
   my ( $self, %args ) = @_;
   my @matched_rules;
   my @matched_pos;
   my $rules      = $self->{rules};
   my $match_type = lc $self->{match_type};
   foreach my $rule ( @$rules ) {
      eval {
         my $match = $rule->{code}->(%args);
         if ( $match_type eq 'pos' ) {
            if ( defined $match ) {
               MKDEBUG && _d('Matches rule', $rule->{id}, 'near pos', $match);
               push @matched_rules, $rule->{id};
               push @matched_pos,   $match;
            }
         }
         elsif ( $match_type eq 'bool' ) {
            if ( $match ) {
               MKDEBUG && _d("Matches rule", $rule->{id});
               push @matched_rules, $rule->{id};
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Code for rule $rule->{id} caused an error: $EVAL_ERROR";
      }
   }
   return \@matched_rules, \@matched_pos;
};


sub get_rule_info {
   my ( $self, $id ) = @_;
   return unless $id;
   return $self->{rule_info}->{$id};
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Advisor package
# ###########################################################################

# ###########################################################################
# AdvisorRules package 6813
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/AdvisorRules.pm
#   trunk/common/t/AdvisorRules.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package AdvisorRules;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(PodParser) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      rules     => [],
      rule_info => {},
   };
   return bless $self, $class;
}

sub load_rule_info {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(file section ) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $rules = $args{rules} || $self->{rules};
   my $p     = $self->{PodParser};

   $p->parse_from_file($args{file});
   my $rule_items = $p->get_items($args{section});
   my %seen;
   foreach my $rule_id ( keys %$rule_items ) {
      my $rule = $rule_items->{$rule_id};
      die "Rule $rule_id has no description" unless $rule->{desc};
      die "Rule $rule_id has no severity"    unless $rule->{severity};
      die "Rule $rule_id is already defined"
         if exists $self->{rule_info}->{$rule_id};
      $self->{rule_info}->{$rule_id} = {
         id          => $rule_id,
         severity    => $rule->{severity},
         description => $rule->{desc},
      };
   }

   foreach my $rule ( @$rules ) {
      die "There is no info for rule $rule->{id} in $args{file}"
         unless $self->{rule_info}->{ $rule->{id} };
   }

   return;
}

sub get_rule_info {
   my ( $self, $id ) = @_;
   return unless $id;
   return $self->{rule_info}->{$id};
}

sub _reset_rule_info {
   my ( $self ) = @_;
   $self->{rule_info} = {};
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End AdvisorRules package
# ###########################################################################

# ###########################################################################
# VariableAdvisorRules package 6821
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/VariableAdvisorRules.pm
#   trunk/common/t/VariableAdvisorRules.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package VariableAdvisorRules;
use base 'AdvisorRules';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(%args);
   @{$self->{rules}} = $self->get_rules();
   MKDEBUG && _d(scalar @{$self->{rules}}, "rules");
   return $self;
}

sub get_rules {
   return
   {
      id   => 'auto_increment',
      code => sub {
         my ( %args ) = @_;
         my $vars = $args{variables};
         return unless defined $vars->{auto_increment_increment}
            && defined $vars->{auto_increment_offset};
         return    $vars->{auto_increment_increment} != 1
                || $vars->{auto_increment_offset}    != 1 ? 1 : 0;
      },
   },
   {
      id   => 'concurrent_insert',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{concurrent_insert}, 1);
      },
   },
   {
      id   => 'connect_timeout',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{connect_timeout}, 10);
      },
   },
   {
      id   => 'debug',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{debug} ? 1 : 0;
      },
   },
   {
      id   => 'delay_key_write',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{delay_key_write}, "ON");
      },
   },
   {
      id   => 'flush',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{flush}, "ON");
      },
   },
   {
      id   => 'flush_time',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{flush_time}, 0);
      },
   },
   {
      id   => 'have_bdb',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{have_bdb}, 'YES');
      },
   },
   {
      id   => 'init_connect',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{init_connect} ? 1 : 0;
      },
   },
   {
      id   => 'init_file',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{init_file} ? 1 : 0;
      },
   },
   {
      id   => 'init_slave',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{init_slave} ? 1 : 0;
      },
   },
   {
      id   => 'innodb_additional_mem_pool_size',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_additional_mem_pool_size},
            20 * 1_048_576);  # 20M
      },
   },
   {
      id   => 'innodb_buffer_pool_size',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{innodb_buffer_pool_size},
            10 * 1_048_576);  # 10M
      },
   },
   {
      id   => 'innodb_checksums',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_checksums}, "ON");
      },
   },
   {
      id   => 'innodb_doublewrite',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_doublewrite}, "ON");
      },
   },
   {
      id   => 'innodb_fast_shutdown',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{innodb_fast_shutdown}, 1);
      },
   },
   {
      id   => 'innodb_flush_log_at_trx_commit-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{innodb_flush_log_at_trx_commit}, 1);
      },
   },
   {
      id   => 'innodb_flush_log_at_trx_commit-2',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{innodb_flush_log_at_trx_commit}, 0);
      },
   },
   {
      id   => 'innodb_force_recovery',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_force_recovery}, 0);
      },
   },
   {
      id   => 'innodb_lock_wait_timeout',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_lock_wait_timeout}, 50);
      },
   },
   {
      id   => 'innodb_log_buffer_size',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{innodb_log_buffer_size},
            16 * 1_048_576);  # 16M
      },
   },
   {
      id   => 'innodb_log_file_size',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{innodb_log_file_size},
            5 * 1_048_576);  # 5M
      },
   },
   {
      id   => 'innodb_max_dirty_pages_pct',
      code => sub {
         my ( %args ) = @_;
         return _var_lt($args{variables}->{innodb_max_dirty_pages_pct}, 90);
      },
   },
   {
      id   => 'key_buffer_size',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{key_buffer_size},
            8 * 1_048_576);  # 8M
      },
   },
   {
      id   => 'large_pages',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{large_pages}, "ON");
      },
   },
   {
      id   => 'locked_in_memory',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{locked_in_memory}, "ON");
      },
   },
   {
      id   => 'log_warnings-1',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{log_warnings}, 0);
      },
   },
   {
      id   => 'log_warnings-2',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{log_warnings}, 1);
      },
   },
   {
      id   => 'low_priority_updates',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{low_priority_updates}, "ON");
      },
   },
   {
      id   => 'max_binlog_size',
      code => sub {
         my ( %args ) = @_;
         return _var_lt($args{variables}->{max_binlog_size},
            1 * 1_073_741_824);  # 1G
      },
   },
   {
      id   => 'max_connect_errors',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{max_connect_errors}, 10);
      },
   },
   {
      id   => 'max_connections',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{max_connections}, 1_000);
      },
   },

   {
      id   => 'myisam_repair_threads',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{myisam_repair_threads}, 1);
      },
   },
   {
      id   => 'old_passwords',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{old_passwords}, "ON");
      },
   },
   {
      id   => 'optimizer_prune_level',
      code => sub {
         my ( %args ) = @_;
         return _var_lt($args{variables}->{optimizer_prune_level}, 1);
      },
   },
   {
      id   => 'port',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{port}, 3306);
      },
   },
   {
      id   => 'query_cache_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{query_cache_size},
            128 * 1_048_576);  # 128M
      },
   },
   {
      id   => 'query_cache_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{query_cache_size},
            512 * 1_048_576);  # 512M
      },
   },
   {
      id   => 'read_buffer_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{read_buffer_size}, 131_072);
      },
   },
   {
      id   => 'read_buffer_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{read_buffer_size},
            8 * 1_048_576);  # 8M
      },
   },
   {
      id   => 'read_rnd_buffer_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{read_rnd_buffer_size}, 262_144);
      },
   },
   {
      id   => 'read_rnd_buffer_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{read_rnd_buffer_size},
            4 * 1_048_576);  # 4M
      },
   },
   {
      id   => 'relay_log_space_limit',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{relay_log_space_limit}, 0);
      },
   },
   
   {
      id   => 'slave_net_timeout',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{slave_net_timeout}, 60);
      },
   },
   {
      id   => 'slave_skip_errors',
      code => sub {
         my ( %args ) = @_;
         return $args{variables}->{slave_skip_errors}
             && $args{variables}->{slave_skip_errors} ne 'OFF' ? 1 : 0;
      },
   },
   {
      id   => 'sort_buffer_size-1',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{sort_buffer_size}, 2_097_144);
      },
   },
   {
      id   => 'sort_buffer_size-2',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{sort_buffer_size},
            4 * 1_048_576);  # 4M
      },
   },
   {
      id   => 'sql_notes',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{sql_notes}, "OFF");
      },
   },
   {
      id   => 'sync_frm',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{sync_frm}, "ON");
      },
   },
   {
      id   => 'tx_isolation-1',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{tx_isolation}, "REPEATABLE-READ");
      },
   },
   {
      id   => 'tx_isolation-2',
      code => sub {
         my ( %args ) = @_;
         return
               _var_sneq($args{variables}->{tx_isolation}, "REPEATABLE-READ")
            && _var_sneq($args{variables}->{tx_isolation}, "READ-COMMITTED")
            ? 1 : 0;
      },
   },
   {
      id   => 'expire_log_days',
      code => sub {
         my ( %args ) = @_;
         return _var_eq($args{variables}->{expire_log_days}, 0)
            && $args{variables}->{log_bin} ? 1 : 0;
      },
   },
   {
      id   => 'innodb_file_io_threads',
      code => sub {
         my ( %args ) = @_;
         return _var_neq($args{variables}->{innodb_file_io_threads}, 4)
            && $OSNAME ne 'MSWin32' ? 1 : 0;
      },
   },
   {
      id   => 'innodb_data_file_path',
      code => sub {
         my ( %args ) = @_;
         return
            ($args{variables}->{innodb_data_file_path} || '') =~ m/autoextend/
            ? 1 : 0;
      },
   },
   {
      id   => 'innodb_flush_method',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_flush_method}, 'O_DIRECT')
            && $OSNAME ne 'MSWin32' ? 1 : 0;
      },
   },
   {
      id   => 'innodb_locks_unsafe_for_binlog',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{innodb_locks_unsafe_for_binlog},
            "ON") && $args{variables}->{log_bin} ? 1 : 0;
      },
   },
   {
      id   => 'innodb_support_xa',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{innodb_support_xa}, "ON")
            && $args{variables}->{log_bin} ? 1 : 0;
      },
   },
   {
      id   => 'log_bin',
      code => sub {
         my ( %args ) = @_;
         return _var_sneq($args{variables}->{log_bin}, "ON");
      },
   },
   {
      id   => 'log_output',
      code => sub {
         my ( %args ) = @_;
         return ($args{variables}->{log_output} || '') =~ m/TABLE/i ? 1 : 0;
      },
   },
   {
      id   => 'max_relay_log_size',
      code => sub {
         my ( %args ) = @_;
         return _var_gt($args{variables}->{max_relay_log_size}, 0)
            &&  _var_lt($args{variables}->{max_relay_log_size},
                  1 * 1_073_741_824)  ? 1 : 0;
      },
   },
   {
      id   => 'myisam_recover_options',
      code => sub {
         my ( %args ) = @_;
         return _var_seq($args{variables}->{myisam_recover_options}, "OFF")
            ||  _var_seq($args{variables}->{myisam_recover_options}, "DEFAULT")
               ? 1 : 0;
      },
   },
   {
      id   => 'storage_engine',
      code => sub {
         my ( %args ) = @_;
         return 0 unless $args{variables}->{storage_engine};
         return $args{variables}->{storage_engine} !~ m/InnoDB|MyISAM/i ? 1 : 0;
      },
   },
   {
      id   => 'sync_binlog',
      code => sub {
         my ( %args ) = @_;
         return
            $args{variables}->{log_bin}
            && (   _var_eq($args{variables}->{sync_binlog}, 0)
                || _var_gt($args{variables}->{sync_binlog}, 1)) ? 1 : 0;
      },
   },
   {
      id   => 'tmp_table_size',
      code => sub {
         my ( %args ) = @_;
         return ($args{variables}->{tmp_table_size} || 0)
              > ($args{variables}->{max_heap_table_size} || 0) ? 1 : 0;
      },
   },
   {
      id   => 'old mysql version',
      code => sub {
         my ( %args ) = @_;
         my $mysql_version = $args{mysql_version};
         return 0 unless $mysql_version;
         my ($major, $minor, $patch) = $mysql_version =~ m/(\d{3})/g;
         if ( $major eq '003' ) {
            return $mysql_version lt '003023000' ? 1 : 0;  # 3.23.x
         }
         elsif ( $major eq '004' ) {
            return $mysql_version lt '004001020' ? 1 : 0;  # 4.1.20
         }
         elsif ( $major eq '005' ) {
            if ( $minor eq '000' ) {
               return $mysql_version lt '005000037' ? 1 : 0;  # 5.0.37
            }
            elsif ( $minor eq '001' ) {
               return $mysql_version lt '005001030' ? 1 : 0;  # 5.1.30
            }
            else {
               return 0;
            }
         }
         else {
            return 0;
         }
      },
   },
   {
      id   => 'end-of-life mysql version',
      code => sub {
         my ( %args ) = @_;
         my $mysql_version = $args{mysql_version};
         return 0 unless $mysql_version;
         return $mysql_version lt '005001000' ? 1 : 0;  # 5.1.x
      },
   },
};

sub _var_gt {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var > $val ? 1 : 0;
}

sub _var_lt {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var < $val ? 1 : 0;
}

sub _var_eq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var == $val ? 1 : 0;
}

sub _var_neq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return _var_eq($var, $val) ? 0 : 1;
}

sub _var_seq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return $var eq $val ? 1 : 0;
}

sub _var_sneq {
   my ($var, $val) = @_;
   return 0 unless defined $var;
   return _var_seq($var, $val) ? 0 : 1;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End VariableAdvisorRules package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_variable_advisor;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   my $vars_from         = $o->get('source-of-variables');
   # my $status_from       = lc $o->get('source-of-status');
   # my $slave_status_from = lc $o->get('source-of-slave-status');

   my $need_dbh = $vars_from =~ m/^mysql$/i; # || $status_from eq 'mysql' etc.

   if ( !$o->get('help') ) {
      if ( $vars_from =~ m/^mysql$/i && @ARGV == 0 ) {
         $o->save_error("A DSN must be specified when --source-of-variables=mysql");
      }
   }

   $o->usage_or_errors();

   # #########################################################################
   # Check that any files given exit.
   # #########################################################################
   if ( $vars_from !~ m/^mysql|none^/i ) {
      die "The --source-of-variables file $vars_from does not exist"
         unless -f $vars_from;
   }

   # #########################################################################
   # Load rules from POD and plugins.
   # #########################################################################
   my $p   = new PodParser();
   my $var = new VariableAdvisorRules(PodParser => $p);
   my $adv = new Advisor(
      match_type   => "bool",
      ignore_rules => $o->get('ignore-rules'),
   );

   $var->load_rule_info(
      file    => __FILE__,
      section => 'RULES',
   );
   $adv->load_rules($var);
   $adv->load_rule_info($var);

   # TODO: load rules from plugins

   # #########################################################################
   # Make common modules.
   # #########################################################################
   my $vp  = new VersionParser();
   my $trp = new TextResultSetParser();
   my %common_modules = (
      OptionParser        => $o,
      DSNParser           => $dp,
      TextResultSetParser => $trp,
      VersionParser       => $vp,
   );

   # ##########################################################################
   # Connect to MySQL if any of the input sources is mysql.
   # ##########################################################################
   my $dbh;
   if ( $need_dbh ) {
      my $dsn_defaults = $dp->parse_options($o);
      my $dsn          = $dp->parse(shift @ARGV, $dsn_defaults);

      if ( $o->get('ask-pass') ) {
         $dsn->{p} = OptionParser::prompt_noecho("Enter password: ");
      }

      $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), {AutoCommit => 1});
      $dbh->{FetchHashKeyName} = 'NAME_lc';
      MKDEBUG && _d('Connected dbh', $dbh);
   }

   # ########################################################################
   # Daemonize now that everything is setup and ready to work.
   # ########################################################################
   my $daemon;
   if ( $o->get('daemonize') ) {
      $daemon = new Daemon(o=>$o);
      $daemon->daemonize();
      MKDEBUG && _d('I am a daemon now');
   }
   elsif ( $o->get('pid') ) {
      # We're not daemoninzing, it just handles PID stuff.
      $daemon = new Daemon(o=>$o);
      $daemon->make_PID_file();
   }

   # #########################################################################
   # Get the variables and other MySQL info to pass to rules.
   # #########################################################################
   my $vars = get_variables(
      source => $vars_from,
      dbh    => $dbh,
      %common_modules,
   );

   my $mysql_version  = $vp->parse($vars->{version});
   my $innodb_version = $vp->innodb_version($dbh);
   MKDEBUG && _d("MySQL version", $mysql_version,
      "InnoDB version", $innodb_version);

   # #########################################################################
   # Run rules, print advice.
   # #########################################################################
   my ($advice) = $adv->run_rules(
      variables      => $vars,
      mysql_version  => $mysql_version,
      innodb_version => $innodb_version,
      %common_modules,
   );

   print_advice(
      advice  => $advice,
      Advisor => $adv,
      %common_modules,
   );

   return 0;
}

# ##########################################################################
# Subroutines
# ##########################################################################

# Sub: get_variables
#   Get SHOW VARIABLES from MySQL or a file.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   source - "mysql" or a file name
#
# Optional Arguments:
#   dbh                 - dbh if source=="mysql"
#   TextResultSetParser - <TextResultSetParser> object if source==file
#
# Returns:
#   Hashref of SHOW /*40003 GLOBAL*/ VARIABLES values.
sub get_variables {
   my ( %args ) = @_;
   my @required_args = qw(source);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($source) = @args{@required_args};

   my $vars;
   if ( ($source || '') =~ m/^mysql$/i ) {
      my $dbh = $args{dbh};
      die "I need a dbh argument" unless $dbh;
      MKDEBUG && _d("Getting variables from dbh", $dbh);
      my $sql = "SHOW /*40003 GLOBAL*/ VARIABLES";
      MKDEBUG && _d($dbh, $sql);
      map { $vars->{$_->{variable_name}} = $_->{value}; }
         @{ $dbh->selectall_arrayref($sql, {Slice=>{}}) };
   }
   else {
      my $trp = $args{TextResultSetParser};
      die "I need a TextResultSetParser arg" unless $trp;
      MKDEBUG && _d("Getting variables from", $source);
      open my $fh, "<", $source or die "Cannot open $source: $OS_ERROR";
      my $contents = do { local $/ = undef; <$fh> };
      close $fh;
      map { $vars->{$_->{Variable_name}} = $_->{Value} }
         @{ $trp->parse($contents) };
   }

   return $vars;
}

# Sub: print_advice
#   Print information about rules that matched.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   advice       - Arrayref of rule IDs, returned by <Advisor::run_rules()>
#   Advisor      - <Advisor> object
#   OptionParser - <OptionParser> object
sub print_advice {
   my ( %args ) = @_;
   my @required_args = qw(advice Advisor OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($advice, $adv, $o) = @args{@required_args};
   my $verbose = $o->get('verbose');

   return unless scalar @$advice;

   foreach my $id ( @$advice ) {
      my $info = $adv->get_rule_info($id);
      my @desc = map {
         $_ .= '.' unless m/\.$/;
         $_;
      } split(/\.\s{1,2}/, $info->{description} || '');
      $desc[1] ||= "";  # Some desc have only 1 sentence.
      my $desc = $verbose == 1 ? $desc[0]             # terse
               : $verbose == 2 ? "$desc[0] $desc[1]"  # fuller
               : $verbose >  2 ? $info->{description} # complete
               :                 '';                  # none
      print "# ", uc $info->{severity}, " $id: $desc\n\n";
   }

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

# ############################################################################
# Run the program.
# ############################################################################
if ( !caller ) { exit main(@ARGV); }

1; # Because this is a module as well as a script.

# ############################################################################
# Documentation
# ############################################################################

=pod

=head1 NAME

mk-variable-advisor - Analyze MySQL variables and advise on possible problems.

=head1 SYNOPSIS

Usage: mk-variable-advisor [OPTION...] [DSN]

mk-variable-advisor analyzes variables and advises on possible problems.

Get SHOW VARIABLES from localhost:

  mk-variable-advisor localhost

Get SHOW VARIABLES output saved in vars.txt:

  mk-variable-advisor --source-of-variables vars.txt

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-variable-advisor reads MySQL's configuration and examines it and is thus
very low risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-variable-advisor>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-variable-advisor examines C<SHOW VARIABLES> for bad values and settings
according to the L<"RULES"> described below.  It reports on variables that
match the rules, so you can find bad settings in your MySQL server.

At the time of this release, mk-variable-advisor only examples
C<SHOW VARIABLES>, but other input sources are planned like C<SHOW STATUS>
and C<SHOW SLAVE STATUS>.

=head1 RULES

These are the rules that mk-variable-advisor will apply to SHOW VARIABLES.
Each rule has three parts: an ID, a severity, and a description.

The rule's ID is a short, unique name for the rule.  It usually relates
to the variable that the rule examines.  If a variable is examined by
several rules, then the rules' IDs are numbered like "-1", "-2", "-N".

The rule's severity is an indication of how important it is that this
rule matched a query.  We use NOTE, WARN, and CRIT to denote these
levels.

The rule's description is a textual, human-readable explanation of
what it means when a variable matches this rule.  Depending on the
verbosity of the report you generate, you will see more of the text in
the description.  By default, you'll see only the first sentence,
which is sort of a terse synopsis of the rule's meaning.  At a higher
verbosity, you'll see subsequent sentences.

=over

=item auto_increment

severity: note

Are you trying to write to more than one server in a dual-master or
ring replication configuration?  This is potentially very dangerous and in
most cases is a serious mistake.  Most people's reasons for doing this are
actually not valid at all.

=item concurrent_insert

severity: note

Holes (spaces left by deletes) in MyISAM tables might never be
reused.

=item connect_timeout

severity: note 

A large value of this setting can create a denial of service
vulnerability.

=item debug

severity: crit

Servers built with debugging capability should not be used in
production because of the large performance impact.

=item delay_key_write

severity: warn

MyISAM index blocks are never flushed until necessary.  If there is
a server crash, data corruption on MyISAM tables can be much worse than
usual.

=item flush

severity: warn 

This option might decrease performance greatly.

=item flush_time

severity: warn 

This option might decrease performance greatly.

=item have_bdb

severity: note 

The BDB engine is deprecated.  If you aren't using it, you should
disable it with the skip_bdb option.

=item init_connect

severity: note

The init_connect option is enabled on this server.

=item init_file

severity: note 

The init_file option is enabled on this server.

=item init_slave

severity: note

The init_slave option is enabled on this server.

=item innodb_additional_mem_pool_size

severity: warn

This variable generally doesn't need to be larger than 20MB.

=item innodb_buffer_pool_size

severity: warn 

The InnoDB buffer pool size is unconfigured.  In a production
environment it should always be configured explicitly, and the default
10MB size is not good.

=item innodb_checksums

severity: warn 

InnoDB checksums are disabled.  Your data is not protected from
hardware corruption or other errors!

=item innodb_doublewrite

severity: warn 

InnoDB doublewrite is disabled.  Unless you use a filesystem that
protects against partial page writes, your data is not safe!

=item innodb_fast_shutdown

severity: warn

InnoDB's shutdown behavior is not the default.  This can lead to
poor performance, or the need to perform crash recovery upon startup.

=item innodb_flush_log_at_trx_commit-1

severity: warn 

InnoDB is not configured in strictly ACID mode.  If there
is a crash, some transactions can be lost.

=item innodb_flush_log_at_trx_commit-2

severity: warn

Setting innodb_flush_log_at_trx_commit to 0 has no performance
benefits over setting it to 2, and more types of data loss are possible.
If you are trying to change it from 1 for performance reasons, you should
set it to 2 instead of 0.

=item innodb_force_recovery

severity: warn 

InnoDB is in forced recovery mode!  This should be used only
temporarily when recovering from data corruption or other bugs, not for
normal usage.

=item innodb_lock_wait_timeout

severity: warn 

This option has an unusually long value, which can cause
system overload if locks are not being released.

=item innodb_log_buffer_size

severity: warn 

The InnoDB log buffer size generally should not be set larger than
16MB.  If you are doing large BLOB operations, InnoDB is not really a good
choice of engines anyway.

=item innodb_log_file_size

severity: warn 

The InnoDB log file size is set to its default value, which is not
usable on production systems.

=item innodb_max_dirty_pages_pct

severity: note 

The innodb_max_dirty_pages_pct is lower than the default.  This can
cause overly aggressive flushing and add load to the I/O system.

=item flush_time

severity: warn 

This setting is likely to cause very bad performance every
flush_time seconds.

=item key_buffer_size

severity: warn 

The key buffer size is unconfigured.  In a production
environment it should always be configured explicitly, and the default
8MB size is not good.

=item large_pages

severity: note 

Large pages are enabled.

=item locked_in_memory

severity: note 

The server is locked in memory with --memlock.

=item log_warnings-1

severity: note

Log_warnings is disabled, so unusual events such as statements
unsafe for replication and aborted connections will not be logged to the
error log.

=item log_warnings-2

severity: note

Log_warnings must be set greater than 1 to log unusual events such
as aborted connections.

=item low_priority_updates

severity: note 

The server is running with non-default lock priority for updates.
This could cause update queries to wait unexpectedly for read queries.

=item max_binlog_size

severity: note 

The max_binlog_size is smaller than the default of 1GB.

=item max_connect_errors

severity: note 

max_connect_errors should probably be set as large as your platform
allows.

=item max_connections

severity: warn 

If the server ever really has more than a thousand threads running,
then the system is likely to spend more time scheduling threads than
really doing useful work.  This variable's value should be considered in
light of your workload.

=item myisam_repair_threads

severity: note 

myisam_repair_threads > 1 enables multi-threaded repair, which is
relatively untested and is still listed as beta-quality code in the
official documentation.

=item old_passwords

severity: warn 

Old-style passwords are insecure.  They are sent in plain text
across the wire.

=item optimizer_prune_level

severity: warn 

The optimizer will use an exhaustive search when planning complex
queries, which can cause the planning process to take a long time.

=item port

severity: note 

The server is listening on a non-default port.

=item query_cache_size-1

severity: note 

The query cache does not scale to large sizes and can cause unstable
performance when larger than 128MB, especially on multi-core machines.

=item query_cache_size-2

severity: warn 

The query cache can cause severe performance problems when it is
larger than 256MB, especially on multi-core machines.

=item read_buffer_size-1

severity: note 

The read_buffer_size variable should generally be left at its
default unless an expert determines it is necessary to change it.

=item read_buffer_size-2

severity: warn 

The read_buffer_size variable should not be larger than 8MB.  It
should generally be left at its default unless an expert determines it is
necessary to change it.  Making it larger than 2MB can hurt performance
significantly, and can make the server crash, swap to death, or just
become extremely unstable.

=item read_rnd_buffer_size-1

severity: note 

The read_rnd_buffer_size variable should generally be left at its
default unless an expert determines it is necessary to change it.

=item read_rnd_buffer_size-2

severity: warn 

The read_rnd_buffer_size variable should not be larger than 4M.  It
should generally be left at its default unless an expert determines it is
necessary to change it.

=item relay_log_space_limit

severity: warn 

Setting relay_log_space_limit is relatively rare, and could cause
an increased risk of previously unknown bugs in replication.

=item slave_net_timeout

severity: warn 

This variable is set too high.  This is too long to wait before
noticing that the connection to the master has failed and retrying.  This
should probably be set to 60 seconds or less.  It is also a good idea to
use mk-heartbeat to ensure that the connection does not appear to time out
when the master is simply idle.

=item slave_skip_errors

severity: crit 

You should not set this option.  If replication is having errors,
you need to find and resolve the cause of that; it is likely that your
slave's data is different from the master.  You can find out with
mk-table-checksum.

=item sort_buffer_size-1

severity: note 

The sort_buffer_size variable should generally be left at its
default unless an expert determines it is necessary to change it.

=item sort_buffer_size-2

severity: note 

The sort_buffer_size variable should generally be left at its
default unless an expert determines it is necessary to change it.  Making
it larger than a few MB can hurt performance significantly, and can make
the server crash, swap to death, or just become extremely unstable.

=item sql_notes

severity: note 

This server is configured not to log Note level warnings to the
error log.

=item sync_frm

severity: warn 

It is best to set sync_frm so that .frm files are flushed safely to
disk in case of a server crash.

=item tx_isolation-1

severity: note 

This server's transaction isolation level is non-default.

=item tx_isolation-2

severity: warn 

Most applications should use the default REPEATABLE-READ transaction
isolation level, or in a few cases READ-COMMITTED.

=item expire_log_days

severity: warn

Binary logs are enabled, but automatic purging is not enabled.  If
you do not purge binary logs, your disk will fill up.  If you delete
binary logs externally to MySQL, you will cause unwanted behaviors.
Always ask MySQL to purge obsolete logs, never delete them externally.

=item innodb_file_io_threads

severity: note 

This option is useless except on Windows.

=item innodb_data_file_path

severity: note 

Auto-extending InnoDB files can consume a lot of disk space that is
very difficult to reclaim later.  Some people prefer to set
innodb_file_per_table and allocate a fixed-size file for ibdata1.

=item innodb_flush_method

severity: note 

Most production database servers that use InnoDB should set
innodb_flush_method to O_DIRECT to avoid double-buffering, unless the I/O
system is very low performance.

=item innodb_locks_unsafe_for_binlog

severity: warn 

This option makes point-in-time recovery from binary logs, and
replication, untrustworthy if statement-based logging is used.

=item innodb_support_xa

severity: warn 

MySQL's internal XA transaction support between InnoDB and the
binary log is disabled.  The binary log might not match InnoDB's state
after crash recovery, and replication might drift out of sync due to
out-of-order statements in the binary log.

=item log_bin

severity: warn 

Binary logging is disabled, so point-in-time recovery and
replication are not possible.

=item log_output

severity: warn 

Directing log output to tables has a high performance impact.

=item max_relay_log_size

severity: note 

A custom max_relay_log_size is defined.

=item myisam_recover_options

severity: warn 

myisam_recover_options should be set to some value such as
BACKUP,FORCE to ensure that table corruption is noticed.

=item storage_engine

severity: note 

The server is using a non-standard storage engine as default.

=item sync_binlog

severity: warn 

Binary logging is enabled, but sync_binlog isn't configured so that
every transaction is flushed to the binary log for durability.

=item tmp_table_size

severity: note 

The effective minimum size of in-memory implicit temporary tables
used internally during query execution is min(tmp_table_size,
max_heap_table_size), so max_heap_table_size should be at least as large
as tmp_table_size.

=item old mysql version

severity: warn

These are the recommended minimum version for each major release: 3.23, 4.1.20, 5.0.37, 5.1.30.  

=item end-of-life mysql version

severity: note

Every release older than 5.1 is now officially end-of-life.

=back

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
binmode on STDOUT without the utf8 layer, and runs SET NAMES after
connecting to MySQL.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --[no]continue-on-error

default: yes

Continue working even if there is an error.

=item --daemonize

Fork to the background and detach from the shell.  POSIX
operating systems only.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore-rules

type: hash

Ignore these rule IDs.

Specify a comma-separated list of rule IDs (e.g. LIT.001,RES.002,etc.)
to ignore.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file when daemonized.  The file contains the process
ID of the daemonized instance.  The PID file is removed when the
daemonized instance exits.  The program checks for the existence of the
PID file when starting; if it exists and the process with the matching PID
exists, the program exits.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this string
will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --source-of-variables

type: string; default: mysql

Read C<SHOW VARIABLES> from this source.  Possible values are "mysql", "none"
or a file name.  If "mysql" is specified then you must also specify a DSN
on the command line.

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes; default: 1

Increase verbosity of output.  At the default level of verbosity, the
program prints only the first sentence of each rule's description.  At
higher levels, the program prints more of the description.

=item --version

Show version and exit.

=back

=head1 DSN OPTIONS

These DSN options are used to create a DSN.  Each option is given like
C<option=value>.  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the C<=> and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the L<maatkit> manpage for full details.

=over

=item * A

dsn: charset; copy: yes

Default character set.

=item * D

dsn: database; copy: yes

Default database.

=item * F

dsn: mysql_read_default_file; copy: yes

Only read default options from the given file

=item * h

dsn: host; copy: yes

Connect to host.

=item * p

dsn: password; copy: yes

Password to use when connecting.

=item * P

dsn: port; copy: yes

Port number to use for connection.

=item * S

dsn: mysql_socket; copy: yes

Socket file to use for connection.

=item * u

dsn: user; copy: yes

User for login if not current user.

=back

=head1 DOWNLOADING

You can download Maatkit from Google Code at
L<http://code.google.com/p/maatkit/>, or you can get any of the tools
easily with a command like the following:

   wget http://www.maatkit.org/get/toolname
   or
   wget http://www.maatkit.org/trunk/toolname

Where C<toolname> can be replaced with the name (or fragment of a name) of any
of the Maatkit tools.  Once downloaded, they're ready to run; no installation is
needed.  The first URL gets the latest released version of the tool, and the
second gets the latest trunk code from Subversion.

=head1 ENVIRONMENT

The environment variable C<MKDEBUG> enables verbose debugging output in all of
the Maatkit tools:

   MKDEBUG=1 mk-....

=head1 SYSTEM REQUIREMENTS

You need the following Perl modules: DBI and DBD::mysql.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-variable-advisor>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2009-2011 Percona Inc.
Feedback and improvements are welcome.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue `man perlgpl' or `man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

=head1 AUTHOR

Baron Schwartz, Daniel Nichter

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.2 Distrib 7540 $Revision: 7477 $.

=cut

__END__
:endofperl
