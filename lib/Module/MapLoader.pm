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

sub _find_files {
  my @libs = @_;
  my %files;

  for my $lib (@libs) {
    my %lib = ref $lib ? %$lib : (
      path   => $lib,
      filter => qr{\.p[lm]\z},
    );
    my $root = $lib{path};
    my $filter = $lib{filter};

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
          next;
        }
        next
          if $filter && $path !~ $filter;

        $files{substr $path, length $root} = $path;
      }
    }
  }

  return \%files;
}

sub _read_pl {
  my (@mapfiles) = @_;
  my %mapping;

  for my $mapfile (@mapfiles) {
    my $mapping;
    my $e;
    {
      local $@;
      $mapping = do $mapfile or $e = $@ || $!;
    }
    die $e
      if defined $e;
    @mapping{keys %$mapping} = values %$mapping;
  }

  return \%mapping;
}

sub _read_tsv {
  my (@mapfiles) = @_;
  my %mapping;

  for my $mapfile (@mapfiles) {
    open my $fh, '<', $mapfile
      or die "can't read $mapfile: $!";
    while (my $line = <$fh>) {
      $line =~ s/\r?\n\z//;
      my ($module, $path) = split /\t/, $line, 2;
      die "No path given for $module in $mapfile!"
        if !defined $path;
      $mapping{$module} = $path;
    }
  }

  return \%mapping;
}

sub new {
  my $class = shift;
  my %opts = @_;

  my @mappings;
  if ($opts{files}) {
    push @mappings, $opts{files};
  }
  if (my $mapfiles = $opts{mapfile_pl}) {
    $mapfiles = [ $mapfiles ]
      if !ref $mapfiles;
    push @mappings, _read_pl(reverse @$mapfiles);
  }
  if (my $mapfiles = $opts{mapfile_tsv}) {
    $mapfiles = [ $mapfiles ]
      if !ref $mapfiles;
    push @mappings, _read_tsv(reverse @$mapfiles);
  }
  if (my $dirs = $opts{lib_dir}) {
    $dirs = [ $dirs ]
      if ref $dirs ne 'ARRAY';
    push @mappings, _find_files(reverse @$dirs);
  }
  if (my $dirs = $opts{blib_dir}) {
    $dirs = [ $dirs ]
      if ref $dirs ne 'ARRAY';
    push @mappings, _find_files(map +("$_/lib", "$_/arch"), reverse @$dirs);
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

  open my $fh, '<:', $fullpath
    or die "$!";

  # %INC entry will initially be an alias to the @INC entry, so we need to
  # delete it before setting the correct value.

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

  use Module::MapLoader files => { "My/Module.pm" => "/my_project/lib/My/Module.pm" };

  my $hook = Module::MapLoader->new(
    files => {
      "My/Module.pm" => "/my_project/lib/My/Module.pm",
    },
    mapfile_pl => [
      '/my_project/mappingfile.pl',
    ],
    mapfile_tsv => [
      '/my_project/mappingfile.tsv',
    ],
    lib_dir => [
      '/my_project/lib',
    ],
  );

  unshift @INC, $hook;

=head1 DESCRIPTION

Creates an L<@INC|perlvar/@INC> hook which will load modules from a predefined
mapping, rather than searching directories.

=head1 METHODS

=head2 import

If any parameters are passed to import, a new hook object is created using
those parameters, and the hook is added to the beginning of
L<@INC|perlvar/@INC>.

=head2 new

Creates a new hook object.

=head3 Options

=over 4

=item files

A hashref of loadable file names to full paths. The file name should be a module
fragment as would be passed to L<perlfunc/require>, like C<Module/MapLoader.pm>,
not a module name, like C<Module::MapLoader>.

=item mapfile_pl

A mapping file, or an array reference of mapping files, of perl code returning
a hash reference of loadable files to full paths.

=item mapfile_tsv

A mapping file, or an array reference of mapping files, containing a tab
separated list of loadable files and full file paths.

=item lib_dir

A library directory or array reference of library directories, which will be
recursively searched for modules to be able to load. Library directories can
be provided as strings, or as hashrefs with the options C<path>, the directory
to search, and C<filter>, containing a regular expression to limit which files
to include in the final mapping. If not provided, the C<filter> defaults to
C</\.(pl|pm)$>.

=back

=head2 INC

When used as a hook, this method is called by perl.

=head2 files

Returns a hash reference of the mapping of files to full paths that are being
provided by the hook. This method will also be used by L<Module::Pluggable> to
see what files are available to be loaded.

=head2 FILES

An alias for files.

=head1 CAVEATS

=over 4

=item *

While this module may be able to load modules that use XS, that has not been
well tested and is not a high priority feature to support.

=back

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
