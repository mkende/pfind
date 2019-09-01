package App::Pfind;

use 5.022;
use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray :config auto_abbrev no_ignore_case
                    permute auto_version);
use Pod::Usage;
use File::Find;
use Safe;

our $VERSION = '1.00';

$Data::Dumper::Terse = 1;  # Don't output variable names.
$Data::Dumper::Sortkeys = 1;  # Sort the content of the hash variables.
$Data::Dumper::Useqq = 1;  # Use double quote for string (better escaping).

# A Safe object, created in reset_options.
my $safe;

# This hash contains options that are global for the whole program.
my %options;

sub reset_options {
  $safe = Safe->new();
  $safe->deny_only(':subprocess', ':ownprocess', ':others', ':dangerous');
  $safe->reval('use File::Spec::Functions qw(:ALL);');
  $safe->share_from('File::Find', ['dir', 'name']);

  # Whether to process the content of a directory before the directory itself.
  $options{depth_first} = 0;
  # Whether to follow the symlinks.
  $options{follow} = 0;
  # Whether to follow the symlinks using a fast method that may process some files twice.
  $options{follow_fast} = 0;
  # Block of code to execute before the main loop
  $options{begin} = [];
  # Block of code to execute after the main loop
  $options{end} = [];
  # Block of code to execute for each file and directory encountered
  $options{exec} = [];
  # Whether to chdir in the crawled directories
  $options{chdir} = 1;
  # Whether to catch errors returned in $! in user code
  $options{catch_errors} = 1;  # non-modifiable for now.
  # Add this string after each print statement
  $options{print} = "\n";
}

sub all_options {(
  'help|h' => sub { pod2usage(-exitval => 0, -verbose => 2) },
  'depth-first|depth|d!' => \$options{depth_first},
  'follow|f!' => \$options{follow},
  'follow-fast|ff!' => \$options{follow_fast},
  'chdir!' => \$options{chdir},
  'print|p=s' => \$options{print},
  'begin|BEGIN|B=s@' => $options{begin},
  'end|END|E=s@' => $options{end},
  'exec|e=s@' => $options{exec}
)}

sub eval_code {
  my ($code, $flag) = @_;
  my $r = $safe->reval($code);
  if ($@) {
    die "Compilation failure in code given to --${flag}: ${@}\n";
  } elsif ($! && $options{catch_errors}) {
    die "Execution failure in code given to --${flag}: $!\n";
  }
  return $r;
}

sub Run {
  my ($argv) = @_;
  
  reset_options();
  # After the GetOptions call this will contain the input directories.
  my @inputs = @$argv;
  GetOptionsFromArray(\@inputs, all_options())
    or pod2usage(-exitval => 2, -verbose => 0);
    
  if (not @{$options{exec}}) {
    $options{exec} = ['print'];
  }
    
  if ($options{follow} && $options{follow_fast}) {
    die "The --follow and --follow-fast options cannot be used together.\n";
  }
  
  $\ = $options{print};
  
  for my $c (@{$options{begin}}) {
    eval_code($c, 'BEGIN');
  }
  
  # We're building a sub that will execute each given piece of code in a block.
  # That way we can evaluate this code in the safe once and get the sub
  # reference (so that it does not need to be recompiled for each file). In
  # addition, control flow keywords (mainly next, redo and return) can be used
  # in each block.
  my $block_start = '{ my $tmp_default = $_; local $_ = $tmp_default; ';
  my $block_end = $options{catch_errors} ? '} die "$!\n" if $!;' : '';
  my $all_exec_code = "sub { ${block_start}".join("${block_end} \n ${block_start}", @{$options{exec}})."${block_end} }";
  print $all_exec_code."\n";
  my $wrapped_code = eval_code($all_exec_code, 'exec');
  
  find({
    bydepth => $options{depth_first},
    follow => $options{follow},
    follow_fast => $options{follow_fast},
    no_chdir => !$options{chdir},
    wanted => $wrapped_code,
  }, @inputs);

  for my $c (@{$options{end}}) {
    eval_code($c, 'BEGIN');
  }
}

1;
