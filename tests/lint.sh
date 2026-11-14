#!/usr/bin/env bash
# qmllint over the tree. Quickshell resolves `import qs.<dir>` at run time;
# qmllint cannot, so this builds the modules under .test/lint/ (a qmldir and
# copies of the files per directory) and passes that as an import path.
#
# Known noise from the Quickshell type files of this snapshot, not from the
# tree: PanelWindow "is not creatable" (category disabled below), the
# I3IpcEvent and QProcess::ExitStatus signal parameters, PopupAnchor's
# `edges` and `gravity`, and the DBusMenuHandle type of SystemTrayItem.menu.
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
QMLLINT=${QMLLINT:-/usr/lib64/qt6/bin/qmllint}
cd "$REPO"

rm -rf .test/lint
for dir in services bar overlay; do
    mkdir -p ".test/lint/qs/$dir"
    {
        echo "module qs.$dir"
        for file in "$dir"/*.qml; do
            name=$(basename "$file" .qml)
            cp "$REPO/$file" ".test/lint/qs/$dir/$name.qml"
            if grep -q '^pragma Singleton' "$file"; then
                echo "singleton $name 1.0 $name.qml"
            else
                echo "$name 1.0 $name.qml"
            fi
        done
    } > ".test/lint/qs/$dir/qmldir"
done

# The module files are linted through their copies (qmllint resolves
# links to the real path), so that references
# between files of the same directory resolve through the generated qmldir.
exec "$QMLLINT" -I .test/lint -I /usr/lib64/qt6/qml --uncreatable-type disable \
    shell.qml .test/lint/qs/*/*.qml tests/client/*.qml
