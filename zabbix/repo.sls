{% from "zabbix/map.jinja" import zabbix with context -%}

# Zabbix official repo releases a deb package that sets a zabbix.list apt
# sources. Here we do the same as that package does, including the PGP key for
# the repo.


# In order to share this state file among the different parts of Zabbix (agent,
# server, frontend, proxy) we have to name the states accordingly. See
# https://github.com/moreda/zabbix-saltstack-formula/issues/2 if you're curious.


{% if sls == "zabbix.agent.repo" %}{% set id_prefix = "zabbix_agent" -%}
{% elif sls == "zabbix.server.repo" %}{% set id_prefix = "zabbix_server" -%}
{% elif sls == "zabbix.frontend.repo" %}{% set id_prefix = "zabbix_frontend" -%}
{% elif sls == "zabbix.proxy.repo" %}{% set id_prefix = "zabbix_proxy" -%}
{% else %}{% set id_prefix = "zabbix" -%}
{% endif -%}


{% if salt['grains.get']('os_family') == 'Debian' -%}
{{ id_prefix }}_apt-transport-https:
  pkg.installed:
    - name: apt-transport-https

{# Debian 13+ uses Sequoia sqv which has stricter GPG key format requirements.
   Use Zabbix's official release package which properly sets up the repo and key. #}
{% if salt['grains.get']('osmajorrelease')|int >= 13 %}
{{ id_prefix }}_release_pkg_download:
  file.managed:
    - name: /tmp/zabbix-release.deb
    - source: https://repo.zabbix.com/zabbix/{{ zabbix.version_repo }}/{{ salt['grains.get']('os')|lower }}/pool/main/z/zabbix-release/zabbix-release_latest_{{ zabbix.version_repo }}+{{ salt['grains.get']('os')|lower }}{{ salt['grains.get']('osmajorrelease') }}_all.deb
    - skip_verify: True
    - require:
      - pkg: {{ id_prefix }}_apt-transport-https

{{ id_prefix }}_repo:
  pkg.installed:
    - sources:
      - zabbix-release: /tmp/zabbix-release.deb
    - require:
      - file: {{ id_prefix }}_release_pkg_download

{% else %}
{% if not zabbix.repo_aptkey %}
{{ id_prefix }}_keyrings_dir:
  file.directory:
    - name: /etc/apt/keyrings
    - mode: 755
{{ id_prefix }}_gpg_key:
  cmd.run:
    - name: curl -fsSL https://repo.zabbix.com/zabbix-official-repo.key | gpg --dearmor -o /etc/apt/keyrings/zabbix.gpg
    - creates: /etc/apt/keyrings/zabbix.gpg
    - require:
      - file: {{ id_prefix }}_keyrings_dir
{% endif %}
{{ id_prefix }}_repo:
  pkgrepo.managed:
    - name: deb [ arch={{ salt['grains.get']('osarch')|lower }} {{ zabbix.repo_signedby }} ]
        https://repo.zabbix.com/zabbix/{{ zabbix.version_repo }}/{{ salt['grains.get']('os')|lower }} {{ salt['grains.get']('oscodename') }} main
    - file: /etc/apt/sources.list.d/zabbix.list
    - key_url: https://repo.zabbix.com/zabbix-official-repo.key
    - clean_file: True
    - aptkey: {{ zabbix.repo_aptkey }}
{% if not zabbix.repo_aptkey %}
    - require:
      - cmd: {{ id_prefix }}_gpg_key
{% endif %}
{% endif %}

{%- elif salt['grains.get']('os_family') == 'RedHat' and
         salt['grains.get']('osmajorrelease')|int >= 6 %}
{%- if zabbix.version_repo|float > 3.0 %}
{%-   set gpgkey = 'https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-A14FE591' %}
{%- else %}
{%-   set gpgkey = 'https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-79EA5ED4' %}
{%- endif %}

{{ id_prefix }}_repo:
  pkgrepo.managed:
    - name: zabbix
    - humanname: Zabbix Official Repository - $basearch
    - baseurl: http://repo.zabbix.com/zabbix/{{ zabbix.version_repo }}/rhel/{{ grains['osmajorrelease']|int }}/$basearch/
    - gpgcheck: 1
    - gpgkey: {{ gpgkey }}

{{ id_prefix }}_non_supported_repo:
  pkgrepo.managed:
    - name: zabbix-non-supported
    - humanname: Zabbix Official Repository non-supported - $basearch
    - baseurl: http://repo.zabbix.com/non-supported/rhel/{{ grains['osmajorrelease']|int }}/$basearch/
    - gpgcheck: 1
    - gpgkey: https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-79EA5ED4

{%- elif salt['grains.get']('os_family') == 'Suse' %}
{{ id_prefix }}_repo:
  pkgrepo.managed:
    - name: zabbix
    - humanname: "Zabbix Official Repository"
    - baseurl: https://repo.zabbix.com/zabbix/{{ zabbix.version_repo }}/sles/{{ grains['osmajorrelease'] }}/x86_64/
    - gpgcheck: 1
    - gpgkey: https://repo.zabbix.com/zabbix/{{ zabbix.version_repo }}/sles/{{ grains['osmajorrelease'] }}/x86_64/repodata/repomd.xml.key
    - gpgautoimport: True

{%- else %}
{{ id_prefix }}_repo: {}
{%- endif %}
