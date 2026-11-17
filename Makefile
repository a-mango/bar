# bar: commands for the nested test desktop, tests and tooling.
# See CLAUDE.md for what each target is for.

QT_BIN := /usr/lib64/qt6/bin
SHADERS := $(patsubst %.frag,%.frag.qsb,$(wildcard shaders/*.frag))

.PHONY: nested nested-stop reference matrix shots log test shaders lint install

nested:
	tests/nested.sh start

nested-stop:
	tests/nested.sh stop

reference:
	tests/nested.sh reference

# make matrix CASE=N5 runs one case.
matrix:
	tests/matrix.sh $(CASE)

shots:
	tests/nested.sh shot

log:
	tests/nested.sh run quickshell log -p $(CURDIR) --follow

test:
	node --test tests/*.test.mjs

shaders: $(SHADERS)

%.frag.qsb: %.frag
	$(QT_BIN)/qsb --qt6 -o $@ $<

lint:
	tests/lint.sh

# The live copy (docs/PLAN.md section 6): the committed tree at a tagged
# HEAD, only the files the shell loads, plus the compiled shaders, and the
# `live` marker that turns file watching off. A running live instance does
# not see the new files: restart bar.service afterwards. DEST=/abs/path
# installs elsewhere (the dry run in the nested session).
DEST ?= $(HOME)/.local/share/bar
STAGE := $(CURDIR)/.test/install

install: shaders
	@test -z "$$(git status --porcelain --untracked-files=no)" || { echo "make install: commit the changes first" >&2; exit 1; }
	@git describe --tags --exact-match HEAD > /dev/null 2>&1 || { echo "make install: tag HEAD first" >&2; exit 1; }
	@case "$(DEST)" in /*) ;; *) echo "make install: DEST must be absolute" >&2; exit 1 ;; esac
	rm -rf $(STAGE) && mkdir -p $(STAGE)
	git archive HEAD shell.qml bar overlay services themes shaders | tar -x -C $(STAGE)
	cp shaders/*.qsb $(STAGE)/shaders/
	git describe --tags --exact-match HEAD > $(STAGE)/live
	mkdir -p "$(DEST)"
	rsync -a --delete $(STAGE)/ "$(DEST)/"
	@echo "make install: $$(cat $(STAGE)/live) is in $(DEST)"
