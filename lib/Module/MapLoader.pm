package Module::MapLoader;
use strict;
use warnings;

our $VERSION = '0.001000';
$VERSION =~ tr/_//d;

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

  my @mappings;
  if ($opts{files}) {
    push @mappings, $opts{files};
  }
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
      push @mappings, $mapping;
    }
  }
  if (my $dirs = $opts{path}) {
    $dirs = [ $dirs ]
      if !ref $dirs;
    my $mapping = _find(@$dirs);
    push @mappings, $mapping;
  }

  my %files;
  @files{keys %$_} = values %$_
    for @mappings;

  return bless {
    files => \%files,
  }, $class;
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
__END__

=head1 NAME

Module::MapLoader - Load modules from predefined mapping

=head1 SYNOPSIS

  use Module::MapLoader;

=head1 DESCRIPTION

Creates an L<perlvar/@INC> hook which will load modules from a predefined
mapping, rather than searching directories.

=head1 AUTHOR

haarg - Graham Knop (cpan:HAARG) <haarg@haarg.org>

=head1 CONTRIBUTORS

None so far.

=head1 COPYRIGHT

Copyright (c) 2022 the Module::MapLoader L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself. See L<https://dev.perl.org/licenses/>.

=cut
