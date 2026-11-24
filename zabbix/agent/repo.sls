{% from "zabbix/map.jinja" import zabbix with context -%}


include:
  - zabbix.agent


{# We have a common template for the official Zabbix repo #}
{% include "zabbix/repo.sls" %}


{#- Debian 13+, and every release from Zabbix 7.2 on, use the release package
    (zabbix/repo.sls). #}
{%- set release_pkg = salt['grains.get']('os_family') == 'Debian' and
      (salt['grains.get']('osmajorrelease')|int >= 13 or zabbix.version_repo|float >= 7.2) %}

# Here we just add a requisite declaration to ensure correct order
extend:
  {% if release_pkg %}
  # The release .deb adds sources but does not fetch their indexes. Refresh at
  # agent installation, including retries after an interrupted first apply.
  zabbix-agent:
    pkg:
      - refresh: True
  zabbix_agent_legacy_list_absent:
    file:
      - require_in:
        - pkg: zabbix-agent
  zabbix_agent_release_sources_dpkg_new:
    cmd:
      - require_in:
        - pkg: zabbix-agent
  {% for key in ['zabbix_official_repo', 'zabbix_official_repo_apr2024', 'zabbix_tools'] %}
  zabbix_agent_obsolete_{{ key }}_absent:
    file:
      - require_in:
        - pkg: zabbix-agent
  {% endfor %}
  {% if salt['grains.get']('os') == 'Ubuntu' and salt['grains.get']('osarch') == 'arm64' and zabbix.version_repo|float < 7.2 %}
  zabbix_agent_arm64_sources:
    file:
      - require_in:
        - pkg: zabbix-agent
  {% endif %}
  {% endif %}
  zabbix_agent_repo:
    {% if release_pkg -%}
    pkg:
      - require_in:
        - pkg: zabbix-agent
    {% elif salt['grains.get']('os_family') in ['Debian', 'Suse'] -%}
    pkgrepo:
      - require_in:
        - pkg: zabbix-agent
    {% elif salt['grains.get']('os_family') == 'RedHat' -%}
    pkgrepo:
      - require_in:
        - pkg: zabbix-agent
  zabbix_agent_non_supported_repo:
    pkgrepo:
      - require_in:
        - pkg: zabbix-agent
    {%- else %} {}
    {%- endif %}
