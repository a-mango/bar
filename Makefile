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

# The live copy in ~/.local/share/bar. It belongs to M8 (docs/PLAN.md
# section 6) and needs the owner's go-ahead, so it is not implemented yet.
install:
	@echo "make install is part of the M8 cutover (docs/PLAN.md section 6)" >&2; exit 1
