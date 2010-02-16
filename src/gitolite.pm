# this file is commonly used using "require".  It is not required to use "use"
# (because it doesn't live in a different package)

# warning: preceding para requires 4th attribute of a programmer after
# laziness, impatience, and hubris: sense of humour :-)

# WARNING
# -------
# the name of this file will change as soon as its function/feature set
# stabilises enough ;-)

# right now all it does is
# - define a function that tells you where to find the rc file
# - define a function that creates a new repo and give it our update hook

# ----------------------------------------------------------------------------
#       common definitions
# ----------------------------------------------------------------------------

$ABRT = "\n\t\t***** ABORTING *****\n       ";
$WARN = "\n\t\t***** WARNING *****\n       ";

# commands we're expecting
$R_COMMANDS=qr/^(git[ -]upload-pack|git[ -]upload-archive)$/;
$W_COMMANDS=qr/^git[ -]receive-pack$/;

# note that REPONAME_PATT allows "/", while USERNAME_PATT allows "@"
$REPONAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._/+-]*$);    # very simple pattern
$USERNAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);   # very simple pattern

# ----------------------------------------------------------------------------
#       convenience subs
# ----------------------------------------------------------------------------

sub wrap_chdir {
    chdir($_[0]) or die "$ABRT chdir $_[0] failed: $! at ", (caller)[1], " line ", (caller)[2], "\n";
}

sub wrap_open {
    open (my $fh, $_[0], $_[1]) or die "$ABRT open $_[1] failed: $! at ", (caller)[1], " line ", (caller)[2], "\n" .
            ( $_[2] || '' );    # suffix custom error message if given
    return $fh;
}

# ln -sf :-)
sub ln_sf
{
    my($srcdir, $glob, $dstdir) = @_;
    for my $hook ( glob("$srcdir/$glob") ) {
        $hook =~ s/$srcdir\///;
        unlink                   "$dstdir/$hook";
        symlink "$srcdir/$hook", "$dstdir/$hook" or die "could not symlink $hook\n";
    }
}

# ----------------------------------------------------------------------------
#       where is the rc file hiding?
# ----------------------------------------------------------------------------

sub where_is_rc
{
    # till now, the rc file was in one fixed place: .gitolite.rc in $HOME of
    # the user hosting the gitolite repos.  This was fine, because gitolite is
    # all about empowering non-root users :-)

    # then we wanted to make a debian package out of it (thank you, Rhonda!)
    # which means (a) it's going to be installed by root anyway and (b) any
    # config files have to be in /etc/<something>

    # the only way to resolve this in a backward compat way is to look for the
    # $HOME one, and if you don't find it look for the /etc one

    # this common routine does that, setting an env var for the first one it
    # finds

    return if $ENV{GL_RC};

    for my $glrc ( $ENV{HOME} . "/.gitolite.rc", "/etc/gitolite/gitolite.rc" ) {
        if (-f $glrc) {
            $ENV{GL_RC} = $glrc;
            return;
        }
    }
}

# ----------------------------------------------------------------------------
#       create a new repository
# ----------------------------------------------------------------------------

# NOTE: this sub will change your cwd; caller beware!
sub new_repo
{
    my ($repo, $hooks_dir) = @_;

    umask($REPO_UMASK);

    system("mkdir", "-p", "$repo.git") and die "$ABRT mkdir $repo.git failed: $!\n";
        # erm, note that's "and die" not "or die" as is normal in perl
    wrap_chdir("$repo.git");
    system("git --bare init >&2");
    # propagate our own, plus any local admin-defined, hooks
    ln_sf($hooks_dir, "*", "hooks");
    chmod 0755, "hooks/update";
}

# ----------------------------------------------------------------------------
#       parse the compiled acl
# ----------------------------------------------------------------------------

sub parse_acl
{
    my $GL_CONF_COMPILED = shift;
    die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

# basic means wildcards will be shown as wildcards; this is pretty much what
# got parsed by the compile script
sub report_basic
{
    my($GL_ADMINDIR, $GL_CONF_COMPILED, $user) = @_;

    &parse_acl($GL_CONF_COMPILED);

    # send back some useful info if no command was given
    print "hello $user, the gitolite version here is ";
    system("cat", "$GL_ADMINDIR/src/VERSION");
    print "\ryou have the following permissions:\n\r";
    for my $r (sort keys %repos) {
        my $perm .= ( $repos{$r}{R}{'@all'} ? '  @' : ( $repos{$r}{R}{$user} ? '  R' : '' ) );
        $perm    .= ( $repos{$r}{W}{'@all'} ? '  @' : ( $repos{$r}{W}{$user} ? '  W' : '' ) );
        print "$perm\t$r\n\r" if $perm;
    }
}

# ----------------------------------------------------------------------------
#       membership info
# ----------------------------------------------------------------------------

# given a plain reponame or username, return a list of all the groups it is a
# member of

sub get_memberships {
    my $base = shift;
    for my $g (sort keys %groups) {
        push @ret, $g if $groups{$g}{$base};
    }
    return @ret;
}

# ----------------------------------------------------------------------------
#       check access for extended user against extended repo for perm
# ----------------------------------------------------------------------------

# given a list of repos/repo groups, a list of users/user groups, and a
# "perm", check if any of the user/groups is allowed $perm access to any of
# the repo/groups

# XXX WARNING.  This mostly breaks "deny" rules, because the order is no
# longer guaranteed.  Deny rules will still work if *all* access to a repo for
# a user is in *one* "repo" stanza (the ordering *within* the sequence of "R",
# "RW", etc., rules in one "repo" stanza is preserved).  What is no longer
# preserved is the ordering between entire stanzas.

sub check_access {
    my ($xrr, $xur, $perm) = @_;
    # note that the first 2 args are listrefs

    my $found=0;
    my @allowed_refs;

    for $r (@$xrr) {
        for $u (@$xur) {
            # finding R (or W) for *any* repo/user pair is enough
            $found = 1 if ( not $found and $repos{$r}{$perm}{$u} );

            # gather level 2 permissions if 'W'riting
            push @allowed_refs, @ { $repos{$r}{$u} } if ($perm eq 'W' and $repos{$r}{$u});
        }
    }

    # personal branches come first
    unshift @allowed_refs, { "$PERSONAL/$ENV{GL_USER}/" => "RW+" }
        if $found and $PERSONAL and $perm eq 'W';

    $ENV{GL_ALLOWED_REFS} = Data::Dumper->Dump([\@allowed_refs], [qw(*allowed_refs)]);

    return $found;
}

1;
