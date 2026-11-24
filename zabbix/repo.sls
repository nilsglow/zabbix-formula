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
   Use Zabbix's official release package which properly sets up the repo and key.
   Ubuntu release packages use the full release (24.04), not the major (24).
   From 7.2 on, Zabbix publishes the release packages under <version>/release/
   (packages under <version>/stable/, one repository for all architectures)
   and signs with a new key; only the release package knows both, so use it
   on every release. #}
{% set release_layout = zabbix.version_repo|float >= 7.2 %}
{% if salt['grains.get']('osmajorrelease')|int >= 13 or release_layout %}
{% set release = salt['grains.get']('osrelease') if salt['grains.get']('os') == 'Ubuntu' else salt['grains.get']('osmajorrelease') %}
{% set ubuntu_arm64 = salt['grains.get']('os') == 'Ubuntu' and salt['grains.get']('osarch') == 'arm64' and not release_layout %}
{% set repo_os = 'ubuntu-arm64' if ubuntu_arm64 else salt['grains.get']('os')|lower %}
{% set repo_dir = zabbix.version_repo ~ ('/release/' if release_layout else '/') ~ repo_os %}
{{ id_prefix }}_release_pkg_download:
  file.managed:
    - name: /tmp/zabbix-release.deb
    - source: https://repo.zabbix.com/zabbix/{{ repo_dir }}/pool/main/z/zabbix-release/zabbix-release_latest_{{ zabbix.version_repo }}+{{ salt['grains.get']('os')|lower }}{{ release }}_all.deb
    - skip_verify: True
    - require:
      - pkg: {{ id_prefix }}_apt-transport-https

{{ id_prefix }}_repo:
  pkg.installed:
    - sources:
      - zabbix-release: /tmp/zabbix-release.deb
    - require:
      - file: {{ id_prefix }}_release_pkg_download

# Current release packages ship zabbix.sources (Signed-By the package's
# keyring) and drop their former zabbix.list and trusted.gpg.d keys. A
# zabbix.list no package owns was written by the pkgrepo branch below before a
# dist-upgrade; next to zabbix.sources, APT rejects the conflicting Signed-By.
{{ id_prefix }}_legacy_list_absent:
  file.absent:
    - name: /etc/apt/sources.list.d/zabbix.list
    - unless: dpkg -S /etc/apt/sources.list.d/zabbix.list
    - require:
      - pkg: {{ id_prefix }}_repo

# The sources are conffiles: an upgrade of the release package (e.g. 6.0 to
# 8.0) keeps a locally modified one, such as the ARM64 rewrite below, and
# leaves the package's version as .dpkg-dist (Salt's --force-confold) or
# .dpkg-new. Take the package's version.
{{ id_prefix }}_release_sources_dpkg_new:
  cmd.run:
    - name: |
        for f in /etc/apt/sources.list.d/zabbix*.sources.dpkg-dist /etc/apt/sources.list.d/zabbix*.sources.dpkg-new; do
          if [ -e "$f" ]; then mv -f "$f" "${f%.dpkg-*}"; fi
        done
    - onlyif: ls /etc/apt/sources.list.d/zabbix*.sources.dpkg-dist /etc/apt/sources.list.d/zabbix*.sources.dpkg-new 2>/dev/null | grep -q .
    - require:
      - pkg: {{ id_prefix }}_repo

# The key the pkgrepo branch below fetched for that zabbix.list; the release
# package brings its own keyring.
{{ id_prefix }}_legacy_keyring_absent:
  file.absent:
    - name: /etc/apt/keyrings/zabbix.gpg
    - unless: grep -rqsF /etc/apt/keyrings/zabbix.gpg /etc/apt/sources.list /etc/apt/sources.list.d/
    - require:
      - file: {{ id_prefix }}_legacy_list_absent

# zabbix-release <= 6.0-4 shipped an unsigned zabbix-agent2-plugins.list that
# newer packages neither ship nor remove (the plugins are in the main
# repository now). It relies on the trusted.gpg.d keys below, and Debian 13's
# sqv rejects its signature even with them, which fails every package list
# refresh: remove it before the first package state. On a host whose release
# package is upgraded in this run, it goes in the next run; the keys stay
# until then (see their unless).
{{ id_prefix }}_obsolete_agent2_plugins_list_absent:
  file.absent:
    - name: /etc/apt/sources.list.d/zabbix-agent2-plugins.list
    - onlyif: dpkg-query -W -f '${Conffiles}\n' zabbix-release | grep -q '^ /etc/apt/sources.list.d/zabbix-agent2-plugins.list [0-9a-f]* obsolete$'
    - require_in:
      - pkg: {{ id_prefix }}_apt-transport-https

# Older release packages put their keys into trusted.gpg.d, where they are
# trusted for every repository. Newer ones no longer ship them, and dpkg keeps
# them as obsolete conffiles: remove them once they are obsolete.
{% for key in ['zabbix-official-repo.gpg', 'zabbix-official-repo-apr2024.gpg', 'zabbix-tools.gpg'] %}
{{ id_prefix }}_obsolete_{{ key|replace('.gpg', '')|replace('-', '_') }}_absent:
  file.absent:
    - name: /etc/apt/trusted.gpg.d/{{ key }}
    - onlyif: dpkg-query -W -f '${Conffiles}\n' zabbix-release | grep -q '^ /etc/apt/trusted.gpg.d/{{ key }} [0-9a-f]* obsolete$'
    # Keep the keys while any Zabbix line still relies on them, or APT fails.
    - unless: grep -hsE '^deb.*repo\.zabbix\.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.list | grep -qv signed-by
    - require:
      - pkg: {{ id_prefix }}_repo
      - file: {{ id_prefix }}_obsolete_agent2_plugins_list_absent
{% endfor %}

{% if ubuntu_arm64 %}
# The AMD64 and ARM64 release packages share a name/version. pkg.installed
# will not replace an already-installed AMD64 configuration with the ARM one.
{{ id_prefix }}_arm64_sources:
  file.replace:
    - name: /etc/apt/sources.list.d/zabbix.sources
    - pattern: '(https://repo\.zabbix\.com/zabbix/[^/\s]+/ubuntu)(?=\s|$)'
    - repl: '\1-arm64'
    - require:
      - pkg: {{ id_prefix }}_repo
      - cmd: {{ id_prefix }}_release_sources_dpkg_new
{% endif %}

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

{% if not zabbix.repo_aptkey and zabbix.repo_signedby %}
{# Keys imported with apt-key (repo_aptkey) into the legacy keyring are trusted
   for every repository. Remove them, but only once the list really references
   the keyring: pkgrepo.managed leaves an existing line without signed-by
   unchanged when python3-apt is installed (salt-ssh), and APT would then fail
   with NO_PUBKEY. #}
{% for fingerprint in ['FBABD5FB20255ECAB22EE194D13D58E479EA5ED4',
                       'A1848F5352D022B9471D83D0082AB56BA14FE591',
                       '4C3D6F2CC75F5146754FC374D913219AB5333005',
                       '84162C39F000750DDAEB816305A7FAEC227618D8'] %}
{{ id_prefix }}_legacy_apt_key_{{ fingerprint[-8:] }}_absent:
  cmd.run:
    - name: apt-key --keyring /etc/apt/trusted.gpg del {{ fingerprint }}
    - onlyif:
      - grep -qF '{{ zabbix.repo_signedby }}' /etc/apt/sources.list.d/zabbix.list
      - test -f /etc/apt/trusted.gpg
      - gpg --no-default-keyring --keyring /etc/apt/trusted.gpg --list-keys {{ fingerprint }}
    - require:
      - pkgrepo: {{ id_prefix }}_repo
{% endfor %}
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
