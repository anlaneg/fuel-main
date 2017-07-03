#创建$@需要的目录，将$<文件copy到$@中
define ACTION.COPY
@mkdir -p $(@D)
cp $< $@
endef

#创建$@对应的目录，并touch $@
define ACTION.TOUCH
@mkdir -p $(@D)
touch $@
endef

# This macros is to make targets dependent on variables
# It writes variable value into temporary file varname.tmp,
# then it compares temporary file with the varname.dep file.
# If there is a difference between them, varname.dep will be updated
# and the target which depends on it will be rebuilt.
# Example:
# target: $(call depv,varname)
# 如果$($1)之前的值与$1.dep中记录的不相等，则重建.dep,则会导致$@将被重建
#如果相等，则$@不会被重建
DEPV_DIR:=$(BUILD_DIR)/depv
define depv
$(shell mkdir -p $(DEPV_DIR))
$(shell echo "$($1)" > $(DEPV_DIR)/$1.tmp)
$(shell diff >/dev/null 2>&1 $(DEPV_DIR)/$1.tmp $(DEPV_DIR)/$1.dep \
	|| mv $(DEPV_DIR)/$1.tmp $(DEPV_DIR)/$1.dep)
$(DEPV_DIR)/$1.dep
endef

#输出一个空行
define NEWLINE


endef

$(BUILD_DIR)/%/.dir:
	mkdir -p $(@D)
	@touch $@

assert-variable=$(if $($1),,$(error Variable $1 need to be defined))
find-files=$(shell test -e $1 && find $1 -type f 2> /dev/null)

# uppercase conversion routine
# usage: UPPER_VAR = $(call uc,$(VAR))
uc = $(shell echo $(1) | tr a-z A-Z)

comma:=,

space:=
space+=
