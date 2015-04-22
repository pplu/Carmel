package Carmel::Runtime;
use Config;
use Module::CoreList;

my %environment;
sub modules { %{$environment{modules}} }
sub inc     { @{$environment{inc}} }
sub path    { @{$environment{path}} }
sub base    { $environment{base} }
sub prereqs { $environment{prereqs} }

sub environment {
    my($class, %args) = @_;
    %environment = %args;
}

sub bootstrap {
    my $class = shift;
    unshift @INC,
      Carmel::Runtime::FastINC->new($class->modules),
      $class->inc,
      Carmel::Runtime::Guard->new;
}

sub require_all {
    my($class, @phase) = @_;

    require Module::Runtime;
    my $modules = Carmel::Runtime->required_modules($phase);
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
        %modules = (%modules, %{$class->prereqs->{$phase}{requires} || {}});
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
