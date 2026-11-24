{% from "zabbix/map.jinja" import zabbix with context %}


include:
  - zabbix.server


# We have a common template for the official Zabbix repo
{% include "zabbix/repo.sls" %}


{#- Debian 13+, and every release from Zabbix 7.2 on, use the release package
    (zabbix/repo.sls). #}
{%- set release_pkg = salt['grains.get']('os_family') == 'Debian' and
      (salt['grains.get']('osmajorrelease')|int >= 13 or zabbix.version_repo|float >= 7.2) %}

# Here we just add a requisite declaration to ensure correct order
extend:
  {% if release_pkg %}
  # The release .deb adds sources but does not fetch their indexes (see
  # zabbix/agent/repo.sls).
  zabbix-server:
    pkg:
      - refresh: True
  zabbix_server_legacy_list_absent:
    file:
      - require_in:
        - pkg: zabbix-server
  zabbix_server_release_sources_dpkg_new:
    cmd:
      - require_in:
        - pkg: zabbix-server
  {% endif %}
  zabbix_server_repo:
    {% if release_pkg -%}
    pkg:
      - require_in:
        - pkg: zabbix-server
    {% elif salt['grains.get']('os_family') in ['Debian', 'Suse'] -%}
    pkgrepo:
      - require_in:
        - pkg: zabbix-server
    {% elif salt['grains.get']('os_family') == 'RedHat' -%}
    pkgrepo:
      - require_in:
        - pkg: zabbix-server
  zabbix_server_non_supported_repo:
    pkgrepo:
      - require_in:
        - pkg: zabbix-server
    {%- else %} {}
    {%- endif %}
