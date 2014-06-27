# Class: bacula::database
#
# This class enforces database resources needed by all
# bacula components
#
# This class is not to be called individually
#
class bacula::database {

  include bacula

  $real_db_password = $bacula::database_password ? {
    ''      => $bacula::real_default_password,
    default => $bacula::database_password,
  }

  $script_directory = $::operatingsystem ? {
    /(?i:Debian|Ubuntu|Mint)/ => '/usr/share/bacula-director',
    default                   => '/usr/libexec/bacula',
  }

  $db_parameters = $bacula::database_backend ? {
    'sqlite' => '',
    'mysql'  => "--host=${bacula::database_host} --user=${bacula::database_user} --password=${real_db_password} --port=${bacula::database_port} --database=${bacula::database_name}",
    default  => '',
  }

  if $bacula::manage_database {
    file_line { 'bacula_database_name':
      path => "${script_directory}/make_mysql_tables",
      line => "db_name=${bacula::database_name}",
      match => "^db_name=(${bacula::database_name}|\${db_name:-XXX_DBNAME_XXX})"
    }
    
    exec { 'create_bacula_tables':
      command     => "${script_directory}/make_mysql_tables ${db_parameters}",
      refreshonly => true,
      require     => File_Line['bacula_database_name']
    }

    case $bacula::database_backend {
      'mysql': {
        require mysql::client

        $notify_create_db = $bacula::manage_database ? {
          true    => Exec['create_bacula_tables'],
          default => undef,
        }
        
        mysql::grant { 'create_bacula_database': 
          mysql_db        => $bacula::database_name,
          mysql_user      => $bacula::database_user,
          mysql_password  => $bacula::database_password,
          mysql_create_db => true,
          mysql_host      => 'localhost',
        }
        
        mysql::grant { 'grant_bacula_user_privileges':
          mysql_db        => $bacula::database_name,
          mysql_user      => $bacula::database_user,
          mysql_password  => $bacula::database_password,
          mysql_create_db => false,
          mysql_host      => '%',
          require         => Mysql::Grant['create_bacula_database'],
          notify          => $notify_create_db,
        }
      }
      'sqlite': {
        sqlite::db { $bacula::database_name:
          ensure   => present,
          location => "/var/lib/bacula/${bacula::database_name}.db",
          owner    => $bacula::process_user,
          group    => $bacula::process_group,
          require  => File['/var/lib/bacula'],
        }
      }
      default: {
        fail "The bacula module does not support managing the ${bacula::database_backend} backend database"
      }
    }
  }
}
