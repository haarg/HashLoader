package Module::MapLoader;
use strict;
use warnings;

sub import {
  my $class = shift;
  if (@_) {
    unshift @INC, $class->new(@_);
  }
}

sub _find {
  my @roots = @_;
  my %files;

  for my $root (@roots) {
    $root =~ s{/?\z}{/};
    my @dirs = $root;
    while (my $dir = pop @dirs) {
      opendir my $dh, $dir or die;
      while (my $item = readdir $dh) {
        next
          if $item eq '.' || $item eq '..';
        my $path = $dir . $item;
        if (-d $path) {
          push @dirs, $path . '/';
        }
        else {
          $files{substr $path, length $root} = $path;
        }
      }
    }
  }

  return \%files;
}

sub new {
  my $class = shift;
  my %opts = @_;
  my $self = bless {
    files => $opts{files} || {},
  }, $class;
  if (my $mapfiles = $opts{mapfile}) {
    $mapfiles = [ $mapfiles ]
      if !ref $mapfiles;
    for my $mapfile (@$mapfiles) {
      my $mapping;
      my $e;
      {
        local $@;
        $mapping = do $mapfile or $e = $@ || $!;
      }
      die $e
        if defined $e;
      @{$self->{files}}{keys %$mapping} = values %$mapping;
    }
  }
  if (my $dirs = $opts{path}) {
    $dirs = [ $dirs ]
      if !ref $dirs;
    my $mapping = _find(@$dirs);
    @{$self->{files}}{keys %$mapping} = values %$mapping;
  }
  return $self;
}

sub FILES {
  my $self = shift;
  return $self->files;
}

sub files {
  my $self = shift;
  return keys %{ $self->{files} };
}

sub Module::MapLoader::INC {
  my $self = shift;
  my $file = shift;
  my $fullpath = $self->{files}{$file}
    or return;
  open my $fh, $fullpath
    or die "$!";
  my $prefix = sprintf <<'END_CODE', quotemeta($file), quotemeta($file), quotemeta($fullpath), $fullpath;
BEGIN {
  delete $INC{"%s"};
  $INC{"%s"} = "%s";
}
#line 1 "%s"
END_CODE
  return (
    \$prefix,
    $fh,
  );
}

1;
