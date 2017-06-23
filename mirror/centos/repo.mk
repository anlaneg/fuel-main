include $(SOURCE_DIR)/mirror/centos/yum_repos.mk

.PHONY: show-yum-urls-centos show-yum-urls-centos-full show-yum-repos-centos

MIRROR_CENTOS_OS_BASEURL?=$(MIRROR_CENTOS)/os/$(CENTOS_ARCH)

#由于前两个目标没有执行语句，故此目标将被合并。将yum_conf宏写入到yum.conf中
$(BUILD_DIR)/mirror/centos/etc/yum.conf: $(call depv,yum_conf)
$(BUILD_DIR)/mirror/centos/etc/yum.conf: export contents:=$(yum_conf)
$(BUILD_DIR)/mirror/centos/etc/yum.conf:
	mkdir -p $(@D)
	/bin/echo -e "$${contents}" > $@

#copy yum插件到yum-plugins目录
$(BUILD_DIR)/mirror/centos/etc/yum-plugins/priorities.py: \
		$(SOURCE_DIR)/mirror/centos/yum-priorities-plugin.py
	mkdir -p $(@D)
	cp $(SOURCE_DIR)/mirror/centos/yum-priorities-plugin.py $@

# DENY_RPM_DOWNGRADE=0 - Disable full_match flag for yum priorities plugin.
# This means that we choose package candidate not by full match
# of version, realase and arch. This may lead to downgrading of
# packages (actually this is what we may want sometimes for
# testing purposes). Please use priorities plugin carefully

$(BUILD_DIR)/mirror/centos/etc/yum/pluginconf.d/priorities.conf:
	mkdir -p $(@D)
	/bin/echo -e "[main]\nenabled=1\ncheck_obsoletes=1\nfull_match=$(DENY_RPM_DOWNGRADE)" > $@

#依据用户配置的YUM repos生成base.repo文件，每一个名称有yum_repo_XXX
$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/base.repo: $(call depv,YUM_REPOS)
$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/base.repo: \
		export contents:=$(foreach repo,$(YUM_REPOS),\n$(yum_repo_$(repo))\n)
$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/base.repo:
	@mkdir -p $(@D)
	/bin/echo -e "$${contents}" > $@

#为yumdownloader打上补丁，产生自已的yumdownloader
$(BUILD_DIR)/bin/yumdownloader: $(SOURCE_DIR)/mirror/centos/yumdownloader-deps.patch
	mkdir -p $(@D)
	cp -a /usr/bin/yumdownloader $(BUILD_DIR)/yumdownloader
	( cd $(BUILD_DIR) && patch -p0 ) < $<
	cp -a $(BUILD_DIR)/yumdownloader $@

#依据用户配置的extra rpm repos生成extra.repo
$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/extra.repo: $(call depv,EXTRA_RPM_REPOS)
$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/extra.repo: \
		export contents:=$(foreach repo,$(EXTRA_RPM_REPOS),\n$(call create_extra_repo,$(repo))\n)
$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/extra.repo:
	@mkdir -p $(@D)
	/bin/echo -e "$${contents}" > $@

centos_empty_installroot:=$(BUILD_DIR)/mirror/centos/dummy_installroot

#对yumdownloader打补丁
#生成yum.conf文件,苍库配置，设置插件，设置插件配置，设置yum配置完成
$(BUILD_DIR)/mirror/centos/yum-config.done: \
		$(BUILD_DIR)/bin/yumdownloader \
		$(BUILD_DIR)/mirror/centos/etc/yum.conf \
		$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/base.repo \
		$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/extra.repo \
		$(BUILD_DIR)/mirror/centos/etc/yum-plugins/priorities.py \
		$(BUILD_DIR)/mirror/centos/etc/yum/pluginconf.d/priorities.conf
	rm -rf $(centos_empty_installroot)
	mkdir -p $(centos_empty_installroot)/cache
	$(ACTION.TOUCH)

#完成rpm包下载
$(BUILD_DIR)/mirror/centos/yum.done: $(BUILD_DIR)/mirror/centos/rpm-download.done
	$(ACTION.TOUCH)

#下载urls.list中的包（urls.list中记录的是yumdownloader需要下载的包吗？）
$(BUILD_DIR)/mirror/centos/rpm-download.done: $(BUILD_DIR)/mirror/centos/urls.list
	dst="$(LOCAL_MIRROR_CENTOS_OS_BASEURL)/Packages"; \
	mkdir -p "$$dst" && \
	xargs -n1 -P4 wget -Nnv -P "$$dst" < $<
	$(ACTION.TOUCH)

# BUILD_PACKAGES=0 - apply patch for requirements rpm, since we need fuel-packages
ifeq ($(BUILD_PACKAGES),0)
#requirements-rpm.txt由source_dir下的requirements-rpm.txt与requirements-fule-rpm.txt
#生成.$^是所有依赖文件，采用cat显示后，按顺序被写入.tmp文件，然后再由tmp文件重命名生成.txt文件
#生成时间过长，如果一步生成时，出错，则依赖将被满足
$(BUILD_DIR)/requirements-rpm.txt: \
		$(SOURCE_DIR)/requirements-rpm.txt \
		$(SOURCE_DIR)/requirements-fuel-rpm.txt
	cat $^ | sort -u > $@.tmp
	mv $@.tmp $@
else
#创建$(BUILD_DIR)，并将$< copy到 $@D中
$(BUILD_DIR)/requirements-rpm.txt: $(SOURCE_DIR)/requirements-rpm.txt
	$(ACTION.COPY)
endif

# Strip the comments and sort the list alphabetically
# 丢弃掉requirements-rpm.txt中的以'#'号开头的行，并重新排序 （即*-rpm-0是不含注释行的）
# $(BUILD_DIR)/requirements-rpm.txt 文件
$(BUILD_DIR)/mirror/centos/requirements-rpm-0.txt: $(BUILD_DIR)/requirements-rpm.txt
	mkdir -p $(@D) && \
	grep -v -e '^#' $< > $@.tmp && \
	sort -u < $@.tmp > $@.pre && \
	mv $@.pre $@

#整理出需要的rpm包，完成yum配置，下载需要的rpm包
$(BUILD_DIR)/mirror/centos/urls.list: $(BUILD_DIR)/mirror/centos/requirements-rpm-0.txt \
		$(BUILD_DIR)/mirror/centos/yum-config.done
	touch "$(BUILD_DIR)/mirror/centos/conflicting-packages-0.lst"
	# 1st pass - find out which packages conflict
	# 2nd pass - get the URLs of non-conflicting packages
	# 3rd pass (under the else clause) - process the conflicting rpms one by one
	count=0; \
	while true; do \
		if [ $$count -gt 1 ]; then \
			echo "Unable to resolve packages dependencies" >&2; \
			cat $(BUILD_DIR)/mirror/centos/yumdownloader-1.out >&2; \
			exit 1; \
		fi; \
		requirements_rpm="$(BUILD_DIR)/mirror/centos/requirements-rpm-$${count}.txt"; \
		requirements_rpm_next="$(BUILD_DIR)/mirror/centos/requirements-rpm-$$((count+1)).txt"; \
		out="$(BUILD_DIR)/mirror/centos/yumdownloader-$${count}.out"; \
		log="$(BUILD_DIR)/mirror/centos/yumdownloader-$${count}.log"; \
		conflict_lst="$(BUILD_DIR)/mirror/centos/conflicting-packages-$${count}.lst"; \
		conflict_lst_next="$(BUILD_DIR)/mirror/centos/conflicting-packages-$$((count+1)).lst"; \
		if ! env \
			TMPDIR="$(centos_empty_installroot)/cache" \
			TMP="$(centos_empty_installroot)/cache" \
			$(BUILD_DIR)/bin/yumdownloader -q --urls \
				--archlist=$(CENTOS_ARCH) \
				--installroot="$(centos_empty_installroot)" \
				-c $(BUILD_DIR)/mirror/centos/etc/yum.conf \
				--resolve \
				`cat $${requirements_rpm}` > "$$out" 2>"$$log"; then \
			sed -rne 's/^([a-zA-Z0-9_-]+)\s+conflicts with\s+(.+)$$/\1/p' < "$$out" > "$${conflict_lst_next}.pre" && \
			# Package X can declare conflict with package Y; but package Y is not obliged \
			# to declare a conflict with package X. yum will report that X conflicts with Y. \
			# We need to figure out that Y conflicts with X on our own. \
			sed -rne 's/^([a-zA-Z0-9_-]+)\s+conflicts with\s+(.+)$$/\2/p' < "$$out" > "$${conflict_lst_next}.more" && \
			while read nvra; do \
				nvr="$${nvra%.*}"; nv="$${nvr%-*}"; n="$${nv%-*}"; echo $$n; \
			done < "$${conflict_lst_next}.more" >> "$${conflict_lst_next}.pre" && \
			cat "$${conflict_lst_next}.pre" "$$conflict_lst" | sort -u > "$$conflict_lst_next" && \
			comm -23 "$$requirements_rpm" "$$conflict_lst_next" > "$${requirements_rpm}.new.pre" && \
			sort -u < "$${requirements_rpm}.new.pre" > "$${requirements_rpm_next}"; \
		else \
			conflicting_pkgs_urls="$(BUILD_DIR)/mirror/centos/urls_conflicting.lst"; \
			nonconflicting_pkgs="$$requirements_rpm"; \
			# Now process conflicting packages one by one. There is a small problem: \
			# in the original requirements-rpm.txt quite a number of packages are    \
			# pinned to specific versions. These pins should be taken into account   \
			# to avoid having several versions of the same package. For instance,    \
			# zabbix-web-* depends on httpd, so the latest version of httpd gets     \
			# installed along with the one listed in the requirements-rpm.txt.       \
			# Therefore add the set of all nonconflicting packages to the package    \
			# being processed to take into account version pins.                     \
			for pkg in `cat $$conflict_lst`; do \
				if ! env \
					TMPDIR="$(centos_empty_installroot)/cache" \
					TMP="$(centos_empty_installroot)/cache" \
					$(BUILD_DIR)/bin/yumdownloader -q --urls \
						--archlist=$(CENTOS_ARCH) \
						--installroot="$(centos_empty_installroot)" \
						-c "$(BUILD_DIR)/mirror/centos/etc/yum.conf" \
						--resolve $$pkg `cat $$nonconflicting_pkgs`; then \
					echo "Failed to resolve package $$pkg" >&2; \
					exit 1; \
				fi; \
			done > "$$conflicting_pkgs_urls" && \
			cat "$$out" "$$conflicting_pkgs_urls" > "$@.out" && \
			break; \
		fi; \
		count=$$((count+1)); \
	done
	# yumdownloader -q prints logs to stdout, filter them out
	sed -rne '/\.rpm$$/ {p}' < $@.out > $@.pre
	sort -u < $@.pre > $@.tmp
	mv $@.tmp $@.full
	grep "$(MIRROR_CENTOS)" $@.full > $@

show-yum-urls-centos: $(BUILD_DIR)/mirror/centos/urls.list
	cat $<

show-yum-urls-centos-full: $(BUILD_DIR)/mirror/centos/urls.list
	cat $(BUILD_DIR)/mirror/centos/urls.list.full

show-yum-repos-centos: \
		$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/base.repo \
		$(BUILD_DIR)/mirror/centos/etc/yum.repos.d/extra.repo
	cat $^

$(LOCAL_MIRROR_CENTOS_OS_BASEURL)/comps.xml: \
		export COMPSXML=$(shell wget -nv -qO- $(MIRROR_CENTOS_OS_BASEURL)/repodata/repomd.xml | grep -m 1 '$(@F)' | awk -F'"' '{ print $$2 }')
$(LOCAL_MIRROR_CENTOS_OS_BASEURL)/comps.xml:
	@mkdir -p $(@D)
	if ( echo $${COMPSXML} | grep -q '\.gz$$' ); then \
		wget -nv -O $@.gz $(MIRROR_CENTOS_OS_BASEURL)/$${COMPSXML}; \
		gunzip $@.gz; \
	else \
		wget -nv -O $@ $(MIRROR_CENTOS_OS_BASEURL)/$${COMPSXML}; \
	fi

#命令前提目标（order-only Prerequisites）,comps.xml的更新不引响repo.done的生成
#创建yum仓库
$(BUILD_DIR)/mirror/centos/repo.done: \
		$(BUILD_DIR)/mirror/centos/yum.done \
		| $(LOCAL_MIRROR_CENTOS_OS_BASEURL)/comps.xml
	createrepo -g $(LOCAL_MIRROR_CENTOS_OS_BASEURL)/comps.xml \
		-o $(LOCAL_MIRROR_CENTOS_OS_BASEURL)/ $(LOCAL_MIRROR_CENTOS_OS_BASEURL)/
	$(ACTION.TOUCH)
