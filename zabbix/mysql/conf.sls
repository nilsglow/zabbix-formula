{% from "zabbix/map.jinja" import zabbix with context -%}
{% set settings = salt['pillar.get']('zabbix-mysql', {}) -%}
{% set defaults = zabbix.get('mysql', {}) -%}
# This required for backward compatibility
{% if 'dbpass' in settings -%}
{%  do settings.update({'dbpassword': settings['dbpass']}) -%}
{% endif -%}

{% set dbhost = settings.get('dbhost', defaults.dbhost) -%}
{% set dbname = settings.get('dbname', defaults.dbname) -%}
{% set dbuser = settings.get('dbuser', defaults.dbuser) -%}
{% set dbpassword = settings.get('dbpassword', defaults.dbpassword) -%}

{% set dbuser_host = settings.get('dbuser_host', defaults.dbuser_host) -%}
{% set dbroot_user = settings.get('dbroot_user') -%}
{% set dbroot_pass = settings.get('dbroot_pass') -%}
{#- MariaDB 10.6+ (Debian 12: 10.11) reports utf8 as utf8mb3; name it so the
    state stays clean. Zabbix 8.0 recommends utf8mb4 (utf8mb4_bin): set
    character_set and collate in pillar once the tables are converted. #}
{% set utf8 = 'utf8mb3' if grains.os == 'Debian' and grains.get('osmajorrelease', 0)|int >= 12 else 'utf8' -%}
{% set character_set = settings.get('character_set', utf8) -%}
{% set collate = settings.get('collate', utf8 ~ '_bin') -%}

# Install Python to MySQL interface packages.
{% if settings.get('pkgs', defaults.get('pkgs', False))
      and not settings.get('skip_pkgs', defaults.skip_pkgs) -%}
mysql_packages:
  pkg.installed:
    - pkgs: {{ settings.get('pkgs', defaults.pkgs)|json }}
{% elif settings.get('skip_pkgs', defaults.skip_pkgs) -%}
mysql_packages:
  test.configurable_test_state:
    - name: You skipped installation of packages with Python interface to MySQL.
    - changes: False
    - result: True
{% else -%}
mysql_packages:
  test.configurable_test_state:
    - name: MySQL prerequired packages are not defined
    - changes: False
    - result: False
    - comment: |
        Packages with Python interface to MySQL are required.
        Please specify them in pillar as list.
        zabbix-mysql:
          pkgs:
            - python-to-mysql-package
        Or you can skip installing them.
        zabbix-mysql:
          skip_pkgs: True
{% endif -%}

zabbix_db:
  mysql_database.present:
    - name: {{ dbname }}
    - host: {{ dbhost }}
    {%- if dbroot_user and dbroot_pass %}
    - connection_host: {{ dbhost }}
    - connection_user: {{ dbroot_user }}
    - connection_pass: {{ dbroot_pass }}
    {%- endif %}
    - character_set: {{ character_set }}
    - collate: {{ collate }}
    - require:
      - mysql_packages
  mysql_user.present:
    - name: {{ dbuser }}
    - host: '{{ dbuser_host }}'
    - password: {{ dbpassword }}
    {%- if dbroot_user and dbroot_pass %}
    - connection_host: {{ dbhost }}
    - connection_user: {{ dbroot_user }}
    - connection_pass: {{ dbroot_pass }}
    {%- endif %}
    - require:
      - mysql_packages
  mysql_grants.present:
    - grant: all privileges
    - database: {{ dbname }}.*
    - user: {{ dbuser }}
    - host: '{{ dbuser_host }}'
    {%- if dbroot_user and dbroot_pass %}
    - connection_host: {{ dbhost }}
    - connection_user: {{ dbroot_user }}
    - connection_pass: {{ dbroot_pass }}
    {%- endif %}
    - require:
      - mysql_packages
      - mysql_database: zabbix_db
      - mysql_user: zabbix_db
