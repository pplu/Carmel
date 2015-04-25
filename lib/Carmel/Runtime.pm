package Carmel::Runtime;
use strict;

my $environment = {};
sub environment {
    $environment = $_[1] if $_[1];
    $environment;
}

sub bootstrap_env {
    my $class = shift;

    if ($environment->{local}) {
        return (
            PATH => ["$environment->{local}/bin"],
            PERL5OPT => ["-MCarmel::Setup"],
            PERL_CARMEL_PATH => $environment->{base},
        );
    } else {
        return (
            PATH => $environment->{path},
            PERL5OPT => ["-MCarmel::Setup"],
            PERL_CARMEL_PATH => $environment->{base},
        );
    }
}

sub _insert_before_sitelib {
    my($inc) = @_;

    require Config;
    my %lib = map { $_ => 1 } @Config::Config{qw(sitearchexp archlibexp)};

    my $index;
    for my $i (0..$#INC) {
        $index = $i, last if $lib{$INC[$i]};
    }

    if ($index) {
        splice @INC, $index, 0, $inc;
    } else {
        warn "Can't find \@INC entry for $Config::Config{sitearchexp}";
    }
}

sub bootstrap {
    my $class = shift;

    _insert_before_sitelib(Carmel::Runtime::Guard->new);
    unshift @INC,
      Carmel::Runtime::FastINC->new(%{$environment->{modules}}),
      @{$environment->{inc}};
}

sub require_all {
    my($class, @phase) = @_;

    require Module::Runtime;
    my $modules = $class->required_modules(@phase);
    while (my($module, $version) = each %$modules) {
        next if $module eq 'perl';
        Module::Runtime::use_module($module, $version);
    }

    1;
}

sub required_modules {
    my($class, @phase) = @_;

    my %modules;
    for my $phase ('runtime', @phase) {
        %modules = (%modules, %{$environment->{prereqs}{$phase}{requires} || {}});
    }

    \%modules
}

package Carmel::Runtime::FastINC;

sub new {
    my($class, %modules) = @_;
    bless \%modules, $class;
}

sub Carmel::Runtime::FastINC::INC {
    my($self, $file) = @_;

    if ($self->{$file}) {
        open my $fh, '<', $self->{$file}
          or die "Could not load $self->{$file}: $!";
        $INC{$file} = $self->{$file};
        return $fh;
    }
}

package Carmel::Runtime::Guard;

# called in runtime via ->require_all
my %whitelist = (
    'Module/Runtime.pm' => 1,
);

sub new {
    my $class = shift;
    require Module::CoreList;
    bless { corelist => {} }, $class;
}

sub _package {
    my $file = shift;
    $file =~ s/\.pm$//;
    $file =~ s!/!::!g;
    $file;
}

sub Carmel::Runtime::Guard::INC {
    my($self, $file) = @_;

    # Config_heavy.pl etc.
    return if $file =~ /\.pl$/;

    # whitelist
    return if $whitelist{$file};

    my $mod = _package($file);
    my @caller = caller 0;

    # eval { require Module }
    return if $caller[3] =~ /^\(eval/ or defined $caller[6];

    # core module calling another module is considered core, too.
    # FIXME: Updated core module might call a non-core package
    if ($self->{corelist}{$caller[0]}) {
        $self->{corelist}{$mod} = 1;
        return;
    }

    # core module
    if ($Module::CoreList::version{$]+0}{$mod}) {
        $self->{corelist}{$mod} = 1;
        return;
    }

    # Module::Runtime::use_package_optimistically tries to parse this message.
    die "Can't locate $file in \@INC (You may need to add `requires '$mod';` to your cpanfile and run carmel install) (\@INC contains: @INC) at $caller[1] line $caller[2].\n";
}

1;
