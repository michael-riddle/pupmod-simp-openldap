# == Class: openldap::pam
#
# See pam_ldap(5) for descriptions of any variable not defined below.
#
# [*start_tls*]
# Type: Boolean
# Default: true
#   If true, use STARTTLS instead of normal SSL.
#
# [*nss_initgroups_ignoreusers*]
# Type: Array
# Default:
#    [
#      'root','bin','daemon','adm',
#      'lp','mail','operator','nobody','dbus',
#      'ntp','saslauth','postfix','sshd','puppet',
#      'stunnel','nscd','haldaemon','clamav','rpcuser','rpc',
#      'clam','nfsnobody','rpm','nslcd','avahi','gdm','rtkit','pulse',
#      'hsqldb','radvd','apache','tomcat'
#    ]
#
#   If this is left empty, it will default to ALLLOCAL.
#
# [*use_auditd*]
# Type: Boolean
# Default: true
#   If true, include auditd support and audit the PAM configuration
#   file.
#
# [*use_nscd*]
# Type: Boolean
# Default: hiera('use_nscd',true)
#   If true, use NSCD for caching instead of SSSD.
#
# [*use_sssd*]
# Type: Boolean
# Default: hiera('use_sssd',true)
#   If true, use SSSD for caching instead of NSCD.
#   Overrides $use_nscd.
#
# == Hiera Variables
#
# [*ldap::base_dn*]
#   The LDAP Base DN
#
# [*ldap::bind_dn*]
#   The Bind DN for LDAP for client authentication.
#
# [*ldap::uri*]
#   The URI array for the LDAP servers.
#
# [*ldap::bind_pw*]
#   The password used for binding to the LDAP servers.
#
# [*openssl::cipher_suite*]
#   An Array of OpenSSL ciphers allowed to be used on the system.
#
#   Regarding POODLE - CVE-2014-3566
#   OpenLDAP cannot handle TLSv1.2 but you can't set the protocol in
#   nslcd. The default negotiation will be TLSv1 as verified through
#   observation.
#
# == Authors
#
#   * Trevor Vaughan <tvaughan@onyxpoint.com>
#
class openldap::pam (
  $base = hiera('ldap::base_dn'),
  $binddn = hiera('ldap::bind_dn'),
  $uri = hiera('ldap::uri'),
  $ldap_version = '3',
  $version = '3',
  $bindpw = hiera('ldap::bind_pw',''),
  $host = [],
  $port = '389',
  $lscope = 'sub',
  $deref = 'never',
  $timelimit = '120',
  $timeout = '120',
  $bind_timelimit = '5',
  $network_timeout = '5',
  $bind_policy = 'hard',
  $referrals = true,
  $restart = true,
  $idle_timelimit = '3600',
  $logdir = '',
  $debug = '',
  $pam_login_attribute = 'uid',
  $pam_filter = 'objectclass=posixAccount',
  $pam_lookup_policy = false,
  $pam_check_host_attr = false,
  $pam_check_service_attr = false,
  $pam_groupdn = '',
  $pam_nsrole = '',
  $pam_min_uid = '500',
  $pam_max_uid = '1000000',
  $pam_template_login_attribute = '',
  $pam_template_login = '',
  $pam_password_prohibit_message = '',
  $pam_sasl_mech = '',
  $pam_member_attribute = 'memberUid',
  $pam_password = 'exop',
  $ssl = true,
  $sslpath = '',
  $start_tls = true,
  $tls_checkpeer = true,
  $tls_cacertfile = '/etc/pki/cacerts/cacerts.pem',
  $tls_cacertdir = '/etc/pki/cacerts',
  $tls_ciphers = hiera('openssl::cipher_suite',[
    'HIGH',
    '-SSLv2'
  ]),
  $tls_cert = "/etc/pki/public/${::fqdn}.pub",
  $tls_key = "/etc/pki/private/${::fqdn}.pem",
  $tls_randfile = false,
  $threads = 5,
  $rootpwmoddn = '',
  $reconnect_sleeptime = '1',
  $reconnect_retrytime = '10',
  $tls_reqcert = 'try',
  $pagesize = '0',
  $validnames = '/^[a-z0-9._@$()][a-z0-9._@$() \~-]+[a-z0-9._@$()~-]$/i',
  $pam_authz_search = '',
  $nss_initgroups_ignoreusers = [
    'root','bin','daemon','adm',
    'lp','mail','operator','nobody','dbus',
    'ntp','saslauth','postfix','sshd','puppet',
    'stunnel','nscd','haldaemon','clamav','rpcuser','rpc',
    'clam','nfsnobody','rpm','nslcd','avahi','gdm','rtkit','pulse',
    'hsqldb','radvd','apache','tomcat'
  ],
  $use_auditd = true,
  $use_nscd = hiera('use_nscd',true),
  $use_sssd = hiera('use_sssd',false)
) {

  $ldap_conf = '/etc/pam_ldap.conf'

  if $use_auditd {
    include '::auditd'

    auditd::add_rules { 'ldap.conf':
      content => "-w ${ldap_conf} -p a -k CFG_etc_ldap",
      require => File[$ldap_conf]
    }
  }

  if $ssl {
    include '::pki'

    Class['pki'] -> File[$ldap_conf]
  }

  # Complete hackery to account for legacy upgrades.
  if $use_sssd {
    include 'sssd'

    # This should be removed when SSSD can handle shadow password changes in
    # LDAP.
    file { $ldap_conf:
      owner    => 'root',
      group    => 'root',
      mode     => '0644',
      content  => template("openldap/${ldap_conf}.erb")
    }
  }
  else {
    if $use_nscd {
      include 'nscd'
      file { $ldap_conf:
        owner    => 'root',
        group    => 'root',
        mode     => '0644',
        content  => template("openldap/${ldap_conf}.erb"),
        notify   => Service['nscd']
      }
    }
    else {
      file { $ldap_conf:
        owner    => 'root',
        group    => 'root',
        mode     => '0644',
        content  => template("openldap/${ldap_conf}.erb")
      }
    }

    if ( $::operatingsystem in ['RedHat','CentOS'] ) and (versioncmp($::lsbmajdistrelease,'6') > 0) {
      if $::selinux_current_mode and $::selinux_current_mode != 'disabled' {
        selboolean { 'authlogin_nsswitch_use_ldap':
          persistent => true,
          value      => 'on'
        }
      }
    }

    file { '/etc/nslcd.conf':
      ensure   => 'file',
      owner    => 'root',
      group    => 'root',
      mode     => '0600',
      content  => template('openldap/etc/nslcd.conf.erb'),
      notify   => Service['nslcd'],
      require  => [
        Package['nss-pam-ldapd'],
        File[$ldap_conf]
      ]
    }

    service { 'nslcd':
      ensure     => 'running',
      enable     => true,
      hasstatus  => true,
      hasrestart => true,
      subscribe  => $ssl ? {
        false   => Package['nss-pam-ldapd'],
        default => [
          Package['nss-pam-ldapd'],
          File[$tls_cacertdir],
          File[$tls_cert],
          File[$tls_key]
        ]
      }
    }
  }

  package { "openldap-clients.${::hardwaremodel}": ensure => 'latest' }
  package { 'nss-pam-ldapd':                       ensure => 'latest' }
  package { 'ruby-ldap':                           ensure => 'latest' }

  validate_string($base)
  validate_string($binddn)
  if !empty($ldap_version) {
    if !empty($version) and ($version != $ldap_version) {
      fail('ldap_version and version both set but do not match. These values must be the same.')
    }
    validate_integer($ldap_version)
  }
  if !empty($version) {
    if !empty($ldap_version) and ($version != $ldap_version) {
      fail('ldap_version and version both set but do not match. These values must be the same.')
    }
    validate_integer($version)
  }
  validate_integer($port)
  validate_array_member($lscope,['sub','one','base'])
  validate_array_member($bind_policy,['hard', 'soft'])
  validate_array_member($deref,['never','searching','finding','always'])
  if !empty($timelimit) {
    if !empty($timeout) and ($timeout != $timelimit) {
      fail('timelimit and timeout both set but do not match. These values must be the same.')
    }
    validate_integer($timelimit)
  }
  if !empty($timeout) {
    if !empty($timelimit) and ($timeout != $timelimit) {
      fail('timelimit and timeout both set but do not match. These values must be the same.')
    }
    validate_integer($timeout)
  }
  if !empty($bind_timelimit) {
    if !empty($network_timeout) and ($network_timeout != $bind_timelimit) {
      fail('bind_timelimit and network_timeout both set but do not match. These values must be the same.')
    }
    validate_integer($bind_timelimit)
  }
  if !empty($network_timeout) {
    if !empty($bind_timelimit) and ($network_timeout != $bind_timelimit) {
      fail('bind_timelimit and network_timeout both set but do not match. These values must be the same.')
    }
    validate_integer($network_timeout)
  }
  validate_bool($referrals)
  validate_bool($restart)
  validate_integer($idle_timelimit)
  validate_bool($pam_lookup_policy)
  validate_bool($pam_check_host_attr)
  validate_bool($pam_check_service_attr)
  validate_integer($pam_min_uid)
  validate_integer($pam_max_uid)
  validate_array_member($pam_password,[
    'clear',
    'clear_remove_old',
    'crypt',
    'nds',
    'racf',
    'ad',
    'exop',
    'exop_send_old'
  ])
  validate_bool($ssl)
  validate_bool($start_tls)
  validate_bool($tls_checkpeer)
  validate_absolute_path($tls_cacertfile)
  validate_absolute_path($tls_cacertdir)
  validate_array($tls_ciphers)
  validate_absolute_path($tls_cert)
  validate_absolute_path($tls_key)
  validate_bool($tls_randfile)
  validate_integer($threads)
}
