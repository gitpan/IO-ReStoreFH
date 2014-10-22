# --8<--8<--8<--8<--
#
# Copyright (C) 2012 Smithsonian Astrophysical Observatory
#
# This file is part of IO::ReStoreFH
#
# IO::ReStoreFH is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# -->8-->8-->8-->8--

package IO::ReStoreFH;

use 5.10.0;

use strict;
use warnings;

use version 0.77; our $VERSION = qv( "v0.02_05" );

use FileHandle::Fmode ':all';

use POSIX qw[ dup dup2 ceil floor ];
use Symbol;
use Carp;

use IO::Handle;
use Scalar::Util qw[ looks_like_number ];
use Try::Tiny;


sub new {

    my $class = shift;

    my $obj = bless { dups => [] }, $class;

    for my $fh ( @_ ) {

        $obj->store( 'ARRAY' eq ref $fh ? @{$fh} : $fh );
    }

    return $obj;

}

# store (dup) a filehandle or file descriptors

# use Perl's open to dup filehandles; POSIX dup to handle fd's

sub store {

    my ( $self, $fh, $mode ) = @_;

    # may be passed glob or ref to glob
    if ( ref( $fh ) || 'GLOB' eq ref( \$fh ) ) {

        # gimme a glob...
        my $glob
          = 'GLOB' eq ref( $fh )  ? ${$fh}
          : 'GLOB' eq ref( \$fh ) ? $fh
          :                         undef;

        # open on Perl 5.10.x seems to return FileHandle objects,
        # and that requires loading the package before it can
        # find its fileno method.  weird.
        require FileHandle
          if defined $glob && *{$glob}{IO}->isa( 'FileHandle' );

        my $fd = eval { $fh->fileno };

        croak( "\$fh object does not have a fileno method:$@ \n" )
          if $@;

        croak( "\$fh is not open\n" )
          unless defined $fd;

        # get access mode; open documentation says mode must
        # match that of original filehandle; do the best we can
        if ( !defined $mode ) {

            my $rfh = 'GLOB' eq ref( \$fh ) ? \$fh : $fh;

            $mode
              = is_RO( $rfh ) ? '<'
              : is_WO( $rfh ) ? '>'
              : is_W( $rfh ) && is_R( $rfh ) ? '+<'
              :                                undef;

            $mode .= '>' if is_A( $fh );

        }

        # give up
        croak(
            "unable to determine mode for $fh; please pass it as an argument\n"
        ) if !defined $mode;


        # dup the filehandle
        open my $dup, $mode . '&', $fh
          or croak( "error fdopening $fh: $!\n" );

        push @{ $self->{dups} }, { fh => $fh, mode => $mode, dup => $dup };

    }

    elsif ( looks_like_number( $fh ) && ceil( $fh ) == floor( $fh ) ) {

        # as the caller specifically used an fd, don't go through Perl's
        # IO system
        my $dup = dup( $fh )
          or croak( "error dup'ing file descriptor $fh: $!\n" );

        push @{ $self->{dups} }, { fd => $fh, dup => $dup };
    }

    else {

        croak(
            "\$fh must be opened Perl filehandle or object or integer file descriptor\n"
          )

    }

    return;
}

sub restore {

    my $self = shift;

    my $dups = $self->{dups};
    ## no critic (ProhibitAccessOfPrivateData)
    while ( my $dup = pop @{$dups} ) {

        if ( exists $dup->{fd} ) {

            dup2( $dup->{dup}, $dup->{fd} )
              or croak( "error restoring file descriptor $dup->{fd}: $!\n" );

            POSIX::close( $dup->{dup} );

        }

        else {

            open( $dup->{fh}, $dup->{mode} . '&', $dup->{dup} )
              or croak( "error restoring file handle $dup->{fh}: $!\n" );

            close( $dup->{dup} );

        }

    }

    return;
}



sub DESTROY {

    my $self = shift;

    try {
        $self->restore;
    }
    catch { croak $_ };

    return;
}

__END__

=head1 NAME

IO::ReStoreFH - store/restore file handles


=head1 SYNOPSIS

    use IO::ReStoreFH;

    {
       my $fhstore = IO::ReStoreFH->new( *STDOUT );

       open( STDOUT, '>', 'file' );
    } # STDOUT will be restored when $fhstore is destroyed

    # or, one at-a-time
    {
       my $fhstore = IO::ReStoreFH->new;
       $store->store( *STDOUT );
       $store->store( $myfh );

       open( STDOUT, '>', 'file' );
       open( $myfh, '>', 'another file' );
    } # STDOUT and $myfh will be restored when $fhstore is destroyed



=head1 DESCRIPTION

Redirecting and restoring I/O streams is straightforward but a chore,
and can lead to strangely silent errors if you forget to restore
STDOUT or STDERR.

B<IO::ReStoreFH> helps keep track of the present state of filehandles and
low-level file descriptors and restores them either explicitly or when
the B<IO::ReStoreFH> object goes out of scope.  It B<only> works with
filehandles for which B<fileno()> returns a defined value.

It uses the standard Perl filehandle duplication methods (via B<open>)
for filehandles, and uses B<POSIX::dup> and B<POSIX::dup2> for file
descriptors.

File handles and descriptors are restored in the reverse order that
they are stored.

=head1 INTERFACE

=over

=item new

    my $fhstore = IO::ReStoreFH->new;
    my $fhstore = IO::ReStoreFH->new( $fh1, [ $fh2, $mode ], $fd, ... );

Create a new object.  Optionally pass a list of Perl filehandles,
integer file descriptors, or filehandle - B<open()> file mode pairs.
The latter is typically only necessary if B<fcntl()> does not return
access mode flags for filehandles.

The passed handles and descriptors will be duplicated to be restored
when the object is destroyed or the B<restore> method is called.

=item store

    $fhstore->store( $fh );
    $fhstore->store( $fh, $mode );

    $fhstore->store( $fd );

The passed handles and descriptors will be duplicated to be restored
when the object is destroyed or the B<restore> method is called.
C<$mode> is optional; and only necessary if the platform's B<fcntl>
does not provide access mode flags.


=item restore

   $fhstore->restore;

Restore the stored file handles and descriptors, in the reverse order
that they were stored.  This is automatically called when the object
is destroyed.

=back



=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< $fh object does not have a fileno method >>

Objects passed to B<IO::ReStoreFH> must provide a fileno method.  They
really need to be file handles.

=item C<< $fh is not open >>

The passed file handle was not attached to a file descriptor.

=item C<< unable to determine mode for %s; please pass it as an argument >>

B<IO::ReStoreFH> was unable to get the access mode for the passed file handle
using B<fcntl> or a match against file descriptors 0, 1, or 2.  You
will need to explicitly provide the Perl access mode used to create
the file handle.

=item C<< error fdopening %s: %s >>

Perl B<open()> was unable to duplicate the passed filehandle for the
specified reason.

=item C<< error dup'ing file descriptor %s: %s >>

B<POSIX::dup()> was unable to duplicate the passed file descriptor for the
specified reason.

=item C<< $fh must be opened Perl filehandle or object or integer file descriptor >>

The passed C<fh> argument wasn't recognized as a Perl filehandle or a
file descriptor.  Please try again.

=item C<< error restoring file descriptor %d: %s >>

Attempting to restore the file descriptor failed for the specified reason.

=item C<< error restoring file handle %s: %s >>

Attempting to restore the Perl file handle failed for the specified reason.

=back


=head1 CONFIGURATION AND ENVIRONMENT

IO::ReStoreFH requires no configuration files or environment variables.


=head1 DEPENDENCIES

Try::Tiny.

=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.  This code has been tested on Linux and Mac OS X.

Please report any bugs or feature requests to
C<bug-io-redir@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/Public/Dist/Display.html?Name=IO-ReStoreFH>.


=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012 The Smithsonian Astrophysical Observatory

IO::ReStoreFH is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 AUTHOR

Diab Jerius  E<lt>djerius@cpan.orgE<gt>


