%define _prefix_path opt/axsh
%define _vdc_git_uri git://github.com/axsh/wakame-vdc.git
%define oname wakame-vdc
%define osubname example-1box

# * rpmbuild -bb ./wakame-vdc-example-1box.spec \
# --define "build_id $(../helpers/gen-release-id.sh)"
# --define "build_id $(../helpers/gen-release-id.sh [ commit-hash ])"

%define release_id 1.daily
%{?build_id:%define release_id %{build_id}}

Name: %{oname}-%{osubname}
Version: 12.03
Release: %{release_id}%{?dist}
Summary: The wakame virtual data center.
Group: Development/Languages
Vendor: Axsh Co. LTD <dev@axsh.net>
URL: http://wakame.jp/
Source: %{_vdc_git_uri}
Prefix: /%{_prefix_path}
License: see https://github.com/axsh/wakame-vdc/blob/master/README.md
BuildArch: noarch

%description
<insert long description, indented with spaces>

# example:common
%package common-vmapp-config
Summary: Configuration set for common %{osubname}
Group: Development/Languages
Requires: %{oname}-vdcsh
%description common-vmapp-config
<insert long description, indented with spaces>

# example:dcmgr
%package dcmgr-vmapp-config
Summary: Configuration set for dcmgr %{osubname}
Group: Development/Languages
Requires: %{oname}-dcmgr-vmapp-config
Requires: %{name}-common-vmapp-config
%description dcmgr-vmapp-config
<insert long description, indented with spaces>

# example:hva
%package hva-vmapp-config
Summary: Configuration set for hva %{osubname}
Group: Development/Languages
Requires: %{oname}-hva-full-vmapp-config
Requires: %{name}-common-vmapp-config
%description hva-vmapp-config
<insert long description, indented with spaces>

# example:full
%package full-vmapp-config
Summary: Configuration set for hva %{osubname}
Group: Development/Languages
Requires: %{name}-dcmgr-vmapp-config
Requires: %{name}-hva-vmapp-config
%description full-vmapp-config
<insert long description, indented with spaces>

## rpmbuild -bp
%prep
[ -d %{name}-%{version} ] || git clone %{_vdc_git_uri} %{name}-%{version}
cd %{name}-%{version}
git checkout master
git pull
[ -z "%{build_id}" ] || {
  build_id=%{build_id}
  git checkout ${build_id##*git}
  unset build_id
} && :

%setup -T -D

## rpmbuild -bc
%build

## rpmbuid -bi
%install
[ -d ${RPM_BUILD_ROOT} ] && rm -rf ${RPM_BUILD_ROOT}

mkdir -p ${RPM_BUILD_ROOT}/etc/%{oname}
mkdir -p ${RPM_BUILD_ROOT}/etc/%{oname}/dcmgr_gui

# generate /etc/%{oname}/*.conf
config_examples="dcmgr nsa sta"
for config_example in ${config_examples}; do
  cp -p `pwd`/dcmgr/config/${config_example}.conf.example ${RPM_BUILD_ROOT}/etc/%{oname}/${config_example}.conf
done
unset config_examples

VDC_ROOT=/var/lib/%{oname}
config_templates="proxy hva"
for config_template in ${config_templates}; do
  echo "$(eval "echo \"$(cat `pwd`/tests/vdc.sh.d/${config_template}.conf.tmpl)\"")" > ${RPM_BUILD_ROOT}/etc/%{oname}/${config_template}.conf
done
unset config_templates
unset VDC_ROOT

# /etc/%{oname}/dcmgr_gui/*.yml
config_ymls="database instance_spec dcmgr_gui"
for config_yml in ${config_ymls}; do
  cp -p `pwd`/frontend/dcmgr_gui/config/${config_yml}.yml.example ${RPM_BUILD_ROOT}/etc/%{oname}/dcmgr_gui/${config_yml}.yml
done
unset config_ymls

%post dcmgr-vmapp-config
# activate upstart system job
sys_default_confs="auth collector dcmgr metadata nsa proxy sta webui"
for sys_default_conf in ${sys_default_confs}; do
  sed -i s,^#RUN=.*,RUN=yes, /etc/default/vdc-${sys_default_conf}
done

# set demo parameters
for sys_default_conf in /etc/default/vdc-*; do sed -i s,^#NODE_ID=.*,NODE_ID=demo1, ${sys_default_conf}; done
[ -f /etc/wakame-vdc/unicorn-common.conf ] && sed -i "s,^worker_processes .*,worker_processes 1," /etc/wakame-vdc/unicorn-common.conf

%post hva-vmapp-config
# activate upstart system job
sys_default_confs="hva"
for sys_default_conf in ${sys_default_confs}; do
  sed -i s,^#RUN=.*,RUN=yes, /etc/default/vdc-${sys_default_conf}
done

# set demo parameters
for sys_default_conf in /etc/default/vdc-*; do sed -i s,^#NODE_ID=.*,NODE_ID=demo1, ${sys_default_conf}; done

%clean
rm -rf ${RPM_BUILD_ROOT}

%files common-vmapp-config
%defattr(-,root,root)

%files dcmgr-vmapp-config
%config /etc/%{oname}/dcmgr.conf
%config /etc/%{oname}/nsa.conf
%config /etc/%{oname}/sta.conf
%config /etc/%{oname}/proxy.conf
%config /etc/%{oname}/dcmgr_gui/database.yml
%config /etc/%{oname}/dcmgr_gui/instance_spec.yml
%config /etc/%{oname}/dcmgr_gui/dcmgr_gui.yml

%files hva-vmapp-config
%config /etc/%{oname}/hva.conf

%files full-vmapp-config

%changelog
