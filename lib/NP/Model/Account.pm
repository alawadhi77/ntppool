package NP::Model::Account;
use strict;
use NP::Util qw();
use Crypt::Skip32::Base32Crockford ();
use Combust::Config ();

sub BAD_SERVER_THRESHOLD {-15}

my $config  = Combust::Config->new;

my $account_id_key = $config->site->{ntppool}->{account_id_key} or die "'account_id_key' not set";
$account_id_key    = pack( 'H20', uc $account_id_key);
my $cipher = Crypt::Skip32::Base32Crockford->new($account_id_key);

sub token_id {
    shift;
    my $token = shift or die "no token specified";
    return $cipher->decrypt_number_b32_crockford($token);
}

sub id_token {
    my $self = shift;
    return lc $cipher->encrypt_number_b32_crockford($self->id);
}

sub validate {
    my $account = shift;
    my $errors = {};
    for my $f (qw(name)) {
        $errors->{$f} = 'Required field' unless $account->$f and $account->$f =~ m/\S/;
    }

    $account->{_validation_errors} = $errors;

    %$errors ? 0 : 1;
}

sub validation_errors {
    my $self = shift;
    $self->{_validation_errors} || {};
}

sub can_edit {
    my ($self, $user) = @_;
    return 0 unless $user;
    return 1 if $user->privileges->vendor_admin;
    return 1 if map { $_->id == $user->id } $self->users;
    return 0;
}

sub can_view {
    return shift->can_edit(shift);
}

sub bad_servers {
    my $s = [grep { $_->score < BAD_SERVER_THRESHOLD } shift->servers];
    wantarray ? @$s : $s;
}

sub servers {
    my $self = shift;

    #local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;
    my $s = NP::Model->server->get_servers(
        query => [
            account_id => $self->id,
            or      => [
                deletion_on => undef,                       # not deleted
                deletion_on => {'gt' => DateTime->today}    # deleted in the future
            ],
        ],
    );
    $s = [
        sort {
            my $r = 0;
            my $ia = Net::IP->new($a->ip);
            my $ib = Net::IP->new($b->ip);

            if (my $c = $ia->version <=> $ib->version) {
                return $c;
            }

            if ($ia->bincomp('lt', $ib)) {
                $r = -1;
            }
            elsif ($ia->bincomp('gt', $ib)) {
                $r = 1;
            }
            $r;
        } @$s
    ];
    wantarray ? @$s : $s;
}


1;
