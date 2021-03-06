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

# This program dumps MySQL tables in parallel.
#
# This program is copyright 2007-2011 Baron Schwartz.
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

our $VERSION = '1.0.28';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7460 $ =~ m/(\d+)/g, 0));

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
# TableParser package 7156
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableParser.pm
#   trunk/common/t/TableParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TableParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub parse {
   my ( $self, $ddl, $opts ) = @_;
   return unless $ddl;
   if ( ref $ddl eq 'ARRAY' ) {
      if ( lc $ddl->[0] eq 'table' ) {
         $ddl = $ddl->[1];
      }
      else {
         return {
            engine => 'VIEW',
         };
      }
   }

   if ( $ddl !~ m/CREATE (?:TEMPORARY )?TABLE `/ ) {
      die "Cannot parse table definition; is ANSI quoting "
         . "enabled or SQL_QUOTE_SHOW_CREATE disabled?";
   }

   my ($name)     = $ddl =~ m/CREATE (?:TEMPORARY )?TABLE\s+(`.+?`)/;
   (undef, $name) = $self->{Quoter}->split_unquote($name) if $name;

   $ddl =~ s/(`[^`]+`)/\L$1/g;

   my $engine = $self->get_engine($ddl);

   my @defs   = $ddl =~ m/^(\s+`.*?),?$/gm;
   my @cols   = map { $_ =~ m/`([^`]+)`/ } @defs;
   MKDEBUG && _d('Table cols:', join(', ', map { "`$_`" } @cols));

   my %def_for;
   @def_for{@cols} = @defs;

   my (@nums, @null);
   my (%type_for, %is_nullable, %is_numeric, %is_autoinc);
   foreach my $col ( @cols ) {
      my $def = $def_for{$col};
      my ( $type ) = $def =~ m/`[^`]+`\s([a-z]+)/;
      die "Can't determine column type for $def" unless $type;
      $type_for{$col} = $type;
      if ( $type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ) {
         push @nums, $col;
         $is_numeric{$col} = 1;
      }
      if ( $def !~ m/NOT NULL/ ) {
         push @null, $col;
         $is_nullable{$col} = 1;
      }
      $is_autoinc{$col} = $def =~ m/AUTO_INCREMENT/i ? 1 : 0;
   }

   my ($keys, $clustered_key) = $self->get_keys($ddl, $opts, \%is_nullable);

   my ($charset) = $ddl =~ m/DEFAULT CHARSET=(\w+)/;

   return {
      name           => $name,
      cols           => \@cols,
      col_posn       => { map { $cols[$_] => $_ } 0..$#cols },
      is_col         => { map { $_ => 1 } @cols },
      null_cols      => \@null,
      is_nullable    => \%is_nullable,
      is_autoinc     => \%is_autoinc,
      clustered_key  => $clustered_key,
      keys           => $keys,
      defs           => \%def_for,
      numeric_cols   => \@nums,
      is_numeric     => \%is_numeric,
      engine         => $engine,
      type_for       => \%type_for,
      charset        => $charset,
   };
}

sub sort_indexes {
   my ( $self, $tbl ) = @_;

   my @indexes
      = sort {
         (($a ne 'PRIMARY') <=> ($b ne 'PRIMARY'))
         || ( !$tbl->{keys}->{$a}->{is_unique} <=> !$tbl->{keys}->{$b}->{is_unique} )
         || ( $tbl->{keys}->{$a}->{is_nullable} <=> $tbl->{keys}->{$b}->{is_nullable} )
         || ( scalar(@{$tbl->{keys}->{$a}->{cols}}) <=> scalar(@{$tbl->{keys}->{$b}->{cols}}) )
      }
      grep {
         $tbl->{keys}->{$_}->{type} eq 'BTREE'
      }
      sort keys %{$tbl->{keys}};

   MKDEBUG && _d('Indexes sorted best-first:', join(', ', @indexes));
   return @indexes;
}

sub find_best_index {
   my ( $self, $tbl, $index ) = @_;
   my $best;
   if ( $index ) {
      ($best) = grep { uc $_ eq uc $index } keys %{$tbl->{keys}};
   }
   if ( !$best ) {
      if ( $index ) {
         die "Index '$index' does not exist in table";
      }
      else {
         ($best) = $self->sort_indexes($tbl);
      }
   }
   MKDEBUG && _d('Best index found is', $best);
   return $best;
}

sub find_possible_keys {
   my ( $self, $dbh, $database, $table, $quoter, $where ) = @_;
   return () unless $where;
   my $sql = 'EXPLAIN SELECT * FROM ' . $quoter->quote($database, $table)
      . ' WHERE ' . $where;
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);
   $expl = { map { lc($_) => $expl->{$_} } keys %$expl };
   if ( $expl->{possible_keys} ) {
      MKDEBUG && _d('possible_keys =', $expl->{possible_keys});
      my @candidates = split(',', $expl->{possible_keys});
      my %possible   = map { $_ => 1 } @candidates;
      if ( $expl->{key} ) {
         MKDEBUG && _d('MySQL chose', $expl->{key});
         unshift @candidates, grep { $possible{$_} } split(',', $expl->{key});
         MKDEBUG && _d('Before deduping:', join(', ', @candidates));
         my %seen;
         @candidates = grep { !$seen{$_}++ } @candidates;
      }
      MKDEBUG && _d('Final list:', join(', ', @candidates));
      return @candidates;
   }
   else {
      MKDEBUG && _d('No keys in possible_keys');
      return ();
   }
}

sub check_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl) = @args{@required_args};
   my $q      = $self->{Quoter};
   my $db_tbl = $q->quote($db, $tbl);
   MKDEBUG && _d('Checking', $db_tbl);

   my $sql = "SHOW TABLES FROM " . $q->quote($db)
           . ' LIKE ' . $q->literal_like($tbl);
   MKDEBUG && _d($sql);
   my $row;
   eval {
      $row = $dbh->selectrow_arrayref($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return 0;
   }
   if ( !$row->[0] || $row->[0] ne $tbl ) {
      MKDEBUG && _d('Table does not exist');
      return 0;
   }

   MKDEBUG && _d('Table exists; no privs to check');
   return 1 unless $args{all_privs};

   $sql = "SHOW FULL COLUMNS FROM $db_tbl";
   MKDEBUG && _d($sql);
   eval {
      $row = $dbh->selectrow_hashref($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return 0;
   }
   if ( !scalar keys %$row ) {
      MKDEBUG && _d('Table has no columns:', Dumper($row));
      return 0;
   }
   my $privs = $row->{privileges} || $row->{Privileges};

   $sql = "DELETE FROM $db_tbl LIMIT 0";
   MKDEBUG && _d($sql);
   eval {
      $dbh->do($sql);
   };
   my $can_delete = $EVAL_ERROR ? 0 : 1;

   MKDEBUG && _d('User privs on', $db_tbl, ':', $privs,
      ($can_delete ? 'delete' : ''));

   if ( !($privs =~ m/select/ && $privs =~ m/insert/ && $privs =~ m/update/
          && $can_delete) ) {
      MKDEBUG && _d('User does not have all privs');
      return 0;
   }

   MKDEBUG && _d('User has all privs');
   return 1;
}

sub get_engine {
   my ( $self, $ddl, $opts ) = @_;
   my ( $engine ) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;
   MKDEBUG && _d('Storage engine:', $engine);
   return $engine || undef;
}

sub get_keys {
   my ( $self, $ddl, $opts, $is_nullable ) = @_;
   my $engine        = $self->get_engine($ddl);
   my $keys          = {};
   my $clustered_key = undef;

   KEY:
   foreach my $key ( $ddl =~ m/^  ((?:[A-Z]+ )?KEY .*)$/gm ) {

      next KEY if $key =~ m/FOREIGN/;

      my $key_ddl = $key;
      MKDEBUG && _d('Parsed key:', $key_ddl);

      if ( $engine !~ m/MEMORY|HEAP/ ) {
         $key =~ s/USING HASH/USING BTREE/;
      }

      my ( $type, $cols ) = $key =~ m/(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $key =~ m/(FULLTEXT|SPATIAL)/;
      $type = $type || $special || 'BTREE';
      if ( $opts->{mysql_version} && $opts->{mysql_version} lt '004001000'
         && $engine =~ m/HEAP|MEMORY/i )
      {
         $type = 'HASH'; # MySQL pre-4.1 supports only HASH indexes on HEAP
      }

      my ($name) = $key =~ m/(PRIMARY|`[^`]*`)/;
      my $unique = $key =~ m/PRIMARY|UNIQUE/ ? 1 : 0;
      my @cols;
      my @col_prefixes;
      foreach my $col_def ( $cols =~ m/`[^`]+`(?:\(\d+\))?/g ) {
         my ($name, $prefix) = $col_def =~ m/`([^`]+)`(?:\((\d+)\))?/;
         push @cols, $name;
         push @col_prefixes, $prefix;
      }
      $name =~ s/`//g;

      MKDEBUG && _d( $name, 'key cols:', join(', ', map { "`$_`" } @cols));

      $keys->{$name} = {
         name         => $name,
         type         => $type,
         colnames     => $cols,
         cols         => \@cols,
         col_prefixes => \@col_prefixes,
         is_unique    => $unique,
         is_nullable  => scalar(grep { $is_nullable->{$_} } @cols),
         is_col       => { map { $_ => 1 } @cols },
         ddl          => $key_ddl,
      };

      if ( $engine =~ m/InnoDB/i && !$clustered_key ) {
         my $this_key = $keys->{$name};
         if ( $this_key->{name} eq 'PRIMARY' ) {
            $clustered_key = 'PRIMARY';
         }
         elsif ( $this_key->{is_unique} && !$this_key->{is_nullable} ) {
            $clustered_key = $this_key->{name};
         }
         MKDEBUG && $clustered_key && _d('This key is the clustered key');
      }
   }

   return $keys, $clustered_key;
}

sub get_fks {
   my ( $self, $ddl, $opts ) = @_;
   my $fks = {};

   foreach my $fk (
      $ddl =~ m/CONSTRAINT .* FOREIGN KEY .* REFERENCES [^\)]*\)/mg )
   {
      my ( $name ) = $fk =~ m/CONSTRAINT `(.*?)`/;
      my ( $cols ) = $fk =~ m/FOREIGN KEY \(([^\)]+)\)/;
      my ( $parent, $parent_cols ) = $fk =~ m/REFERENCES (\S+) \(([^\)]+)\)/;

      if ( $parent !~ m/\./ && $opts->{database} ) {
         $parent = "`$opts->{database}`.$parent";
      }

      $fks->{$name} = {
         name           => $name,
         colnames       => $cols,
         cols           => [ map { s/[ `]+//g; $_; } split(',', $cols) ],
         parent_tbl     => $parent,
         parent_colnames=> $parent_cols,
         parent_cols    => [ map { s/[ `]+//g; $_; } split(',', $parent_cols) ],
         ddl            => $fk,
      };
   }

   return $fks;
}

sub remove_auto_increment {
   my ( $self, $ddl ) = @_;
   $ddl =~ s/(^\).*?) AUTO_INCREMENT=\d+\b/$1/m;
   return $ddl;
}

sub remove_secondary_indexes {
   my ( $self, $ddl ) = @_;
   my $sec_indexes_ddl;
   my $tbl_struct = $self->parse($ddl);

   if ( ($tbl_struct->{engine} || '') =~ m/InnoDB/i ) {
      my $clustered_key = $tbl_struct->{clustered_key};
      $clustered_key  ||= '';

      my @sec_indexes   = map {
         my $key_def = $_->{ddl};
         $key_def =~ s/([\(\)])/\\$1/g;
         $ddl =~ s/\s+$key_def//i;

         my $key_ddl = "ADD $_->{ddl}";
         $key_ddl   .= ',' unless $key_ddl =~ m/,$/;
         $key_ddl;
      }
      grep { $_->{name} ne $clustered_key }
      values %{$tbl_struct->{keys}};
      MKDEBUG && _d('Secondary indexes:', Dumper(\@sec_indexes));

      if ( @sec_indexes ) {
         $sec_indexes_ddl = join(' ', @sec_indexes);
         $sec_indexes_ddl =~ s/,$//;
      }

      $ddl =~ s/,(\n\) )/$1/s;
   }
   else {
      MKDEBUG && _d('Not removing secondary indexes from',
         $tbl_struct->{engine}, 'table');
   }

   return $ddl, $sec_indexes_ddl, $tbl_struct;
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
# End TableParser package
# ###########################################################################

# ###########################################################################
# MySQLDump package 6345
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MySQLDump.pm
#   trunk/common/t/MySQLDump.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MySQLDump;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

( our $before = <<'EOF') =~ s/^   //gm;
   /*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
   /*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
   /*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
   /*!40101 SET NAMES utf8 */;
   /*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
   /*!40103 SET TIME_ZONE='+00:00' */;
   /*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
   /*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
   /*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
   /*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
EOF

( our $after = <<'EOF') =~ s/^   //gm;
   /*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
   /*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
   /*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
   /*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
   /*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
   /*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
   /*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
   /*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
EOF

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      cache => 0,  # Afaik no script uses this cache any longer because
   };
   return bless $self, $class;
}

sub dump {
   my ( $self, $dbh, $quoter, $db, $tbl, $what ) = @_;

   if ( $what eq 'table' ) {
      my $ddl = $self->get_create_table($dbh, $quoter, $db, $tbl);
      return unless $ddl;
      if ( $ddl->[0] eq 'table' ) {
         return $before
            . 'DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . ";\n"
            . $ddl->[1] . ";\n";
      }
      else {
         return 'DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . ";\n"
            . '/*!50001 DROP VIEW IF EXISTS '
            . $quoter->quote($tbl) . "*/;\n/*!50001 "
            . $self->get_tmp_table($dbh, $quoter, $db, $tbl) . "*/;\n";
      }
   }
   elsif ( $what eq 'triggers' ) {
      my $trgs = $self->get_triggers($dbh, $quoter, $db, $tbl);
      if ( $trgs && @$trgs ) {
         my $result = $before . "\nDELIMITER ;;\n";
         foreach my $trg ( @$trgs ) {
            if ( $trg->{sql_mode} ) {
               $result .= qq{/*!50003 SET SESSION SQL_MODE='$trg->{sql_mode}' */;;\n};
            }
            $result .= "/*!50003 CREATE */ ";
            if ( $trg->{definer} ) {
               my ( $user, $host )
                  = map { s/'/''/g; "'$_'"; }
                    split('@', $trg->{definer}, 2);
               $result .= "/*!50017 DEFINER=$user\@$host */ ";
            }
            $result .= sprintf("/*!50003 TRIGGER %s %s %s ON %s\nFOR EACH ROW %s */;;\n\n",
               $quoter->quote($trg->{trigger}),
               @{$trg}{qw(timing event)},
               $quoter->quote($trg->{table}),
               $trg->{statement});
         }
         $result .= "DELIMITER ;\n\n/*!50003 SET SESSION SQL_MODE=\@OLD_SQL_MODE */;\n\n";
         return $result;
      }
      else {
         return undef;
      }
   }
   elsif ( $what eq 'view' ) {
      my $ddl = $self->get_create_table($dbh, $quoter, $db, $tbl);
      return '/*!50001 DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . "*/;\n"
         . '/*!50001 DROP VIEW IF EXISTS ' . $quoter->quote($tbl) . "*/;\n"
         . '/*!50001 ' . $ddl->[1] . "*/;\n";
   }
   else {
      die "You didn't say what to dump.";
   }
}

sub _use_db {
   my ( $self, $dbh, $quoter, $new ) = @_;
   if ( !$new ) {
      MKDEBUG && _d('No new DB to use');
      return;
   }
   my $sql = 'USE ' . $quoter->quote($new);
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);
   return;
}

sub get_create_table {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   if ( !$self->{cache} || !$self->{tables}->{$db}->{$tbl} ) {
      my $sql = '/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, '
         . q{@@SQL_MODE := REPLACE(REPLACE(@@SQL_MODE, 'ANSI_QUOTES', ''), ',,', ','), }
         . '@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, '
         . '@@SQL_QUOTE_SHOW_CREATE := 1 */';
      MKDEBUG && _d($sql);
      eval { $dbh->do($sql); };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      $self->_use_db($dbh, $quoter, $db);
      $sql = "SHOW CREATE TABLE " . $quoter->quote($db, $tbl);
      MKDEBUG && _d($sql);
      my $href;
      eval { $href = $dbh->selectrow_hashref($sql); };
      if ( $EVAL_ERROR ) {
         warn "Failed to $sql.  The table may be damaged.\nError: $EVAL_ERROR";
         return;
      }

      $sql = '/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, '
         . '@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
      my ($key) = grep { m/create table/i } keys %$href;
      if ( $key ) {
         MKDEBUG && _d('This table is a base table');
         $self->{tables}->{$db}->{$tbl} = [ 'table', $href->{$key} ];
      }
      else {
         MKDEBUG && _d('This table is a view');
         ($key) = grep { m/create view/i } keys %$href;
         $self->{tables}->{$db}->{$tbl} = [ 'view', $href->{$key} ];
      }
   }
   return $self->{tables}->{$db}->{$tbl};
}

sub get_columns {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   MKDEBUG && _d('Get columns for', $db, $tbl);
   if ( !$self->{cache} || !$self->{columns}->{$db}->{$tbl} ) {
      $self->_use_db($dbh, $quoter, $db);
      my $sql = "SHOW COLUMNS FROM " . $quoter->quote($db, $tbl);
      MKDEBUG && _d($sql);
      my $cols = $dbh->selectall_arrayref($sql, { Slice => {} });

      $self->{columns}->{$db}->{$tbl} = [
         map {
            my %row;
            @row{ map { lc $_ } keys %$_ } = values %$_;
            \%row;
         } @$cols
      ];
   }
   return $self->{columns}->{$db}->{$tbl};
}

sub get_tmp_table {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   my $result = 'CREATE TABLE ' . $quoter->quote($tbl) . " (\n";
   $result .= join(",\n",
      map { '  ' . $quoter->quote($_->{field}) . ' ' . $_->{type} }
      @{$self->get_columns($dbh, $quoter, $db, $tbl)});
   $result .= "\n)";
   MKDEBUG && _d($result);
   return $result;
}

sub get_triggers {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   if ( !$self->{cache} || !$self->{triggers}->{$db} ) {
      $self->{triggers}->{$db} = {};
      my $sql = '/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, '
         . q{@@SQL_MODE := REPLACE(REPLACE(@@SQL_MODE, 'ANSI_QUOTES', ''), ',,', ','), }
         . '@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, '
         . '@@SQL_QUOTE_SHOW_CREATE := 1 */';
      MKDEBUG && _d($sql);
      eval { $dbh->do($sql); };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      $sql = "SHOW TRIGGERS FROM " . $quoter->quote($db);
      MKDEBUG && _d($sql);
      my $sth = $dbh->prepare($sql);
      $sth->execute();
      if ( $sth->rows ) {
         my $trgs = $sth->fetchall_arrayref({});
         foreach my $trg (@$trgs) {
            my %trg;
            @trg{ map { lc $_ } keys %$trg } = values %$trg;
            push @{ $self->{triggers}->{$db}->{ $trg{table} } }, \%trg;
         }
      }
      $sql = '/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, '
         . '@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }
   if ( $tbl ) {
      return $self->{triggers}->{$db}->{$tbl};
   }
   return values %{$self->{triggers}->{$db}};
}

sub get_databases {
   my ( $self, $dbh, $quoter, $like ) = @_;
   if ( !$self->{cache} || !$self->{databases} || $like ) {
      my $sql = 'SHOW DATABASES';
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      my $sth = $dbh->prepare($sql);
      MKDEBUG && _d($sql, @params);
      $sth->execute( @params );
      my @dbs = map { $_->[0] } @{$sth->fetchall_arrayref()};
      $self->{databases} = \@dbs unless $like;
      return @dbs;
   }
   return @{$self->{databases}};
}

sub get_table_status {
   my ( $self, $dbh, $quoter, $db, $like ) = @_;
   if ( !$self->{cache} || !$self->{table_status}->{$db} || $like ) {
      my $sql = "SHOW TABLE STATUS FROM " . $quoter->quote($db);
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      MKDEBUG && _d($sql, @params);
      my $sth = $dbh->prepare($sql);
      $sth->execute(@params);
      my @tables = @{$sth->fetchall_arrayref({})};
      @tables = map {
         my %tbl; # Make a copy with lowercased keys
         @tbl{ map { lc $_ } keys %$_ } = values %$_;
         $tbl{engine} ||= $tbl{type} || $tbl{comment};
         delete $tbl{type};
         \%tbl;
      } @tables;
      $self->{table_status}->{$db} = \@tables unless $like;
      return @tables;
   }
   return @{$self->{table_status}->{$db}};
}

sub get_table_list {
   my ( $self, $dbh, $quoter, $db, $like ) = @_;
   if ( !$self->{cache} || !$self->{table_list}->{$db} || $like ) {
      my $sql = "SHOW /*!50002 FULL*/ TABLES FROM " . $quoter->quote($db);
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      MKDEBUG && _d($sql, @params);
      my $sth = $dbh->prepare($sql);
      $sth->execute(@params);
      my @tables = @{$sth->fetchall_arrayref()};
      @tables = map {
         my %tbl = (
            name   => $_->[0],
            engine => ($_->[1] || '') eq 'VIEW' ? 'VIEW' : '',
         );
         \%tbl;
      } @tables;
      $self->{table_list}->{$db} = \@tables unless $like;
      return @tables;
   }
   return @{$self->{table_list}->{$db}};
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
# End MySQLDump package
# ###########################################################################

# ###########################################################################
# TableChunker package 7169
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableChunker.pm
#   trunk/common/t/TableChunker.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TableChunker;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use POSIX qw(floor ceil);
use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter MySQLDump) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my %int_types  = map { $_ => 1 } qw(bigint date datetime int mediumint smallint time timestamp tinyint year);
   my %real_types = map { $_ => 1 } qw(decimal double float);

   my $self = {
      %args,
      int_types  => \%int_types,
      real_types => \%real_types,
      EPOCH      => '1970-01-01',
   };

   return bless $self, $class;
}

sub find_chunk_columns {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $tbl_struct = $args{tbl_struct};

   my @possible_indexes;
   foreach my $index ( values %{ $tbl_struct->{keys} } ) {

      next unless $index->{type} eq 'BTREE';

      next if grep { defined } @{$index->{col_prefixes}};

      if ( $args{exact} ) {
         next unless $index->{is_unique} && @{$index->{cols}} == 1;
      }

      push @possible_indexes, $index;
   }
   MKDEBUG && _d('Possible chunk indexes in order:',
      join(', ', map { $_->{name} } @possible_indexes));

   my $can_chunk_exact = 0;
   my @candidate_cols;
   foreach my $index ( @possible_indexes ) { 
      my $col = $index->{cols}->[0];

      my $col_type = $tbl_struct->{type_for}->{$col};
      next unless $self->{int_types}->{$col_type}
               || $self->{real_types}->{$col_type}
               || $col_type =~ m/char/;

      push @candidate_cols, { column => $col, index => $index->{name} };
   }

   $can_chunk_exact = 1 if $args{exact} && scalar @candidate_cols;

   if ( MKDEBUG ) {
      my $chunk_type = $args{exact} ? 'Exact' : 'Inexact';
      _d($chunk_type, 'chunkable:',
         join(', ', map { "$_->{column} on $_->{index}" } @candidate_cols));
   }

   my @result;
   MKDEBUG && _d('Ordering columns by order in tbl, PK first');
   if ( $tbl_struct->{keys}->{PRIMARY} ) {
      my $pk_first_col = $tbl_struct->{keys}->{PRIMARY}->{cols}->[0];
      @result          = grep { $_->{column} eq $pk_first_col } @candidate_cols;
      @candidate_cols  = grep { $_->{column} ne $pk_first_col } @candidate_cols;
   }
   my $i = 0;
   my %col_pos = map { $_ => $i++ } @{$tbl_struct->{cols}};
   push @result, sort { $col_pos{$a->{column}} <=> $col_pos{$b->{column}} }
                    @candidate_cols;

   if ( MKDEBUG ) {
      _d('Chunkable columns:',
         join(', ', map { "$_->{column} on $_->{index}" } @result));
      _d('Can chunk exactly:', $can_chunk_exact);
   }

   return ($can_chunk_exact, @result);
}

sub calculate_chunks {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   MKDEBUG && _d('Calculate chunks for',
      join(", ", map {"$_=".(defined $args{$_} ? $args{$_} : "undef")}
         qw(db tbl chunk_col min max rows_in_range chunk_size zero_chunk exact)
      ));

   if ( !$args{rows_in_range} ) {
      MKDEBUG && _d("Empty table");
      return '1=1';
   }

   if ( $args{rows_in_range} < $args{chunk_size} ) {
      MKDEBUG && _d("Chunk size larger than rows in range");
      return '1=1';
   }

   my $q          = $self->{Quoter};
   my $dbh        = $args{dbh};
   my $chunk_col  = $args{chunk_col};
   my $tbl_struct = $args{tbl_struct};
   my $col_type   = $tbl_struct->{type_for}->{$chunk_col};
   MKDEBUG && _d('chunk col type:', $col_type);

   my %chunker;
   if ( $tbl_struct->{is_numeric}->{$chunk_col} || $col_type =~ /date|time/ ) {
      %chunker = $self->_chunk_numeric(%args);
   }
   elsif ( $col_type =~ m/char/ ) {
      %chunker = $self->_chunk_char(%args);
   }
   else {
      die "Cannot chunk $col_type columns";
   }
   MKDEBUG && _d("Chunker:", Dumper(\%chunker));
   my ($col, $start_point, $end_point, $interval, $range_func)
      = @chunker{qw(col start_point end_point interval range_func)};

   my @chunks;
   if ( $start_point < $end_point ) {

      push @chunks, "$col = 0" if $chunker{have_zero_chunk};

      my ($beg, $end);
      my $iter = 0;
      for ( my $i = $start_point; $i < $end_point; $i += $interval ) {
         ($beg, $end) = $self->$range_func($dbh, $i, $interval, $end_point);

         if ( $iter++ == 0 ) {
            push @chunks,
               ($chunker{have_zero_chunk} ? "$col > 0 AND " : "")
               ."$col < " . $q->quote_val($end);
         }
         else {
            push @chunks, "$col >= " . $q->quote_val($beg) . " AND $col < " . $q->quote_val($end);
         }
      }

      my $chunk_range = lc $args{chunk_range} || 'open';
      my $nullable    = $args{tbl_struct}->{is_nullable}->{$args{chunk_col}};
      pop @chunks;
      if ( @chunks ) {
         push @chunks, "$col >= " . $q->quote_val($beg)
            . ($chunk_range eq 'openclosed'
               ? " AND $col <= " . $q->quote_val($args{max}) : "");
      }
      else {
         push @chunks, $nullable ? "$col IS NOT NULL" : '1=1';
      }
      if ( $nullable ) {
         push @chunks, "$col IS NULL";
      }
   }
   else {
      MKDEBUG && _d('No chunks; using single chunk 1=1');
      push @chunks, '1=1';
   }

   return @chunks;
}

sub _chunk_numeric {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q        = $self->{Quoter};
   my $db_tbl   = $q->quote($args{db}, $args{tbl});
   my $col_type = $args{tbl_struct}->{type_for}->{$args{chunk_col}};

   my $range_func;
   if ( $col_type =~ m/(?:int|year|float|double|decimal)$/ ) {
      $range_func  = 'range_num';
   }
   elsif ( $col_type =~ m/^(?:timestamp|date|time)$/ ) {
      $range_func  = "range_$col_type";
   }
   elsif ( $col_type eq 'datetime' ) {
      $range_func  = 'range_datetime';
   }

   my ($start_point, $end_point);
   eval {
      $start_point = $self->value_to_number(
         value       => $args{min},
         column_type => $col_type,
         dbh         => $args{dbh},
      );
      $end_point  = $self->value_to_number(
         value       => $args{max},
         column_type => $col_type,
         dbh         => $args{dbh},
      );
   };
   if ( $EVAL_ERROR ) {
      if ( $EVAL_ERROR =~ m/don't know how to chunk/ ) {
         die $EVAL_ERROR;
      }
      else {
         die "Error calculating chunk start and end points for table "
            . "`$args{tbl_struct}->{name}` on column `$args{chunk_col}` "
            . "with min/max values "
            . join('/',
                  map { defined $args{$_} ? $args{$_} : 'undef' } qw(min max))
            . ":\n\n"
            . $EVAL_ERROR
            . "\nVerify that the min and max values are valid for the column.  "
            . "If they are valid, this error could be caused by a bug in the "
            . "tool.";
      }
   }

   if ( !defined $start_point ) {
      MKDEBUG && _d('Start point is undefined');
      $start_point = 0;
   }
   if ( !defined $end_point || $end_point < $start_point ) {
      MKDEBUG && _d('End point is undefined or before start point');
      $end_point = 0;
   }
   MKDEBUG && _d("Actual chunk range:", $start_point, "to", $end_point);

   my $have_zero_chunk = 0;
   if ( $args{zero_chunk} ) {
      if ( $start_point != $end_point && $start_point >= 0 ) {
         MKDEBUG && _d('Zero chunking');
         my $nonzero_val = $self->get_nonzero_value(
            %args,
            db_tbl   => $db_tbl,
            col      => $args{chunk_col},
            col_type => $col_type,
            val      => $args{min}
         );
         $start_point = $self->value_to_number(
            value       => $nonzero_val,
            column_type => $col_type,
            dbh         => $args{dbh},
         );
         $have_zero_chunk = 1;
      }
      else {
         MKDEBUG && _d("Cannot zero chunk");
      }
   }
   MKDEBUG && _d("Using chunk range:", $start_point, "to", $end_point);

   my $interval = $args{chunk_size}
                * ($end_point - $start_point)
                / $args{rows_in_range};
   if ( $self->{int_types}->{$col_type} ) {
      $interval = ceil($interval);
   }
   $interval ||= $args{chunk_size};
   if ( $args{exact} ) {
      $interval = $args{chunk_size};
   }
   MKDEBUG && _d('Chunk interval:', $interval, 'units');

   return (
      col             => $q->quote($args{chunk_col}),
      start_point     => $start_point,
      end_point       => $end_point,
      interval        => $interval,
      range_func      => $range_func,
      have_zero_chunk => $have_zero_chunk,
   );
}

sub _chunk_char {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q         = $self->{Quoter};
   my $db_tbl    = $q->quote($args{db}, $args{tbl});
   my $dbh       = $args{dbh};
   my $chunk_col = $args{chunk_col};
   my $row;
   my $sql;

   $sql = "SELECT MIN($chunk_col), MAX($chunk_col) FROM $db_tbl "
        . "ORDER BY `$chunk_col`";
   MKDEBUG && _d($dbh, $sql);
   $row = $dbh->selectrow_arrayref($sql);
   my ($min_col, $max_col) = ($row->[0], $row->[1]);

   $sql = "SELECT ORD(?) AS min_col_ord, ORD(?) AS max_col_ord";
   MKDEBUG && _d($dbh, $sql);
   my $ord_sth = $dbh->prepare($sql);  # avoid quoting issues
   $ord_sth->execute($min_col, $max_col);
   $row = $ord_sth->fetchrow_arrayref();
   my ($min_col_ord, $max_col_ord) = ($row->[0], $row->[1]);
   MKDEBUG && _d("Min/max col char code:", $min_col_ord, $max_col_ord);

   my $base;
   my @chars;
   MKDEBUG && _d("Table charset:", $args{tbl_struct}->{charset});
   if ( ($args{tbl_struct}->{charset} || "") eq "latin1" ) {
      my @sorted_latin1_chars = (
          32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,
          46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,
          60,  61,  62,  63,  64,  65,  66,  67,  68,  69,  70,  71,  72,  73,
          74,  75,  76,  77,  78,  79,  80,  81,  82,  83,  84,  85,  86,  87,
          88,  89,  90,  91,  92,  93,  94,  95,  96, 123, 124, 125, 126, 161,
         162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
         176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189,
         190, 191, 215, 216, 222, 223, 247, 255);

      my ($first_char, $last_char);
      for my $i ( 0..$#sorted_latin1_chars ) {
         $first_char = $i and last if $sorted_latin1_chars[$i] >= $min_col_ord;
      }
      for my $i ( $first_char..$#sorted_latin1_chars ) {
         $last_char = $i and last if $sorted_latin1_chars[$i] >= $max_col_ord;
      };

      @chars = map { chr $_; } @sorted_latin1_chars[$first_char..$last_char];
      $base  = scalar @chars;
   }
   else {

      my $tmp_tbl    = '__maatkit_char_chunking_map';
      my $tmp_db_tbl = $q->quote($args{db}, $tmp_tbl);
      $sql = "DROP TABLE IF EXISTS $tmp_db_tbl";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
      my $col_def = $args{tbl_struct}->{defs}->{$chunk_col};
      $sql        = "CREATE TEMPORARY TABLE $tmp_db_tbl ($col_def) "
                  . "ENGINE=MEMORY";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);

      $sql = "INSERT INTO $tmp_db_tbl VALUE (CHAR(?))";
      MKDEBUG && _d($dbh, $sql);
      my $ins_char_sth = $dbh->prepare($sql);  # avoid quoting issues
      for my $char_code ( $min_col_ord..$max_col_ord ) {
         $ins_char_sth->execute($char_code);
      }

      $sql = "SELECT `$chunk_col` FROM $tmp_db_tbl "
           . "WHERE `$chunk_col` BETWEEN ? AND ? "
           . "ORDER BY `$chunk_col`";
      MKDEBUG && _d($dbh, $sql);
      my $sel_char_sth = $dbh->prepare($sql);
      $sel_char_sth->execute($min_col, $max_col);

      @chars = map { $_->[0] } @{ $sel_char_sth->fetchall_arrayref() };
      $base  = scalar @chars;

      $sql = "DROP TABLE $tmp_db_tbl";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   MKDEBUG && _d("Base", $base, "chars:", @chars);


   $sql = "SELECT MAX(LENGTH($chunk_col)) FROM $db_tbl ORDER BY `$chunk_col`";
   MKDEBUG && _d($dbh, $sql);
   $row = $dbh->selectrow_arrayref($sql);
   my $max_col_len = $row->[0];
   MKDEBUG && _d("Max column value:", $max_col, $max_col_len);
   my $n_values;
   for my $n_chars ( 1..$max_col_len ) {
      $n_values = $base**$n_chars;
      if ( $n_values >= $args{chunk_size} ) {
         MKDEBUG && _d($n_chars, "chars in base", $base, "expresses",
            $n_values, "values");
         last;
      }
   }

   my $n_chunks = $args{rows_in_range} / $args{chunk_size};
   my $interval = floor($n_values / $n_chunks) || 1;

   my $range_func = sub {
      my ( $self, $dbh, $start, $interval, $max ) = @_;
      my $start_char = $self->base_count(
         count_to => $start,
         base     => $base,
         symbols  => \@chars,
      );
      my $end_char = $self->base_count(
         count_to => min($max, $start + $interval),
         base     => $base,
         symbols  => \@chars,
      );
      return $start_char, $end_char;
   };

   return (
      col         => $q->quote($chunk_col),
      start_point => 0,
      end_point   => $n_values,
      interval    => $interval,
      range_func  => $range_func,
   );
}

sub get_first_chunkable_column {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($exact, @cols) = $self->find_chunk_columns(%args);
   my $col = $cols[0]->{column};
   my $idx = $cols[0]->{index};

   my $wanted_col = $args{chunk_column};
   my $wanted_idx = $args{chunk_index};
   MKDEBUG && _d("Preferred chunk col/idx:", $wanted_col, $wanted_idx);

   if ( $wanted_col && $wanted_idx ) {
      foreach my $chunkable_col ( @cols ) {
         if (    $wanted_col eq $chunkable_col->{column}
              && $wanted_idx eq $chunkable_col->{index} ) {
            $col = $wanted_col;
            $idx = $wanted_idx;
            last;
         }
      }
   }
   elsif ( $wanted_col ) {
      foreach my $chunkable_col ( @cols ) {
         if ( $wanted_col eq $chunkable_col->{column} ) {
            $col = $wanted_col;
            $idx = $chunkable_col->{index};
            last;
         }
      }
   }
   elsif ( $wanted_idx ) {
      foreach my $chunkable_col ( @cols ) {
         if ( $wanted_idx eq $chunkable_col->{index} ) {
            $col = $chunkable_col->{column};
            $idx = $wanted_idx;
            last;
         }
      }
   }

   MKDEBUG && _d('First chunkable col/index:', $col, $idx);
   return $col, $idx;
}

sub size_to_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $chunk_size) = @args{@required_args};
   my $q  = $self->{Quoter};
   my $du = $self->{MySQLDump};

   my ($n_rows, $avg_row_length);

   my ( $num, $suffix ) = $chunk_size =~ m/^(\d+)([MGk])?$/;
   if ( $suffix ) { # Convert to bytes.
      $chunk_size = $suffix eq 'k' ? $num * 1_024
                  : $suffix eq 'M' ? $num * 1_024 * 1_024
                  :                  $num * 1_024 * 1_024 * 1_024;
   }
   elsif ( $num ) {
      $n_rows = $num;
   }
   else {
      die "Invalid chunk size $chunk_size; must be an integer "
         . "with optional suffix kMG";
   }

   if ( $suffix || $args{avg_row_length} ) {
      my ($status) = $du->get_table_status($dbh, $q, $db, $tbl);
      $avg_row_length = $status->{avg_row_length};
      if ( !defined $n_rows ) {
         $n_rows = $avg_row_length ? ceil($chunk_size / $avg_row_length) : undef;
      }
   }

   return $n_rows, $avg_row_length;
}

sub get_range_statistics {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_col tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $col) = @args{@required_args};
   my $where = $args{where};
   my $q     = $self->{Quoter};

   my $col_type       = $args{tbl_struct}->{type_for}->{$col};
   my $col_is_numeric = $args{tbl_struct}->{is_numeric}->{$col};

   my $db_tbl = $q->quote($db, $tbl);
   $col       = $q->quote($col);

   my ($min, $max);
   eval {
      my $sql = "SELECT MIN($col), MAX($col) FROM $db_tbl"
              . ($args{index_hint} ? " $args{index_hint}" : "")
              . ($where ? " WHERE ($where)" : '');
      MKDEBUG && _d($dbh, $sql);
      ($min, $max) = $dbh->selectrow_array($sql);
      MKDEBUG && _d("Actual end points:", $min, $max);

      ($min, $max) = $self->get_valid_end_points(
         %args,
         dbh      => $dbh,
         db_tbl   => $db_tbl,
         col      => $col,
         col_type => $col_type,
         min      => $min,
         max      => $max,
      );
      MKDEBUG && _d("Valid end points:", $min, $max);
   };
   if ( $EVAL_ERROR ) {
      die "Error getting min and max values for table $db_tbl "
         . "on column $col: $EVAL_ERROR";
   }

   my $sql = "EXPLAIN SELECT * FROM $db_tbl"
           . ($args{index_hint} ? " $args{index_hint}" : "")
           . ($where ? " WHERE $where" : '');
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);

   return (
      min           => $min,
      max           => $max,
      rows_in_range => $expl->{rows},
   );
}

sub inject_chunks {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(database table chunks chunk_num query) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   MKDEBUG && _d('Injecting chunk', $args{chunk_num});
   my $query   = $args{query};
   my $comment = sprintf("/*%s.%s:%d/%d*/",
      $args{database}, $args{table},
      $args{chunk_num} + 1, scalar @{$args{chunks}});
   $query =~ s!/\*PROGRESS_COMMENT\*/!$comment!;
   my $where = "WHERE (" . $args{chunks}->[$args{chunk_num}] . ')';
   if ( $args{where} && grep { $_ } @{$args{where}} ) {
      $where .= " AND ("
         . join(" AND ", map { "($_)" } grep { $_ } @{$args{where}} )
         . ")";
   }
   my $db_tbl     = $self->{Quoter}->quote(@args{qw(database table)});
   my $index_hint = $args{index_hint} || '';

   MKDEBUG && _d('Parameters:',
      Dumper({WHERE => $where, DB_TBL => $db_tbl, INDEX_HINT => $index_hint}));
   $query =~ s!/\*WHERE\*/! $where!;
   $query =~ s!/\*DB_TBL\*/!$db_tbl!;
   $query =~ s!/\*INDEX_HINT\*/! $index_hint!;
   $query =~ s!/\*CHUNK_NUM\*/! $args{chunk_num} AS chunk_num,!;

   return $query;
}


sub value_to_number {
   my ( $self, %args ) = @_;
   my @required_args = qw(column_type dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $val = $args{value};
   my ($col_type, $dbh) = @args{@required_args};
   MKDEBUG && _d('Converting MySQL', $col_type, $val);

   return unless defined $val;  # value is NULL

   my %mysql_conv_func_for = (
      timestamp => 'UNIX_TIMESTAMP',
      date      => 'TO_DAYS',
      time      => 'TIME_TO_SEC',
      datetime  => 'TO_DAYS',
   );

   my $num;
   if ( $col_type =~ m/(?:int|year|float|double|decimal)$/ ) {
      $num = $val;
   }
   elsif ( $col_type =~ m/^(?:timestamp|date|time)$/ ) {
      my $func = $mysql_conv_func_for{$col_type};
      my $sql = "SELECT $func(?)";
      MKDEBUG && _d($dbh, $sql, $val);
      my $sth = $dbh->prepare($sql);
      $sth->execute($val);
      ($num) = $sth->fetchrow_array();
   }
   elsif ( $col_type eq 'datetime' ) {
      $num = $self->timestampdiff($dbh, $val);
   }
   else {
      die "I don't know how to chunk $col_type\n";
   }
   MKDEBUG && _d('Converts to', $num);
   return $num;
}

sub range_num {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $end = min($max, $start + $interval);


   $start = sprintf('%.17f', $start) if $start =~ /e/;
   $end   = sprintf('%.17f', $end)   if $end   =~ /e/;

   $start =~ s/\.(\d{5}).*$/.$1/;
   $end   =~ s/\.(\d{5}).*$/.$1/;

   if ( $end > $start ) {
      return ( $start, $end );
   }
   else {
      die "Chunk size is too small: $end !> $start\n";
   }
}

sub range_time {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT SEC_TO_TIME($start), SEC_TO_TIME(LEAST($max, $start + $interval))";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_date {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT FROM_DAYS($start), FROM_DAYS(LEAST($max, $start + $interval))";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_datetime {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT DATE_ADD('$self->{EPOCH}', INTERVAL $start SECOND), "
       . "DATE_ADD('$self->{EPOCH}', INTERVAL LEAST($max, $start + $interval) SECOND)";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_timestamp {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT FROM_UNIXTIME($start), FROM_UNIXTIME(LEAST($max, $start + $interval))";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub timestampdiff {
   my ( $self, $dbh, $time ) = @_;
   my $sql = "SELECT (COALESCE(TO_DAYS('$time'), 0) * 86400 + TIME_TO_SEC('$time')) "
      . "- TO_DAYS('$self->{EPOCH} 00:00:00') * 86400";
   MKDEBUG && _d($sql);
   my ( $diff ) = $dbh->selectrow_array($sql);
   $sql = "SELECT DATE_ADD('$self->{EPOCH}', INTERVAL $diff SECOND)";
   MKDEBUG && _d($sql);
   my ( $check ) = $dbh->selectrow_array($sql);
   die <<"   EOF"
   Incorrect datetime math: given $time, calculated $diff but checked to $check.
   This could be due to a version of MySQL that overflows on large interval
   values to DATE_ADD(), or the given datetime is not a valid date.  If not,
   please report this as a bug.
   EOF
      unless $check eq $time;
   return $diff;
}




sub get_valid_end_points {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my ($real_min, $real_max)           = @args{qw(min max)};

   my $err_fmt = "Error finding a valid %s value for table $db_tbl on "
               . "column $col. The real %s value %s is invalid and "
               . "no other valid values were found.  Verify that the table "
               . "has at least one valid value for this column"
               . ($args{where} ? " where $args{where}." : ".");

   my $valid_min = $real_min;
   if ( defined $valid_min ) {
      MKDEBUG && _d("Validating min end point:", $real_min);
      $valid_min = $self->_get_valid_end_point(
         %args,
         val      => $real_min,
         endpoint => 'min',
      );
      die sprintf($err_fmt, 'minimum', 'minimum',
         (defined $real_min ? $real_min : "NULL"))
         unless defined $valid_min;
   }

   my $valid_max = $real_max;
   if ( defined $valid_max ) {
      MKDEBUG && _d("Validating max end point:", $real_min);
      $valid_max = $self->_get_valid_end_point(
         %args,
         val      => $real_max,
         endpoint => 'max',
      );
      die sprintf($err_fmt, 'maximum', 'maximum',
         (defined $real_max ? $real_max : "NULL"))
         unless defined $valid_max;
   }

   return $valid_min, $valid_max;
}

sub _get_valid_end_point {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my $val = $args{val};

   return $val unless defined $val;

   my $validate = $col_type =~ m/time|date/ ? \&_validate_temporal_value
                :                             undef;

   if ( !$validate ) {
      MKDEBUG && _d("No validator for", $col_type, "values");
      return $val;
   }

   return $val if defined $validate->($dbh, $val);

   MKDEBUG && _d("Value is invalid, getting first valid value");
   $val = $self->get_first_valid_value(
      %args,
      val      => $val,
      validate => $validate,
   );

   return $val;
}

sub get_first_valid_value {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col validate endpoint);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $validate, $endpoint) = @args{@required_args};
   my $tries = defined $args{tries} ? $args{tries} : 5;
   my $val   = $args{val};

   return unless defined $val;

   my $cmp = $endpoint =~ m/min/i ? '>'
           : $endpoint =~ m/max/i ? '<'
           :                        die "Invalid endpoint arg: $endpoint";
   my $sql = "SELECT $col FROM $db_tbl "
           . ($args{index_hint} ? "$args{index_hint} " : "")
           . "WHERE $col $cmp ? AND $col IS NOT NULL "
           . ($args{where} ? "AND ($args{where}) " : "")
           . "ORDER BY $col LIMIT 1";
   MKDEBUG && _d($dbh, $sql);
   my $sth = $dbh->prepare($sql);

   my $last_val = $val;
   while ( $tries-- ) {
      $sth->execute($last_val);
      my ($next_val) = $sth->fetchrow_array();
      MKDEBUG && _d('Next value:', $next_val, '; tries left:', $tries);
      if ( !defined $next_val ) {
         MKDEBUG && _d('No more rows in table');
         last;
      }
      if ( defined $validate->($dbh, $next_val) ) {
         MKDEBUG && _d('First valid value:', $next_val);
         $sth->finish();
         return $next_val;
      }
      $last_val = $next_val;
   }
   $sth->finish();
   $val = undef;  # no valid value found

   return $val;
}

sub _validate_temporal_value {
   my ( $dbh, $val ) = @_;
   my $sql = "SELECT IF(TIME_FORMAT(?,'%H:%i:%s')=?, TIME_TO_SEC(?), TO_DAYS(?))";
   my $res;
   eval {
      MKDEBUG && _d($dbh, $sql, $val);
      my $sth = $dbh->prepare($sql);
      $sth->execute($val, $val, $val, $val);
      ($res) = $sth->fetchrow_array();
      $sth->finish();
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
   }
   return $res;
}

sub get_nonzero_value {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my $tries = defined $args{tries} ? $args{tries} : 5;
   my $val   = $args{val};

   my $is_nonzero = $col_type =~ m/time|date/ ? \&_validate_temporal_value
                  :                             sub { return $_[1]; };

   if ( !$is_nonzero->($dbh, $val) ) {  # quasi-double-negative, sorry
      MKDEBUG && _d('Discarding zero value:', $val);
      my $sql = "SELECT $col FROM $db_tbl "
              . ($args{index_hint} ? "$args{index_hint} " : "")
              . "WHERE $col > ? AND $col IS NOT NULL "
              . ($args{where} ? "AND ($args{where}) " : '')
              . "ORDER BY $col LIMIT 1";
      MKDEBUG && _d($sql);
      my $sth = $dbh->prepare($sql);

      my $last_val = $val;
      while ( $tries-- ) {
         $sth->execute($last_val);
         my ($next_val) = $sth->fetchrow_array();
         if ( $is_nonzero->($dbh, $next_val) ) {
            MKDEBUG && _d('First non-zero value:', $next_val);
            $sth->finish();
            return $next_val;
         }
         $last_val = $next_val;
      }
      $sth->finish();
      $val = undef;  # no non-zero value found
   }

   return $val;
}

sub base_count {
   my ( $self, %args ) = @_;
   my @required_args = qw(count_to base symbols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($n, $base, $symbols) = @args{@required_args};

   return $symbols->[0] if $n == 0;

   my $highest_power = floor(log($n)/log($base));
   if ( $highest_power == 0 ){
      return $symbols->[$n];
   }

   my @base_powers;
   for my $power ( 0..$highest_power ) {
      push @base_powers, ($base**$power) || 1;  
   }

   my @base_multiples;
   foreach my $base_power ( reverse @base_powers ) {
      my $multiples = floor($n / $base_power);
      push @base_multiples, $multiples;
      $n -= $multiples * $base_power;
   }

   return join('', map { $symbols->[$_] } @base_multiples);
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
# End TableChunker package
# ###########################################################################

# ###########################################################################
# Quoter package 6850
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Quoter.pm
#   trunk/common/t/Quoter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Quoter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

sub quote {
   my ( $self, @vals ) = @_;
   foreach my $val ( @vals ) {
      $val =~ s/`/``/g;
   }
   return join('.', map { '`' . $_ . '`' } @vals);
}

sub quote_val {
   my ( $self, $val ) = @_;

   return 'NULL' unless defined $val;          # undef = NULL
   return "''" if $val eq '';                  # blank string = ''
   return $val if $val =~ m/^0x[0-9a-fA-F]+$/;  # hex data

   $val =~ s/(['\\])/\\$1/g;
   return "'$val'";
}

sub split_unquote {
   my ( $self, $db_tbl, $default_db ) = @_;
   $db_tbl =~ s/`//g;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   return ($db, $tbl);
}

sub literal_like {
   my ( $self, $like ) = @_;
   return unless $like;
   $like =~ s/([%_])/\\$1/g;
   return "'$like'";
}

sub join_quote {
   my ( $self, $default_db, $db_tbl ) = @_;
   return unless $db_tbl;
   my ($db, $tbl) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   $db  = "`$db`"  if $db  && $db  !~ m/^`/;
   $tbl = "`$tbl`" if $tbl && $tbl !~ m/^`/;
   return $db ? "$db.$tbl" : $tbl;
}

1;

# ###########################################################################
# End Quoter package
# ###########################################################################

# ###########################################################################
# Transformers package 7226
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Transformers.pm
#   trunk/common/t/Transformers.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Transformers;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::Local qw(timegm timelocal);
use Digest::MD5 qw(md5_hex);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ();
our @EXPORT      = ();
our @EXPORT_OK   = qw(
   micro_t
   percentage_of
   secs_to_time
   time_to_secs
   shorten
   ts
   parse_timestamp
   unix_timestamp
   any_unix_timestamp
   make_checksum
   crc32
);

our $mysql_ts  = qr/(\d\d)(\d\d)(\d\d) +(\d+):(\d+):(\d+)(\.\d+)?/;
our $proper_ts = qr/(\d\d\d\d)-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(\.\d+)?/;
our $n_ts      = qr/(\d{1,5})([shmd]?)/; # Limit \d{1,5} because \d{6} looks

sub micro_t {
   my ( $t, %args ) = @_;
   my $p_ms = defined $args{p_ms} ? $args{p_ms} : 0;  # precision for ms vals
   my $p_s  = defined $args{p_s}  ? $args{p_s}  : 0;  # precision for s vals
   my $f;

   $t = 0 if $t < 0;

   $t = sprintf('%.17f', $t) if $t =~ /e/;

   $t =~ s/\.(\d{1,6})\d*/\.$1/;

   if ($t > 0 && $t <= 0.000999) {
      $f = ($t * 1000000) . 'us';
   }
   elsif ($t >= 0.001000 && $t <= 0.999999) {
      $f = sprintf("%.${p_ms}f", $t * 1000);
      $f = ($f * 1) . 'ms'; # * 1 to remove insignificant zeros
   }
   elsif ($t >= 1) {
      $f = sprintf("%.${p_s}f", $t);
      $f = ($f * 1) . 's'; # * 1 to remove insignificant zeros
   }
   else {
      $f = 0;  # $t should = 0 at this point
   }

   return $f;
}

sub percentage_of {
   my ( $is, $of, %args ) = @_;
   my $p   = $args{p} || 0; # float precision
   my $fmt = $p ? "%.${p}f" : "%d";
   return sprintf $fmt, ($is * 100) / ($of ||= 1);
}

sub secs_to_time {
   my ( $secs, $fmt ) = @_;
   $secs ||= 0;
   return '00:00' unless $secs;

   $fmt ||= $secs >= 86_400 ? 'd'
          : $secs >= 3_600  ? 'h'
          :                   'm';

   return
      $fmt eq 'd' ? sprintf(
         "%d+%02d:%02d:%02d",
         int($secs / 86_400),
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : $fmt eq 'h' ? sprintf(
         "%02d:%02d:%02d",
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : sprintf(
         "%02d:%02d",
         int(($secs % 3_600) / 60),
         $secs % 60);
}

sub time_to_secs {
   my ( $val, $default_suffix ) = @_;
   die "I need a val argument" unless defined $val;
   my $t = 0;
   my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
   $suffix = $suffix || $default_suffix || 's';
   if ( $suffix =~ m/[smhd]/ ) {
      $t = $suffix eq 's' ? $num * 1        # Seconds
         : $suffix eq 'm' ? $num * 60       # Minutes
         : $suffix eq 'h' ? $num * 3600     # Hours
         :                  $num * 86400;   # Days

      $t *= -1 if $prefix && $prefix eq '-';
   }
   else {
      die "Invalid suffix for $val: $suffix";
   }
   return $t;
}

sub shorten {
   my ( $num, %args ) = @_;
   my $p = defined $args{p} ? $args{p} : 2;     # float precision
   my $d = defined $args{d} ? $args{d} : 1_024; # divisor
   my $n = 0;
   my @units = ('', qw(k M G T P E Z Y));
   while ( $num >= $d && $n < @units - 1 ) {
      $num /= $d;
      ++$n;
   }
   return sprintf(
      $num =~ m/\./ || $n
         ? "%.${p}f%s"
         : '%d',
      $num, $units[$n]);
}

sub ts {
   my ( $time, $gmt ) = @_;
   my ( $sec, $min, $hour, $mday, $mon, $year )
      = $gmt ? gmtime($time) : localtime($time);
   $mon  += 1;
   $year += 1900;
   my $val = sprintf("%d-%02d-%02dT%02d:%02d:%02d",
      $year, $mon, $mday, $hour, $min, $sec);
   if ( my ($us) = $time =~ m/(\.\d+)$/ ) {
      $us = sprintf("%.6f", $us);
      $us =~ s/^0\././;
      $val .= $us;
   }
   return $val;
}

sub parse_timestamp {
   my ( $val ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $f)
         = $val =~ m/^$mysql_ts$/ )
   {
      return sprintf "%d-%02d-%02d %02d:%02d:"
                     . (defined $f ? '%09.6f' : '%02d'),
                     $y + 2000, $m, $d, $h, $i, (defined $f ? $s + $f : $s);
   }
   return $val;
}

sub unix_timestamp {
   my ( $val, $gmt ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $us) = $val =~ m/^$proper_ts$/ ) {
      $val = $gmt
         ? timegm($s, $i, $h, $d, $m - 1, $y)
         : timelocal($s, $i, $h, $d, $m - 1, $y);
      if ( defined $us ) {
         $us = sprintf('%.6f', $us);
         $us =~ s/^0\././;
         $val .= $us;
      }
   }
   return $val;
}

sub any_unix_timestamp {
   my ( $val, $callback ) = @_;

   if ( my ($n, $suffix) = $val =~ m/^$n_ts$/ ) {
      $n = $suffix eq 's' ? $n            # Seconds
         : $suffix eq 'm' ? $n * 60       # Minutes
         : $suffix eq 'h' ? $n * 3600     # Hours
         : $suffix eq 'd' ? $n * 86400    # Days
         :                  $n;           # default: Seconds
      MKDEBUG && _d('ts is now - N[shmd]:', $n);
      return time - $n;
   }
   elsif ( $val =~ m/^\d{9,}/ ) {
      MKDEBUG && _d('ts is already a unix timestamp');
      return $val;
   }
   elsif ( my ($ymd, $hms) = $val =~ m/^(\d{6})(?:\s+(\d+:\d+:\d+))?/ ) {
      MKDEBUG && _d('ts is MySQL slow log timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp(parse_timestamp($val));
   }
   elsif ( ($ymd, $hms) = $val =~ m/^(\d{4}-\d\d-\d\d)(?:[T ](\d+:\d+:\d+))?/) {
      MKDEBUG && _d('ts is properly formatted timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp($val);
   }
   else {
      MKDEBUG && _d('ts is MySQL expression');
      return $callback->($val) if $callback && ref $callback eq 'CODE';
   }

   MKDEBUG && _d('Unknown ts type:', $val);
   return;
}

sub make_checksum {
   my ( $val ) = @_;
   my $checksum = uc substr(md5_hex($val), -16);
   MKDEBUG && _d($checksum, 'checksum for', $val);
   return $checksum;
}

sub crc32 {
   my ( $string ) = @_;
   return unless $string;
   my $poly = 0xEDB88320;
   my $crc  = 0xFFFFFFFF;
   foreach my $char ( split(//, $string) ) {
      my $comp = ($crc ^ ord($char)) & 0xFF;
      for ( 1 .. 8 ) {
         $comp = $comp & 1 ? $poly ^ ($comp >> 1) : $comp >> 1;
      }
      $crc = (($crc >> 8) & 0x00FFFFFF) ^ $comp;
   }
   return $crc ^ 0xFFFFFFFF;
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
# End Transformers package
# ###########################################################################

# ###########################################################################
# MaatkitCommon package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MaatkitCommon.pm
#   trunk/common/t/MaatkitCommon.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MaatkitCommon;


use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ();
our @EXPORT      = qw();
our @EXPORT_OK   = qw(
   _d
   get_number_of_cpus
);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

sub get_number_of_cpus {
   my ( $sys_info ) = @_;
   my $n_cpus; 

   my $cpuinfo;
   if ( $sys_info || (open $cpuinfo, "<", "/proc/cpuinfo") ) {
      local $INPUT_RECORD_SEPARATOR = undef;
      my $contents = $sys_info || <$cpuinfo>;
      MKDEBUG && _d('sys info:', $contents);
      close $cpuinfo if $cpuinfo;
      $n_cpus = scalar( map { $_ } $contents =~ m/(processor)/g );
      MKDEBUG && _d('Got', $n_cpus, 'cpus from /proc/cpuinfo');
      return $n_cpus if $n_cpus;
   }


   if ( $sys_info || ($OSNAME =~ m/freebsd/i) || ($OSNAME =~ m/darwin/i) ) { 
      my $contents = $sys_info || `sysctl hw.ncpu`;
      MKDEBUG && _d('sys info:', $contents);
      ($n_cpus) = $contents =~ m/(\d)/ if $contents;
      MKDEBUG && _d('Got', $n_cpus, 'cpus from sysctl hw.ncpu');
      return $n_cpus if $n_cpus;
   } 

   $n_cpus ||= $ENV{NUMBER_OF_PROCESSORS};

   return $n_cpus || 1; # There has to be at least 1 CPU.
}

1;

# ###########################################################################
# End MaatkitCommon package
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
# SchemaIterator package 7141
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SchemaIterator.pm
#   trunk/common/t/SchemaIterator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SchemaIterator;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      filter => undef,
      dbs    => [],
   };
   return bless $self, $class;
}

sub make_filter {
   my ( $self, $o ) = @_;
   my @lines = (
      'sub {',
      '   my ( $dbh, $db, $tbl ) = @_;',
      '   my $engine = undef;',
   );


   my @permit_dbs = _make_filter('unless', '$db', $o->get('databases'))
      if $o->has('databases');
   my @reject_dbs = _make_filter('if', '$db', $o->get('ignore-databases'))
      if $o->has('ignore-databases');
   my @dbs_regex;
   if ( $o->has('databases-regex') && (my $p = $o->get('databases-regex')) ) {
      push @dbs_regex, "      return 0 unless \$db && (\$db =~ m/$p/o);";
   }
   my @reject_dbs_regex;
   if ( $o->has('ignore-databases-regex')
        && (my $p = $o->get('ignore-databases-regex')) ) {
      push @reject_dbs_regex, "      return 0 if \$db && (\$db =~ m/$p/o);";
   }
   if ( @permit_dbs || @reject_dbs || @dbs_regex || @reject_dbs_regex ) {
      push @lines,
         '   if ( $db ) {',
            (@permit_dbs        ? @permit_dbs       : ()),
            (@reject_dbs        ? @reject_dbs       : ()),
            (@dbs_regex         ? @dbs_regex        : ()),
            (@reject_dbs_regex  ? @reject_dbs_regex : ()),
         '   }';
   }

   if ( $o->has('tables') || $o->has('ignore-tables')
        || $o->has('ignore-tables-regex') ) {

      my $have_qtbl       = 0;
      my $have_only_qtbls = 0;
      my %qtbls;

      my @permit_tbls;
      my @permit_qtbls;
      my %permit_qtbls;
      if ( $o->get('tables') ) {
         my %tbls;
         map {
            if ( $_ =~ m/\./ ) {
               $permit_qtbls{$_} = 1;
            }
            else {
               $tbls{$_} = 1;
            }
         } keys %{ $o->get('tables') };
         @permit_tbls  = _make_filter('unless', '$tbl', \%tbls);
         @permit_qtbls = _make_filter('unless', '$qtbl', \%permit_qtbls);

         if ( @permit_qtbls ) {
            push @lines,
               '   my $qtbl   = ($db ? "$db." : "") . ($tbl ? $tbl : "");';
            $have_qtbl = 1;
         }
      }

      my @reject_tbls;
      my @reject_qtbls;
      my %reject_qtbls;
      if ( $o->get('ignore-tables') ) {
         my %tbls;
         map {
            if ( $_ =~ m/\./ ) {
               $reject_qtbls{$_} = 1;
            }
            else {
               $tbls{$_} = 1;
            }
         } keys %{ $o->get('ignore-tables') };
         @reject_tbls= _make_filter('if', '$tbl', \%tbls);
         @reject_qtbls = _make_filter('if', '$qtbl', \%reject_qtbls);

         if ( @reject_qtbls && !$have_qtbl ) {
            push @lines,
               '   my $qtbl   = ($db ? "$db." : "") . ($tbl ? $tbl : "");';
         }
      }

      if ( keys %permit_qtbls  && !@permit_dbs ) {
         my $dbs = {};
         map {
            my ($db, undef) = split(/\./, $_);
            $dbs->{$db} = 1;
         } keys %permit_qtbls;
         MKDEBUG && _d('Adding restriction "--databases',
               (join(',', keys %$dbs) . '"'));
         if ( keys %$dbs ) {
            $o->set('databases', $dbs);
            return $self->make_filter($o);
         }
      }

      my @tbls_regex;
      if ( $o->has('tables-regex') && (my $p = $o->get('tables-regex')) ) {
         push @tbls_regex, "      return 0 unless \$tbl && (\$tbl =~ m/$p/o);";
      }
      my @reject_tbls_regex;
      if ( $o->has('ignore-tables-regex')
           && (my $p = $o->get('ignore-tables-regex')) ) {
         push @reject_tbls_regex,
            "      return 0 if \$tbl && (\$tbl =~ m/$p/o);";
      }

      my @get_eng;
      my @permit_engs;
      my @reject_engs;
      if ( ($o->has('engines') && $o->get('engines'))
           || ($o->has('ignore-engines') && $o->get('ignore-engines')) ) {
         push @get_eng,
            '      my $sql = "SHOW TABLE STATUS "',
            '              . ($db ? "FROM `$db`" : "")',
            '              . " LIKE \'$tbl\'";',
            '      MKDEBUG && _d($sql);',
            '      eval {',
            '         $engine = $dbh->selectrow_hashref($sql)->{engine};',
            '      };',
            '      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);',
            '      MKDEBUG && _d($tbl, "uses engine", $engine);',
            '      $engine = lc $engine if $engine;',
         @permit_engs
            = _make_filter('unless', '$engine', $o->get('engines'), 1);
         @reject_engs
            = _make_filter('if', '$engine', $o->get('ignore-engines'), 1)
      }

      if ( @permit_tbls || @permit_qtbls || @reject_tbls || @tbls_regex
           || @reject_tbls_regex || @permit_engs || @reject_engs ) {
         push @lines,
            '   if ( $tbl ) {',
               (@permit_tbls       ? @permit_tbls        : ()),
               (@reject_tbls       ? @reject_tbls        : ()),
               (@tbls_regex        ? @tbls_regex         : ()),
               (@reject_tbls_regex ? @reject_tbls_regex  : ()),
               (@permit_qtbls      ? @permit_qtbls       : ()),
               (@reject_qtbls      ? @reject_qtbls       : ()),
               (@get_eng           ? @get_eng            : ()),
               (@permit_engs       ? @permit_engs        : ()),
               (@reject_engs       ? @reject_engs        : ()),
            '   }';
      }
   }

   push @lines,
      '   MKDEBUG && _d(\'Passes filters:\', $db, $tbl, $engine, $dbh);',
      '   return 1;',  '}';

   my $code = join("\n", @lines);
   MKDEBUG && _d('filter sub:', $code);
   my $filter_sub= eval $code
      or die "Error compiling subroutine code:\n$code\n$EVAL_ERROR";

   return $filter_sub;
}

sub set_filter {
   my ( $self, $filter_sub ) = @_;
   $self->{filter} = $filter_sub;
   MKDEBUG && _d('Set filter sub');
   return;
}

sub get_db_itr {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};

   my $filter = $self->{filter};
   my @dbs;
   eval {
      my $sql = 'SHOW DATABASES';
      MKDEBUG && _d($sql);
      @dbs =  grep {
         my $ok = $filter ? $filter->($dbh, $_, undef) : 1;
         $ok = 0 if $_ =~ m/information_schema|performance_schema|lost\+found/;
         $ok;
      } @{ $dbh->selectcol_arrayref($sql) };
      MKDEBUG && _d('Found', scalar @dbs, 'databases');
   };

   MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
   my $iterator = sub {
      return shift @dbs;
   };

   if (wantarray) {
      return ($iterator, scalar @dbs);
   }
   else {
      return $iterator;
   }
}

sub get_tbl_itr {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $views) = @args{@required_args, 'views'};

   my $filter = $self->{filter};
   my @tbls;
   if ( $db ) {
      eval {
         my $sql = 'SHOW /*!50002 FULL*/ TABLES FROM '
                 . $self->{Quoter}->quote($db);
         MKDEBUG && _d($sql);
         @tbls = map {
            $_->[0]
         }
         grep {
            my ($tbl, $type) = @$_;
            my $ok = $filter ? $filter->($dbh, $db, $tbl) : 1;
            if ( !$views ) {
               $ok = 0 if ($type || '') eq 'VIEW';
            }
            $ok;
         }
         @{ $dbh->selectall_arrayref($sql) };
         MKDEBUG && _d('Found', scalar @tbls, 'tables in', $db);
      };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
   }
   else {
      MKDEBUG && _d('No db given so no tables');
   }

   my $iterator = sub {
      return shift @tbls;
   };

   if ( wantarray ) {
      return ($iterator, scalar @tbls);
   }
   else {
      return $iterator;
   }
}

sub _make_filter {
   my ( $cond, $var_name, $objs, $lc ) = @_;
   my @lines;
   if ( scalar keys %$objs ) {
      my $test = join(' || ',
         map { "$var_name eq '" . ($lc ? lc $_ : $_) ."'" } keys %$objs);
      push @lines, "      return 0 $cond $var_name && ($test);",
   }
   return @lines;
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
# End SchemaIterator package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_parallel_dump;

use English qw(-no_match_vars);
use File::Basename qw(dirname);
use File::Spec;
use List::Util qw(max);
use POSIX;
use Time::HiRes qw(time);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

eval {
  require IO::Compress::Gzip;
  IO::Compress::Gzip->import(qw(gzip $GzipError));
};
my $can_gzip = $EVAL_ERROR ? 0 : 1;

Transformers->import( qw(shorten secs_to_time ts) );

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Global variables.

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

   $o->set('threads', max(2, MaatkitCommon::get_number_of_cpus()))
      unless $o->got('threads');

   # ########################################################################
   # Process options.
   # ########################################################################
   $o->set('base-dir', File::Spec->rel2abs($o->get('base-dir')));

   if ( !$o->get('help') ) {
      if ( !$o->get('threads') ) {
         $o->save_error("You must specify --threads");
      }

      if ( !$o->get('help') && $o->get('lossless-floats') && !$o->get('tab') ) {
         $o->save_error("--lossless-floats requires --tab");
      }
   }

   if ( $o->get('csv') ) {
      $o->set('tab', 1);
   }

   if ( $o->get('tab') ) {
      $o->set('umask', 0) unless $o->got('umask');
   }

   if ( $o->get('umask') ) {
      umask oct($o->get('umask'));
   }

   if ( $o->get('gzip') && !$can_gzip ) {
      $o->save_error("Cannot --gzip because the IO::Compress::Gzip module "
         . "is not installed.  Install the module or specify --no-gzip.");
   }

   $o->usage_or_errors();

   # ########################################################################
   # If --pid, check it first since we'll die if it already exits.
   # ########################################################################
   my $daemon;
   if ( $o->get('pid') ) {
      # We're not daemonizing, it just handles PID stuff.  Keep $daemon
      # in the the scope of main() because when it's destroyed it automatically
      # removes the PID file.
      $daemon = new Daemon(o=>$o);
      $daemon->make_PID_file();
   }

   # ########################################################################
   # Connect.
   # ########################################################################
   if ( $o->get('ask-pass') ) {
      $o->set('password', OptionParser::prompt_noecho("Enter password: "));
   }

   # http://code.google.com/p/maatkit/issues/detail?id=837
   my $dbh_attribs = {
      mysql_use_result => $o->get('client-side-buffering') ? 0 : 1,
   };

   my $dsn_defaults = $dp->parse_options($o);
   my $dsn  = @ARGV ? $dp->parse(shift @ARGV, $dsn_defaults)
            :         $dsn_defaults;
   my $dbh  = $dp->get_dbh($dp->get_cxn_params($dsn), $dbh_attribs);
   $dbh->{InactiveDestroy}  = 1;         # Don't die on fork().
   $dbh->{FetchHashKeyName} = 'NAME_lc'; # Lowercases all column names for fetchrow_hashref() 

   # ########################################################################
   # Stop the slave if desired.
   # ########################################################################
   if ( $o->get('stop-slave') && !$o->get('dry-run') ) {
      my $sql = 'SHOW STATUS LIKE "Slave_running"';
      MKDEBUG && _d($sql);
      my (undef, $slave_running) = $dbh->selectrow_array($sql);
      MKDEBUG && _d($slave_running);
      if ( ($slave_running || '') ne 'ON' ) {
         die "This server is not a running slave";
      }
      $sql = 'STOP SLAVE';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }

   # ########################################################################
   # Lock the whole server if desired.
   # ########################################################################
   if ( $o->get('flush-lock') && !$o->get('dry-run') ) {
      my $sql = 'FLUSH TABLES WITH READ LOCK';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }

   # ########################################################################
   # Make common modules.
   # ########################################################################
   my $q  = new Quoter();
   my $tp = new TableParser(Quoter => $q);
   my $du = new MySQLDump(cache => 0);
   my $tc = new TableChunker(Quoter => $q, MySQLDump => $du);
   my %common_modules = (
      OptionParser => $o,
      DSNParser    => $dp,
      Quoter       => $q,
      TableParser  => $tp,
      TableChunker => $tc,
      MySQLDump    => $du,
   );
   my $si = new SchemaIterator(
      Quoter => $q,
   );

   # ########################################################################
   # Find each db.tbl to dump.
   # ######################################################################## 
   my @tbls;
   my %stat_totals;  # for all dbs and tbls
   my %stats_for;    # for each db and tbl
   my $bytes  = 0;  # for progress
   my $done   = 0;  # for progress
   my $maxdb  = 0;  # for report
   my $maxtbl = 0;  # for report

   $si->set_filter($si->make_filter($o));
   my $next_db = $si->get_db_itr(dbh => $dbh);
   DATABASE:
   while ( my $db = $next_db->() ) {
      MKDEBUG && _d('Getting tables from', $db);
      my $next_tbl = $si->get_tbl_itr(
         dbh   => $dbh,
         db    => $db,
         views => 0,
      );
      TABLE:
      while ( my $tbl = $next_tbl->() ) {
         MKDEBUG && _d('Getting table', $tbl);
         my $tbl_struct;
         eval {
            $tbl_struct = $tp->parse(
               $du->get_create_table($dbh, $q, $db, $tbl));
         };
         if ( !$tbl_struct ) {
            # If this happens errors will be printed to STDERR so the
            # user knows what table is broken.  The errors are like:
            # Failed to SHOW CREATE TABLE `test`.`broken_tbl`.  The table
            # may be damaged.
            # Error: DBD::mysql::db selectrow_hashref failed: Incorrect
            # information in file: './test/broken_tbl.frm' [for Statement
            # "SHOW CREATE TABLE `test`.`broken_tbl`"] at ...
            MKDEBUG && _d('Error getting table def');
            $stats_for{$db}->{exit} = 1;
            $stat_totals{exit} = 1;
            next TABLE;
         }

         # Get table size.
         my $size = 0;
         if ( $o->get('biggest-first') || $o->get('progress') ) {
            my @tbl_stats;
            eval {
               @tbl_stats = $du->get_table_status($dbh, $q, $db, $tbl);
            };
            if ( $EVAL_ERROR ) {
               MKDEBUG && _d('Error getting table status', $EVAL_ERROR);
               $stats_for{$db}->{exit} = 1;
               $stat_totals{exit} = 1;
               next TABLE;
            }
            $size   = $tbl_stats[0]->{data_length} || 0;
            $bytes += $tbl_stats[0]->{data_length} || 0;
         }

         push @tbls, {
            db         => $db,
            tbl        => $tbl,
            tbl_struct => $tbl_struct,
            size       => $size,
         };

         # For $fmt below.
         $maxdb  = length $db  if length $db  > $maxdb;
         $maxtbl = length $tbl if length $tbl > $maxtbl;
      } # next table
   } # next database

   # ########################################################################
   # Sort the tables biggest-first.
   # ########################################################################
   if ( $o->get('biggest-first') ) {
      @tbls = sort { $b->{size} <=> $a->{size} } @tbls;
   }
   # Exclude tbl_struct from this debug else the output may be enormous.
   MKDEBUG && _d("Found tables\n",
      join("\n", map { join ' ', @{$_}{qw(db tbl size)} } @tbls));

   # ########################################################################
   # Chunk each table which by default means just one chunk, 1=1, unless
   # --chunk-size is specified.  Do this after sorting the tables so chunks
   # for the biggest tables will be done first.
   # ########################################################################
   my @chunks = chunk_tables(
      tbls        => \@tbls,
      dbh         => $dbh,
      stat_totals => \%stat_totals,
      stats_for   => \%stats_for,
      %common_modules,
   );

   # ########################################################################
   # Flush logs and get binlog pos.
   # ########################################################################
   if ( $o->get('flush-log') && !$o->get('dry-run') ) {
      my $sql = 'FLUSH LOGS';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }
   if ( $o->get('bin-log-position') && !$o->get('dry-run') ) {
      dump_binlog_pos(
         dbh    => $dbh,
         chunks => \@chunks,
         %common_modules,
      );
   }

   # #####################################################################
   # Design the format for printing out.
   # #####################################################################
   my $db_tbl_width = $maxdb + (($o->get('verbose')||0) > 1 ? $maxtbl : 0) + 1;
   $db_tbl_width    = 14 if $db_tbl_width < 14;
   my $fmt = "%5s %5s %5s %8s %-${db_tbl_width}s %-s";
   info($o, 0, sprintf($fmt,
      qw(CHUNK TIME EXIT SKIPPED DATABASE.TABLE),
      ($o->get('progress') ? 'PROGRESS' : ''))
   );

   # #####################################################################
   # Assign the work to child processes.  Initially just start --threads
   # number of children.  Each child that exits will trigger a new one to
   # start after that.  This is really a terrible hack -- I wish Perl had
   # decent threading support so I could just queue work for a fixed pool
   # of worker threads!
   # #####################################################################
   
   # This signal handler will do nothing but wake up the sleeping parent process
   # and record the exit status and time of the child that exited (as a side
   # effect of not discarding the signal).
   my %kids;
   my %exited_children;
   $SIG{CHLD} = sub {
      my $kid;
      while (($kid = waitpid(-1, POSIX::WNOHANG)) > 0) {
         MKDEBUG && _d('Process', $kid, 'exited with', $CHILD_ERROR);
         # Must right-shift to get the actual exit status of the child.
         $exited_children{$kid}->{exit} = $CHILD_ERROR >> 8;
         $exited_children{$kid}->{time} = time();
      }
   };

   my $start = time();
   while ( @chunks || %kids ) {
      # Wait for the MySQL server to become responsive.
      my $tries = 0;
      while ( !$dbh->ping && $tries++ < $o->get('wait') ) {
         sleep(1);
         eval {
            $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), $dbh_attribs);
         };
         if ( $EVAL_ERROR ) {
            info($o, 0, 'Waiting: ' . scalar(localtime)
               . ' ' . mysql_error_msg($EVAL_ERROR));
         }
      }
      if ( $tries >= $o->get('wait') ) {
         die "Too many retries, exiting.\n";
      }

      # Start a new child process.
      while ( @chunks && (keys %kids < $o->get('threads')) ) {
         my $chunk = shift @chunks;
         my $file  = filename($o->get('base-dir'),
            interp($chunk, '%D', '%N.%6C'));
         makedir($file) unless $o->get('dry-run');

         # Set start time for database, table and chunk.  Do this before
         # possibly skipping the chunk so report_stats() doesn't die due
         # to a db or tbl not having a time value.
         $stats_for{$chunk->{D}}->{start_time} = time
            if $chunk->{first_tbl_in_db};
         $stats_for{$chunk->{D}}->{tables}->{$chunk->{N}}->{start_time} = time
            if $chunk->{C} == 0;
         $chunk->{start_time} = time;

         # See if this chunk has already been done.
         if ( $o->get('resume') && (-f "$file.sql" || -f "$file.sql.gz") ) {
            $done += $chunk->{Z} || 0;
            $stat_totals{skipped}++;
            $stats_for{$chunk->{D}}->{skipped}++;
            $stats_for{$chunk->{D}}->{tables}->{$chunk->{N}}->{skipped}++;
            $chunk->{skipped}++;
            my $progress = update_progress($o, $start, $bytes, $done);
            $chunk->{exit} = 0;
            $chunk->{time} = 0;
            report_stats(
               chunk       => $chunk,
               stat_totals => \%stat_totals,
               stats_for   => \%stats_for,
               fmt         => $fmt,
               progress    => $progress,
               %common_modules,
            );
            next;
         }

         # Lock the table if --lock-tables and this is the first chunk
         # of the table.  It will be unlocked after the table's last chunk.
         # Do this here, not in a child, so the lock holds during all
         # chunks (each child makes a new connection to MySQL so if the
         # child that does this chunk acquires the lock, it will be lost
         # when it exits).
         if ( $chunk->{C} == 0
              && $o->get('lock-tables')
              && !$o->get('dry-run') ) {
            my $db_tbl = $q->quote($chunk->{D}, $chunk->{N});
            my $sql    = "LOCK TABLES $db_tbl READ";
            MKDEBUG && _d($sql);
            eval {
               $dbh->do($sql);
            };
            # This shouldn't happen.
            warn $EVAL_ERROR if $EVAL_ERROR;
         }

         my $pid = fork();
         die "Can't fork: $OS_ERROR" unless defined $pid;
         if ( $pid ) {              # I'm the parent
            $kids{$pid} = $chunk;
         }
         else {                     # I'm the child
            $SIG{CHLD} = 'DEFAULT'; # See bug #1886444
            MKDEBUG && _d('Start PID', $PID);
            my $exit_status = dump_chunk(
               chunk       => $chunk,
               file        => $file,
               dsn         => $dsn,
               dbh_attribs => $dbh_attribs,
               %common_modules,
            );
            MKDEBUG && _d('End PID', $PID, 'exit status', $exit_status);
            exit $exit_status;
         }
      }

      # Possibly wait for child.
      my $reaped = 0;
      foreach my $pid ( keys %exited_children ) {
         my $chunk = $kids{$pid};
         $chunk->{exit} = $exited_children{$pid}->{exit};
         $chunk->{time} = $exited_children{$pid}->{time} - $chunk->{start_time};

         if ( $chunk->{last_chunk_in_tbl}
              && $o->get('lock-tables')
              && !$o->get('dry-run') ) {
            my $db_tbl = $q->quote($chunk->{D}, $chunk->{N});
            my $sql    = "UNLOCK TABLES";
            MKDEBUG && _d($sql);
            eval {
               $dbh->do($sql);
            };
            warn $EVAL_ERROR if $EVAL_ERROR;
         }

         $done += $chunk->{Z} || 0;
         my $progress = update_progress($o, $start, $bytes, $done);
         report_stats(
            chunk       => $chunk,
            stat_totals => \%stat_totals,
            stats_for   => \%stats_for,
            fmt         => $fmt,
            progress    => $progress,
            %common_modules,
         );

         $reaped = 1;
         delete $kids{$pid};
         delete $exited_children{$pid};
      }

      if ( !$reaped ) {
         # Don't busy-wait.  But don't wait forever either, as a child
         # may exit and signal while we're not sleeping, so if we sleep
         # forever we may not get the signal.
         MKDEBUG && _d('No children reaped, sleeping');
         sleep 1;
      }

      MKDEBUG && _d(scalar @chunks, "chunks left; ",
         "outstanding child processes:\n", join("\n",
            map { "PID $_ $kids{$_}->{D}.$kids{$_}->{N} chunk $kids{$_}->{C}" }
            keys %kids));
   } # while chunks or kids

   # ########################################################################
   # Unlock tables possibly locked with FLUSH TABLES WITH READ LOCK.
   # ########################################################################
   if ( !$o->get('dry-run') ) {
      my $sql = 'UNLOCK TABLES';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }
   $dbh->commit();

   # ########################################################################
   # Restart the slave if desired.
   # ########################################################################
   if ( $o->get('stop-slave') && !$o->get('dry-run') ) {
      my $sql = 'START SLAVE';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }

   $dbh->disconnect();

   $stat_totals{wallclock} = time() - $start;
   my $progress = '';
   if ( $o->get('progress') ) {
      $progress = 'done at ' . ts(time) .', '
                . join(', ',
                     map { ($stat_totals{counts}->{$_} || 0) . " $_" }
                        qw(databases tables chunks));
   }
   info($o, 0, sprintf($fmt,
         'all',
         sprintf('%.2f', $stat_totals{wallclock}),
         $stat_totals{exit} || 0,
         $stat_totals{skipped} || 0,
         '-',
         $progress)
   );

   return $stat_totals{exit} || 0;
}

# ############################################################################
# Subroutines
# ############################################################################

sub mysql_error_msg {
   my ( $text ) = @_;
   $text =~ s/^.*?failed: (.*?) at \S+ line (\d+).*$/$1 at line $2/s;
   return $text;
}

sub chunk_tables {
   my ( %args ) = @_;
   my @required_args = qw(dbh tbls stat_totals stats_for OptionParser
                          Quoter TableChunker);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $tbls, $stat_totals, $stats_for) = @args{@required_args};

   if ( scalar @$tbls == 0 ) {
      MKDEBUG && _d('No tables to chunk');
      return ();
   }

   my %seen_db;
   my $last_db  = '';
   my $n_tables = scalar @$tbls - 1;
   my $chunkno  = 0;
   my @chunks;
   for my $tblno ( 0..$n_tables ) {
      my $tbl  = $tbls->[$tblno];
      my $cols = make_col_list(tbl_struct=>$tbl->{tbl_struct}, %args);
      eval {
         my $i = 0;
         push @chunks, map {
            my $chunk = {
               D => $_->{D},  # Database name
               N => $_->{N},  # Table name
               W => $_->{W},  # WHERE clause
               E => $_->{E},  # Storage engine
               Z => $_->{Z},  # Chunk size
               C => $i++,     # Chunk number for this table
               L => $cols,    # SELECT list
               S => $tbl->{tbl_struct},
            };

            # @chunks is a continuous list of db.tbl.chunk.  To report per-db
            # and per-tbl info we need to know the first table in each db
            # and the number of chunks in each db and table.  So, this chunk
            # is the first in this db if this db has never been seen before,
            # and...
            $chunk->{first_tbl_in_db} = 1 if !$seen_db{$chunk->{D}}++;

            $chunkno++;
            $chunk;  # save the chunk
         } get_chunks(tbl => $tbl, %args);

         # ...save the number of chunk in each db and table.  These values
         # are decremented so we can reliably know when a table and db are
         # fully done (when there's no more chunks left).
         $stats_for->{$tbl->{db}}->{tables}->{$tbl->{tbl}}->{chunks_left} += $i;
         $stats_for->{$tbl->{db}}->{chunks_left} += $i;

         # Save the number of chunks again.  These values aren't modified;
         # they for status reports (see report_stats()).
         $stats_for->{$tbl->{db}}->{tables}->{$tbl->{tbl}}->{chunks} = $i;
         $stats_for->{$tbl->{db}}->{chunks} += $i;

         # last_chunk_in_tbl is used to tell us when we can unlock the
         # table if using --lock-tables.  The last chunk (-1) is the last
         # one for this table.
         $chunks[-1]->{last_chunk_in_tbl} = 1;  
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d('Error getting chunks for', $tbl->{db}, '.', $tbl->{tbl},
            ':', $EVAL_ERROR);
         $stat_totals->{exit} |= 1;
         $stats_for->{$tbl->{db}}->{$tbl->{tbl}}->{exit} |= 1;
         next;
      }
   }

   $stat_totals->{counts}->{databases} = scalar keys %seen_db;
   $stat_totals->{counts}->{tables}    = scalar @$tbls;
   $stat_totals->{counts}->{chunks}    = scalar @chunks;

   return @chunks;
}

# Return a list of all columns not '*' so we can build a proper
# "INSERT INTO tbl (cols) VALUES ..." in dump_sql_chunk().
# For FLOAT and DOUBLE, if lossless floating point dumps are desired,
# wrap the column with REPLACE(FORMAT(col, 17), ',', '').
sub make_col_list {
   my ( %args ) = @_;
   my @required_args = qw(tbl_struct OptionParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl_struct, $o, $q) = @args{@required_args};

   my @cols = map {
      my $col;
      if ( $tbl_struct->{type_for}->{$_} =~ m/float|double/
           && $o->get('lossless-floats') ) {
         $col = sprintf("REPLACE(FORMAT(%s, 17), ',', '')", $q->quote($_));
      }
      else {
         $col = $q->quote($_);
      }
      $col;
   } @{$tbl_struct->{cols}};

   return join(',', @cols);
}

sub get_chunks {
   my ( %args ) = @_;
   my @required_args = qw(tbl dbh OptionParser TableChunker);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my (undef, $dbh, $o, $tc) = @args{@required_args};
   my $db         = $args{tbl}->{db};
   my $tbl        = $args{tbl}->{tbl};
   my $tbl_struct = $args{tbl}->{tbl_struct};

   # Decide where to store the file of chunks, which is important for resuming a
   # dump -- the precalculated chunks must be used, not re-calculated, or
   # resuming might go awry.
   my $chunkfile = filename($o->get('base-dir'),
      interp({D => $db, N => $tbl}, '%D', '%N.chunks'));
   makedir($chunkfile) unless $o->get('dry-run');

   # Resume dump by reading chunk boundaries from chunk file
   # if it already exists.
   if ( $o->get('resume') && -f $chunkfile ) {
      MKDEBUG && _d('Chunk file', $chunkfile, 'exists, using it');
      open my $fh, "<", $chunkfile or die "Can't open $chunkfile: $OS_ERROR";
      my @chunks;
      while ( my $where = <$fh> ) {
         chomp $where;
         push @chunks, {
            D => $db,
            N => $tbl,
            W => $where,
            E => $tbl_struct->{engine},
            Z => $args{tbl}->{size},
         };
      };
      close $fh or die "Can't close $chunkfile: $OS_ERROR";
      return @chunks;
   }

   # By default we can't/don't chunk because --chunk-size has no default
   # value so each table is one big chunk (1=1).
   my $cant_chunk = {
      D => $db,
      N => $tbl,
      W => '1=1',
      E => $tbl_struct->{engine},
      Z => $args{tbl}->{size},
   };
   return $cant_chunk unless $o->get('chunk-size');

   # Check that this table can be chunked.
   my ($col, undef)  = $tc->get_first_chunkable_column(tbl_struct=>$tbl_struct);
   return $cant_chunk unless $col;
   my %range_stats = $tc->get_range_statistics(
      dbh        => $dbh,
      db         => $db,
      tbl        => $tbl,
      chunk_col  => $col,
      tbl_struct => $tbl_struct,
   );
   return $cant_chunk
      if grep { !defined $range_stats{$_} } qw(min max rows_in_range);

   # Get chunk boundaries (WHERE clauses).
   my ($rows_per_chunk, $avg_row_len) = $tc->size_to_rows(
      dbh            => $dbh,
      db             => $db,
      tbl            => $tbl,
      chunk_size     => $o->get('chunk-size'),
      avg_row_length => 1,  # always get avg row length
   );
   my @chunk_boundaries = $tc->calculate_chunks(
      dbh        => $dbh,
      db         => $db,
      tbl        => $tbl,
      tbl_struct => $tbl_struct,
      chunk_col  => $col,
      chunk_size => $rows_per_chunk,
      zero_chunk => $o->get('zero-chunk'),
      %range_stats,
   );
   my $avg_chunk_size = $rows_per_chunk * $avg_row_len;
   MKDEBUG && _d('Rows per chunk:', $rows_per_chunk,
      'avg row len:', $avg_row_len, 'avg chunk size:', $avg_chunk_size);

   # Write chunk boundaries to the chunk file.
   my $fh;
   if ( !$o->get('dry-run') ) {
      open $fh, ">", $chunkfile or die "Can't open $chunkfile: $OS_ERROR";
   }
   my @chunks = map {
      if ( !$o->get('dry-run') ) {
         print $fh $_, "\n" or die "Can't print to $chunkfile: $OS_ERROR";
      }
      {
         D => $db,
         N => $tbl,
         W => $_,
         E => $tbl_struct->{engine},
         Z => $avg_chunk_size,
      }
   } @chunk_boundaries;
   if ( !$o->get('dry-run') ) {
      close $fh or die "Can't close $chunkfile: $OS_ERROR";
   }

   return @chunks;
}

# Prints a message.
sub info {
   my ( $o, $level, $msg ) = @_;
   return if $o->get('quiet');
   print "$msg\n" if $level <= ($o->get('verbose') || 0);
}

# Interpolates % directives from a db/tbl hashref, to insert % variables into
# arguments.  The available macros are as follows:
# 
#  MACRO  MEANING
#  =====  =================
#  %D     The database name
#  %N     The table name
#  %C     The chunk number
#  %W     The WHERE clause
#
# You can place a number between the % and the letter.  The macro replacement
# then assumes it's a digit and pads it with leading zeroes (in practice, this is
# only useful for %C).
sub interp {
   my ( $chunk, @strings ) = @_;
   map {
      $_ =~ s/%(\d+)?([SDNCW])/$1 ? sprintf("%0$1d", $chunk->{$2})
                                  : $chunk->{$2}/ge
   } @strings;
   return @strings;
}

# Dump a chunk of a table.  Each table is a single chunk (1=1) unless
# --chunk-size is specified.
sub dump_chunk {
   my ( %args ) = @_;
   my @required_args = qw(chunk file DSNParser OptionParser Quoter MySQLDump
                          dsn dbh_attribs);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($chunk, $file, $dp, $o, $q, $du) = @args{@required_args};
   my $D           = $q->quote($chunk->{D});
   my $N           = $q->quote($chunk->{N});
   my $exit_status = 0;

   MKDEBUG && $chunk->{C} == 0 && _d('Dumping', Dumper($chunk));

   my $dbh;
   if ( !$o->get('dry-run') ) {
      my $dsn         = $args{dsn};
      my $dbh_attribs = $args{dbh_attribs};
      $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), $dbh_attribs);
   }

   # Dump SHOW CREATE TABLE  before the first chunk.
   if ( $chunk->{C} == 0 && !$o->get('dry-run') ) {
      my $ddl = $dbh->selectrow_arrayref("SHOW CREATE TABLE $D.$N")->[1];
      if ( $ddl ) {
         my $ctfile = filename($o->get('base-dir'),
                               interp($chunk, '%D', '00_%N.sql'));
         open my $fh, '>', $ctfile or die "Can't open $ctfile: $OS_ERROR";
         print $fh $ddl            or die "Can't print to $ctfile: $OS_ERROR";
         close $fh                 or die "Can't close $ctfile: $OS_ERROR";
      }
      else {
         warn "Failed to dump SHOW CREATE TABLE $D.$N";
         $exit_status = 1;
      }
   }

   if ( $o->get('tab') ) {  # dump via SELECT INTO OUTFILE
      my $sql
        = $o->get('csv')
        ?    "SELECT $chunk->{L} INTO OUTFILE '$file.txt' "
           . "FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\\\"' "
           . "LINES TERMINATED BY '\\n' FROM $D.$N WHERE $chunk->{W}"
        :    "SELECT $chunk->{L} INTO OUTFILE '$file.txt' "
           . "FROM $D.$N WHERE $chunk->{W};";
      if ( $o->get('dry-run') ) {
         print $sql, "\n" unless $o->get('quiet');
      }
      else {
         eval {
            $dbh->do($sql);
         };
         if ( $EVAL_ERROR ) {
            warn mysql_error_msg($EVAL_ERROR) . "\n";
            $exit_status |= 1;
         }
      }
   }
   else {
      $file = $o->get('gzip') ? "$file.sql.gz" : "$file.sql";
      my $fh;
      if ( !$o->get('dry-run') ) {
         open $fh, '>', $file or die "Cannot open $file: $OS_ERROR";
      }
      $exit_status |= dump_sql_chunk(
         chunk   => $chunk,
         file    => $file,
         fh      => $fh,
         dbh     => $dbh,
         dry_run => $o->get('dry-run'),
         %args
      );
      if ( $fh && !$o->get('dry-run') ) {
         close $fh or die "Cannot close $file: $OS_ERROR";
      }
   }

   $dbh->disconnect() if $dbh;

   return $exit_status;
}

sub dump_sql_chunk {
   my ( %args ) = @_;
   my @required_args = qw(chunk file Quoter OptionParser);
   push @required_args, qw(fh dbh) unless $args{dry_run};
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($chunk, $file, $q, $o, $fh, $dbh) = @args{@required_args};
   my $exit_status = 0;

   # Open a compressed filehandle if --gzip.  Else, just point
   # $zfh to non-compressed $fh.  Only use $zfh after this point.
   # Caller closes $fh so don't close $zfh here.
   my $zfh;
   if ( $o->get('gzip') && !$o->get('dry-run') ) {
      our $GzipError;
      $zfh = new IO::Compress::Gzip($fh)
         or die "IO::Compress::Gzip failed: $GzipError\n";
   }
   else {
      $zfh = $fh;  # no compression (--no-gzip)
   }

   my $tbl_struct = $chunk->{S};
   my $n_cols     = scalar @{$tbl_struct->{cols}};
   my $db_tbl     = $q->quote($chunk->{D}, $chunk->{N});
   my $tz_utc     = "/*!40103 SET TIME_ZONE='+00:00' */;";
   my $sql        = "SELECT /*chunk $chunk->{C}*/ $chunk->{L} "
                  . "FROM $db_tbl "
                  . "WHERE  $chunk->{W};";

   # Set timezone to UTC/GMT for consistent dump/restore
   # of TIMESTAMP columns.
   if ( $o->get('tz-utc') ) {
      MKDEBUG && _d($dbh, $tz_utc);
      if ( $o->get('dry-run') ) {
         print $tz_utc, "\n";
      }
      else {
         $dbh->do($tz_utc);
         print $zfh $tz_utc, "\n";
      }
   }

   # Print the SELECT chunk and return early if dry-run.  Everything
   # below is actual data-accessing work.
   if ( $o->get('dry-run') ) {
      print $sql, "\n";
      return $exit_status;
   }

   # Execute the SELECT chunk to get the rows to dump.  Don't use
   # $dbh->selectall_arrayref() because it does not throw errors
   # from execute, so we would miss stuff like "the table is marked
   # as crashed".
   MKDEBUG && _d($dbh, $sql);
   my $rows;
   eval {
      my $sth = $dbh->prepare($sql);
      $sth->execute();
      $rows = $sth->fetchall_arrayref();
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($dbh, $EVAL_ERROR);
      $exit_status = 1;  # general error unless...
      $exit_status = 3 if $EVAL_ERROR =~ m/ crashed /;
      return $exit_status;
   }

   # Write the INSERT for the row values to the dump file, row by row.
   # Don't build the whole INSERT else $sql may consume a lot of memory.
   if ( @$rows ) {
      $sql = "INSERT /*chunk $chunk->{C}*/ "
           . "INTO " . $q->quote($chunk->{N}) . " ($chunk->{L}) VALUES ";
      MKDEBUG && _d('Write', $sql, 'to', $file);
      print $zfh $sql;
      my $rowno = 0;
      ROW:
      foreach my $row ( @$rows ) {
         COL:
         for my $i ( 0..($n_cols-1) ) {
            # Escape and quote column values in place (i.e. in $row).
            if ( $row->[$i] ) {
               my $col = $tbl_struct->{cols}->[$i];
               if ( !$tbl_struct->{is_numeric}->{$col} ) {
                  $row->[$i] = q{'}.escape_string_for_mysql($row->[$i]).q{'};
               }
               # Numeric columns are not quoted.
            }
            else {
               $row->[$i] = defined $row->[$i] ? q{''} : 'NULL';
            }
         }
         my $val = ($rowno++ ? ',(' : '(') . join(',', @$row) . ')';
         print $zfh $val;
      }
      print $zfh ";\n";
      MKDEBUG && _d('Dumped', $rowno, 'rows');
   }
   else {
      MKDEBUG && _d('Empty table:', $db_tbl);
   }

   return $exit_status;
}

# Perl version of escape_string_for_mysql() in mysys/charset.c.
sub escape_string_for_mysql {
   my ( $str ) = @_;
   return unless $str;
   $str =~ s/\\/\\\\/g;  # match this first
   $str =~ s/\x00/\\0/g;
   $str =~ s/\n/\\n/g;
   $str =~ s/\r/\\r/g;
   $str =~ s/(['"])/\\$1/g;
   $str =~ s/\032/\\Z/g;
   return $str;
}

# Makes a filename.
sub filename {
   my ( $base_dir, @file_name ) = @_;
   my $filename = File::Spec->catfile($base_dir, @file_name);
   return $filename;
}

{
   # Do not memorize else tests will fail because we don't
   # recreate dirs that the tests rm.

   # If the directory doesn't exist, makes the directory.
   sub makedir {
      my ( $filename ) = @_;
      my @dirs = File::Spec->splitdir(dirname($filename));
      foreach my $i ( 0 .. $#dirs ) {
         my $dir = File::Spec->catdir(@dirs[0 .. $i]);
         if ( ! -d $dir ) {
            MKDEBUG && _d('mkdir', $dir);
            mkdir($dir, 0777) or die "Failed to mkdir $dir: $OS_ERROR";
         }
      }
   }
}

sub dump_binlog_pos {
   my ( %args ) = @_;
   my @required_args = qw(dbh chunks OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $chunks, $o) = @args{@required_args};

   my $file = filename($o->get('base-dir'), '', '00_master_data.sql');
   makedir($file) unless $o->get('dry-run');
   MKDEBUG && _d('Writing to', $file);
   open my $fh, ">", $file or die "Cannot open $file: $OS_ERROR";
   my %wanted = map { $_ => 1 }
      qw(file position master_host master_port master_log_file
      read_master_log_pos relay_log_file relay_log_pos
      relay_master_log_file exec_master_log_pos);

   my ( $master_pos, $slave_pos );
   eval {
      my $sql = 'SHOW MASTER STATUS';
      MKDEBUG && _d($sql);
      $master_pos = $dbh->selectrow_hashref($sql);
   };
   eval {
      my $sql = 'SHOW SLAVE STATUS';
      MKDEBUG && _d($sql);
      $slave_pos = $dbh->selectrow_hashref($sql);
      print $fh "CHANGE MASTER TO MASTER_HOST='$slave_pos->{master_host}', "
         . "MASTER_LOG_FILE='$slave_pos->{relay_master_log_file}', "
         . "MASTER_LOG_POS=$slave_pos->{exec_master_log_pos}\n"
         or die $OS_ERROR;
   };

   foreach my $thing ( $master_pos, $slave_pos ) {
      next unless $thing;
      foreach my $key ( grep { $wanted{$_} } sort keys %$thing ) {
         print $fh "-- $key $thing->{$key}\n"
            or die $OS_ERROR;
      }
   }

   # Put the details of the chunks into the file.
   foreach my $chunk ( @$chunks ) {
      print $fh "-- CHUNK $chunk->{D} $chunk->{N} $chunk->{C} $chunk->{W}\n"
         or die $OS_ERROR;
   }

   close $fh or die $OS_ERROR;

   return;
}

sub report_stats {
   my ( %args ) = @_;
   my @required_args = qw(chunk stat_totals stats_for fmt progress
                          OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($chunk, $stat_totals, $stats_for, $fmt, $progress, $o)
      = @args{@required_args};

   my $exit_status = $chunk->{exit};

   # Update stat totals (global stats).
   $stat_totals->{exit} |= $exit_status;

   # Update database and table stats.
   my $db        = $chunk->{D};
   my $tbl       = $chunk->{N};
   my $db_stats  = $stats_for->{$db};
   my $tbl_stats = $stats_for->{$db}->{tables}->{$tbl};
   foreach my $stats ( $db_stats, $tbl_stats ) {
      $stats->{exit} |= $exit_status;
      $stats->{chunks_left} -= 1;
   }

   # Report completed chunk.
   info($o, 2, sprintf($fmt,
      $chunk->{C},
      sprintf('%.2f', $chunk->{time}),
      $exit_status,
      $chunk->{skipped} || 0,
      "$chunk->{D}.$chunk->{N}",
      $progress,)
   );

   # Report completed table.
   if ( !$tbl_stats->{chunks_left} ) {
      info($o, 1, sprintf($fmt,
         'tbl',
         sprintf('%.2f', time - $tbl_stats->{start_time}),
         $tbl_stats->{exit} || 0,
         $tbl_stats->{skipped}  || 0,
         "$chunk->{D}.$chunk->{N}",
         $progress,)
      );
   }

   # Report completed database.
   if ( !$db_stats->{chunks_left} ) {
      info($o, 0, sprintf($fmt,
            'db',
            sprintf('%.2f', time - $db_stats->{start_time}),
            $db_stats->{exit} || 0,
            $db_stats->{skipped}  || 0,
            $chunk->{D},
            $progress,)
      );
   }

   return;
}

sub update_progress {
   my ( $o, $start, $bytes, $done ) = @_;
   my $progress = '';
   if ( $o->get('progress') ) {
      my $pct = $done / ($bytes || 1);
      my $now = time();
      my $remaining = ($now - $start) / ($pct || 1);
      $progress = sprintf("%s/%s %6.2f%% ETA %s (%s)",
            shorten($done),
            shorten($bytes),
            $pct * 100,
            secs_to_time($remaining),
            ts($now + $remaining),
         );
   }
   return $progress;
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
# Documentation.
# ############################################################################

=pod

=head1 NAME

mk-parallel-dump - (DEPRECATED) Dump MySQL tables in parallel.

=head1 SYNOPSIS

This tool is deprecated because after several complete redesigns, we concluded
that Perl is the wrong technology for this task.  Read L<"RISKS"> before you use
it, please.  It remains useful for some people who we know aren't depending on
it in production, and therefore we are not removing it from the distribution.

Usage: mk-parallel-dump [OPTION...] [DSN]

mk-parallel-dump dumps MySQL tables in parallel to make some data loading
operations more convenient.  IT IS NOT A BACKUP TOOL!

Dump all databases and tables to the current directory:

  mk-parallel-dump

Dump all databases and tables via SELECT INTO OUTFILE to /tmp/dumps:

  mk-parallel-dump --tab --base-dir /tmp/dumps

Dump only table db.foo in chunks of ten thousand rows using 8 threads:

  mk-parallel-dump --databases db --tables foo \
     --chunk-size 10000 --threads 8

Dump tables in chunks of approximately 10kb of data (not ten thousand rows!):

  mk-parallel-dump --chunk-size 10k

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-parallel-dump is not a backup program!  It is only designed for fast data
exports, for purposes such as quickly loading data into test systems.  Do not
use mk-parallel-dump for backups.

At the time of this release there is a bug that prevents L<"--lock-tables"> from
working correctly, an unconfirmed bug that prevents the tool from finishing,
a bug that causes the wrong character set to be used, and a bug replacing
default values.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-parallel-dump>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-parallel-dump connects to a MySQL server, finds database and table names,
and dumps them in parallel for speed.  Only tables and data are dumped;
view definitions or any kind of stored code (triggers, events, routines,
procedures, etc.) are not dumped.  However, if you dump the C<mysql> database,
you'll be dumping the stored routines anyway.

Exit status is 0 if everything went well, 1 if any chunks failed, and any
other value indicates an internal error.

To dump all tables to uncompressed text files in the current directory, each
database with its own directory, with a global read lock, flushing and
recording binary log positions, each table in a single file:

  mk-parallel-dump

To dump tables elsewhere:

  mk-parallel-dump --base-dir /path/to/elsewhere

To dump to tab-separated files with C<SELECT INTO OUTFILE>, each table with
separate data and SQL files:

  mk-parallel-dump --tab

mk-parallel-dump doesn't clean out any destination directories before
dumping into them.  You can move away the old destination, then remove it
after a successful dump, with a shell script like the following:

   #!/bin/sh
   CNT=`ls | grep -c old`;
   if [ -d default ]; then mv default default.old.$CNT;
   mk-parallel-dump
   if [ $? != 0 ]
   then
      echo "There were errors, not purging old sets."
   else
      echo "No errors during dump, purging old sets."
      rm -rf default.old.*
   fi

mk-parallel-dump checks whether files have been created before dumping.  If the
file has been created, it skips the table or chunk that would have created the
file.  This makes it possible to resume dumps.  If you don't want this behavior,
and instead you want a full dump, then move away the old files or specify
L<"--[no]resume">.

=head1 CHUNKS

mk-parallel-dump can break your tables into chunks when dumping, and put
approximately the amount of data you specify into each chunk.  This is useful
for two reasons:

=over

=item *

A table that is dumped in chunks can be dumped in many threads simultaneously.

=item *

Dumping in chunks creates small files, which can be imported more efficiently
and safely.  Importing a single huge file can be a lot of extra work for
transactional storage engines like InnoDB.  A huge file can create a huge
rollback segment in your tablespace.  If the import fails, the rollback can take
a very long time.

=back

To dump in chunks, specify the L<"--chunk-size"> option.  This option is an
integer with an optional suffix.  Without the suffix, it's the number of rows
you want in each chunk.  With the suffix, it's the approximate size of the data.

mk-parallel-dump tries to use index statistics to calculate where the
boundaries between chunks should be.  If the values are not evenly distributed,
some chunks can have a lot of rows, and others may have very few or even none.
Some chunks can exceed the size you want.

When you specify the size with a suffix, the allowed suffixes are k, M and G,
for kibibytes, mebibytes, and gibibytes, respectively.  mk-parallel-dump
doesn't know anything about data size.  It asks MySQL (via C<SHOW TABLE STATUS>)
how long an average row is in the table, and converts your option to a number
of rows.

Not all tables can be broken into chunks.  mk-parallel-dump looks for an
index whose leading column is numeric (integers, real numbers, and date and time
types).  It prefers the primary key if its first column is chunk-able.
Otherwise it chooses the first chunk-able column in the table.

Generating a series of C<WHERE> clauses to divide a table into evenly-sized
chunks is difficult.  If you have any ideas on how to improve the algorithm,
please write to the author (see L<"BUGS">).

=head1 OUTPUT

Output depends on L<"--verbose">, L<"--progress">, L<"--dry-run"> and
L<"--quiet">.  If L<"--dry-run"> is specified mk-parallel-dump prints the
commands or SQL statements that it would use to dump data but it does not
actually dump any data.  If L<"--quiet"> is specified there is no output;
this overrides all other options that affect the output.

The default output is something like the following example:

  CHUNK  TIME  EXIT  SKIPPED DATABASE.TABLE 
     db  0.28     0        0 sakila         
    all  0.28     0        0 -

=over

=item CHUNK

The CHUNK column signifies what kind of information is in the line:

  Value  Meaning
  =====  ========================================================
  db     This line contains summary information about a database.
  tbl    This line contains summary information about a table.
  <int>  This line contains information about the Nth chunk of a
         table.

The types of lines you'll see depend on the L<"--chunk-size"> option and
L<"--verbose"> options.  mk-parallel-dump treats everything as a chunk.  If you
don't specify L<"--chunk-size">, then each table is one big chunk and each
database is a chunk (of all its tables).  Thus, there is output for numbered
table chunks (L<"--chunk-size">), table chunks, and database chunks.

=item TIME

The TIME column shows the wallclock time elapsed while the chunk was dumped.  If
CHUNK is "db" or "tbl", this time is the total wallclock time elapsed for the
database or table.

=item EXIT

The EXIT column shows the exit status of the chunk.  Any non-zero exit signifies
an error.  The cause of errors are usually printed to STDERR.

=item SKIPPED

The SKIPPED column shows how many chunks were skipped.  These are not
errors.  Chunks are skipped if the dump can be resumed.  See L<"--[no]resume">.

=item DATABASE.TABLE

The DATABASE.TABLE column shows to which table the chunk belongs.  For "db"
chunks, this shows just the database.  Chunks are printed when they complete,
and this is often out of the order you'd expect.  For example, you might see a
chunk for db1.table_1, then a chunk for db2.table_2, then another chunk for
db1.table_1, then the "db" chunk summary for db2.

=item PROGRESS

If you specify L<"--progress">, then the tool adds a PROGRESS column after
DATABASE.TABLE, which contains text similar to the following:

  PROGRESS
  4.10M/4.10M 100.00% ETA ... 00:00 (2009-10-16T15:37:49)
  done at 2009-10-16T15:37:48, 1 databases, 16 tables, 16 chunks

This column shows information about the amount of data dumped so far, the
amount of data left to dump, and an ETA ("estimated time of arrival").  The ETA
is a best-effort prediction when everything will be finished dumping.  Sometimes
the ETA is very accurate, but at other times it can be significantly wrong.

=back

The final line of the output is special: it summarizes all chunks (all table
chunks, tables and databases).

If you specify L<"--verbose"> once, then the output includes "tbl" CHUNKS:

  CHUNK  TIME  EXIT  SKIPPED DATABASE.TABLE 
    tbl  0.07     0        0 sakila.payment 
    tbl  0.08     0        0 sakila.rental  
    tbl  0.03     0        0 sakila.film    
     db  0.28     0        0 sakila         
    all  0.28     0        0 -

And if you specify L<"--verbose"> twice in conjunction with L<"--chunk-size">,
then the output includes the chunks:

  CHUNK  TIME  EXIT  SKIPPED DATABASE.TABLE       
      0  0.03     0        0 sakila.payment       
      1  0.03     0        0 sakila.payment      
    tbl  0.10     0        0 sakila.payment
      0  0.01     0        1 sakila.store         
    tbl  0.02     0        1 sakila.store         
     db  0.20     0        1 sakila               
    all  0.21     0        1 -               

The output shows that C<sakila.payment> was dumped in two chunks, and
C<sakila.store> was dumped in one chunk that was skipped.

=head1 SPEED OF PARALLEL DUMPS

How much faster is it to dump in parallel?  That depends on your hardware and
data.  You may be able dump files twice as fast, or more if you have lots of
disks and CPUs.  At the time of writing, no benchmarks exist for the current
release.  User-contributed results for older versions of mk-parallel-dump showed
very good speedup depending on the hardware.  Here are two links you can use as
reference: 

=over

=item *

L<http://www.paragon-cs.com/wordpress/?p=52>

=item *

L<http://mituzas.lt/2009/02/03/mydumper/>

=back

=head1 OPTIONS

L<"--lock-tables"> and L<"--[no]flush-lock"> are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --base-dir

type: string

The base directory in which files will be stored.

The default is the current working directory.  Each database gets its own
directory under the base directory.  So if the base directory is C</tmp>
and database C<foo> is dumped, then the directory C</tmp/foo> is created which
contains all the table dump files for C<foo>.

=item --[no]biggest-first

default: yes

Process tables in descending order of size (biggest to smallest).

This strategy gives better parallelization.  Suppose there are 8 threads and
the last table is huge.  We will finish everything else and then be running
single-threaded while that one finishes.  If that one runs first, then we will
have the max number of threads running at a time for as long as possible.

=item --[no]bin-log-position

default: yes

Dump the master/slave position.

Dump binary log positions from both C<SHOW MASTER STATUS> and C<SHOW SLAVE
STATUS>, whichever can be retrieved from the server.  The data is dumped to a
file named F<00_master_data.sql> in the C<"--base-dir">.

The file also contains details of each table dumped, including the WHERE clauses
used to dump it in chunks.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
binmode on STDOUT without the utf8 layer, and runs SET NAMES after
connecting to MySQL.

=item --chunk-size

type: string

Number of rows or data size to dump per file.

Specifies that the table should be dumped in segments of approximately the size
given.  The syntax is either a plain integer, which is interpreted as a number
of rows per chunk, or an integer with a suffix of G, M, or k, which is
interpreted as the size of the data to be dumped in each chunk.  See L<"CHUNKS">
for more details.

=item --client-side-buffering

Fetch and buffer results in memory on client.

By default this option is not enabled because it causes data to be completely
fetched from the server then buffered in-memory on the client.  For large dumps
this can require a lot of memory

Instead, the default (when this option is not specified) is to fetch and dump
rows one-by-one from the server.  This requires a lot less memory on the client
but can keep the tables on the server locked longer.

Use this option only if you're sure that the data being dumped is relatively
small and the client has sufficient memory.  Remember that, if this option is
specified, all L<"--threads"> will buffer their results in-memory, so memory
consumption can increase by a factor of N L<"--threads">.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --csv

Do L<"--tab"> dump in CSV format (implies L<"--tab">).

Changes L<"--tab"> options so the dump file is in comma-separated values
(CSV) format.  The SELECT INTO OUTFILE statement looks like the following, and
can be re-loaded with the same options:

   SELECT * INTO OUTFILE %D.%N.%6C.txt
   FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
   LINES TERMINATED BY '\n' FROM %D.%N;

=item --databases

short form: -d; type: hash

Dump only this comma-separated list of databases.

=item --databases-regex

type: string

Dump only databases whose names match this Perl regex.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --dry-run

Print commands instead of executing them.

=item --engines

short form: -e; type: hash

Dump only tables that use this comma-separated list of storage engines.

=item --[no]flush-lock

Use C<FLUSH TABLES WITH READ LOCK>.

This is enabled by default.  The lock is taken once, at the beginning of the
whole process and is released after all tables have been dumped.  If you want
to lock only the tables you're dumping, use L<"--lock-tables">.  

=item --flush-log

Execute C<FLUSH LOGS> when getting binlog positions.

This option is NOT enabled by default because it causes the MySQL server to
rotate its error log, potentially overwriting error messages.

=item --[no]gzip

default: yes

Compress (gzip) SQL dump files; does not work with L<"--tab">.

The IO::Compress::Gzip Perl module is used to compress SQL dump files
as they are written to disk.  The resulting dump files have a C<.gz>
extension, like C<table.000000.sql.gz>.  They can be uncompressed with
L<gzip>.  L<mk-parallel-restore> will automatically uncompress them, too,
when restoring.

This option does not work with L<"--tab"> because the MySQL server
writes the tab dump files directly using C<SELECT INTO OUTFILE>.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore-databases

type: Hash

Ignore this comma-separated list of databases.

=item --ignore-databases-regex

type: string

Ignore databases whose names match this Perl regex.

=item --ignore-engines

type: Hash; default: FEDERATED,MRG_MyISAM

Do not dump tables that use this comma-separated list of storage engines.

The schema file will be dumped as usual.  This prevents dumping data for
Federated tables and Merge tables.

=item --ignore-tables

type: Hash

Ignore this comma-separated list of table names.

Table names may be qualified with the database name.

=item --ignore-tables-regex

type: string

Ignore tables whose names match the Perl regex.

=item --lock-tables

Use C<LOCK TABLES> (disables L<"--[no]flush-lock">).

Disables L<"--[no]flush-lock"> (unless it was explicitly set) and locks tables
with C<LOCK TABLES READ>.  The lock is taken and released for every table as
it is dumped.

=item --lossless-floats

Dump float types with extra precision for lossless restore (requires L<"--tab">).

Wraps these types with a call to C<FORMAT()> with 17 digits of precision.
According to the comments in Google's patches, this will give lossless dumping
and reloading in most cases.  (I shamelessly stole this technique from them.  I
don't know enough about floating-point math to have an opinion).

This works only with L<"--tab">.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file.  The file contains the process ID of the script.
The PID file is removed when the script exits.  Before starting, the script
checks if the PID file already exists.  If it does not, then the script creates
and writes its own PID to it.  If it does, then the script checks the following:
if the file contains a PID and a process is running with that PID, then
the script dies; or, if there is no process running with that PID, then the
script overwrites the file with its own PID and starts; else, if the file
contains no PID, then the script dies.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --progress

Display progress reports.

Progress is displayed each time a table or chunk of a table finishes dumping.
Progress is calculated by measuring the average data size of each full chunk
and assuming all bytes are created equal.  The output is the completed and
total bytes, the percent completed, estimated time remaining, and estimated
completion time.  For example:

  40.72k/112.00k  36.36% ETA 00:00 (2009-10-27T19:17:53)

If L<"--chunk-size"> is not specified then each table is effectively one big
chunk and the progress reports are pretty accurate.  When L<"--chunk-size">
is specified the progress reports can be skewed because of averaging.

Progress reports are inaccurate when a dump is resumed.  This is known issue
and will be fixed in a later release.

=item --quiet

short form: -q

Quiet output; disables L<"--verbose">.

=item --[no]resume

default: yes

Resume dumps.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this string
will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --stop-slave

Issue C<STOP SLAVE> on server before dumping data.

This ensures that the data is not changing during the dump.  Issues C<START
SLAVE> after the dump is complete.

If the slave is not running, throws an error and exits.  This is to prevent
possibly bad things from happening if the slave is not running because of a
problem, or because someone intentionally stopped the slave for maintenance or
some other purpose.

=item --tab

Dump tab-separated (sets L<"--umask"> 0).

Dump via C<SELECT INTO OUTFILE>, which is similar to what C<mysqldump> does with
the L<"--tab"> option, but you're not constrained to a single database at a
time.

Before you use this option, make sure you know what C<SELECT INTO OUTFILE> does!
I recommend using it only if you're running mk-parallel-dump on the same
machine as the MySQL server, but there is no protection if you don't.

This option sets L<"--umask"> to zero so auto-created directories are writable
by the MySQL server.

=item --tables

short form: -t; type: hash

Dump only this comma-separated list of table names.

Table names may be qualified with the database name.

=item --tables-regex

type: string

Dump only tables whose names match this Perl regex.

=item --threads

type: int; default: 2

Number of threads to dump concurrently.

Specifies the number of parallel processes to run.  The default is 2 (this is
mk-parallel-dump, after all -- 1 is not parallel).  On GNU/Linux machines,
the default is the number of times 'processor' appears in F</proc/cpuinfo>.  On
Windows, the default is read from the environment.  In any case, the default is
at least 2, even when there's only a single processor.

=item --[no]tz-utc

default: yes

Enable TIMESTAMP columns to be dumped and reloaded between different time zones. 
mk-parallel-dump sets its connection time zone to UTC and adds
C<SET TIME_ZONE='+00:00'> to the dump file.  Without this option, TIMESTAMP
columns are dumped and reloaded in the time zones local to the source and
destination servers, which can cause the values to change.  This option also
protects against changes due to daylight saving time.

This option is identical to C<mysqldump --tz-utc>.  In fact, the above text
was copied from mysqldump's man page.

=item --umask

type: string

Set the program's C<umask> to this octal value.

This is useful when you want created files and directories to be readable or
writable by other users (for example, the MySQL server itself).

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes

Be verbose; can specify multiple times.

See L<"OUTPUT">.

=item --version

Show version and exit.

=item --wait

short form: -w; type: time; default: 5m

Wait limit when the server is down.

If the MySQL server crashes during dumping, waits until the server comes back
and then continues with the rest of the tables.  C<mk-parallel-dump> will
check the server every second until this time is exhausted, at which point it
will give up and exit.

This implements Peter Zaitsev's "safe dump" request: sometimes a dump on a
server that has corrupt data will kill the server.  mk-parallel-dump will
wait for the server to restart, then keep going.  It's hard to say which table
killed the server, so no tables will be retried.  Tables that were being
concurrently dumped when the crash happened will not be retried.  No additional
locks will be taken after the server restarts; it's assumed this behavior is
useful only on a server you're not trying to dump while it's in production.

=item --[no]zero-chunk

default: yes

Add a chunk for rows with zero or zero-equivalent values.  The only has an
effect when L<"--chunk-size"> is specified.  The purpose of the zero chunk
is to capture a potentially large number of zero values that would imbalance
the size of the first chunk.  For example, if a lot of negative numbers were
inserted into an unsigned integer column causing them to be stored as zeros,
then these zero values are captured by the zero chunk instead of the first
chunk and all its non-zero values.

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

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

This program works best on GNU/Linux.  Filename quoting might not work well on
Microsoft Windows if you have spaces or funny characters in your database or
table names.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-parallel-dump>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2007-2011 Baron Schwartz.
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

=head1 SEE ALSO

See also L<mk-parallel-restore>.

=head1 AUTHOR

Baron Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.28 Distrib 7540 $Revision: 7460 $.

=cut

__END__
:endofperl
