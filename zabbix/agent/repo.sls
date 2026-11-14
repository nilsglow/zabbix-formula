{% from "zabbix/map.jinja" import zabbix with context -%}


include:
  - zabbix.agent


{# We have a common template for the official Zabbix repo #}
{% include "zabbix/repo.sls" %}


# Here we just add a requisite declaration to ensure correct order
extend:
  {% if salt['grains.get']('os_family') == 'Debian' and salt['grains.get']('osmajorrelease')|int >= 13 %}
  # The release .deb adds sources but does not fetch their indexes. Refresh at
  # agent installation, including retries after an interrupted first apply.
  zabbix-agent:
    pkg:
      - refresh: True
  zabbix_agent_legacy_list_absent:
    file:
      - require_in:
        - pkg: zabbix-agent
  {% for key in ['zabbix_official_repo', 'zabbix_official_repo_apr2024', 'zabbix_tools'] %}
  zabbix_agent_obsolete_{{ key }}_absent:
    file:
      - require_in:
        - pkg: zabbix-agent
  {% endfor %}
  {% if salt['grains.get']('os') == 'Ubuntu' and salt['grains.get']('osarch') == 'arm64' %}
  zabbix_agent_arm64_sources:
    file:
      - require_in:
        - pkg: zabbix-agent
  {% endif %}
  {% endif %}
  zabbix_agent_repo:
    {% if salt['grains.get']('os_family') == 'Debian' and salt['grains.get']('osmajorrelease')|int >= 13 -%}
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
