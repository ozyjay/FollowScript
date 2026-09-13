#!/bin/sh

set -eu

project_dir=${PROJECT_DIR:?PROJECT_DIR is required}
generated_configuration="$project_dir/Config/GitBuildNumber.xcconfig"

commit_count=$(git -C "$project_dir" rev-list --count HEAD)
case "$commit_count" in
    ''|*[!0-9]*|0)
        echo "Could not derive a valid build number from the Git commit count." >&2
        exit 1
        ;;
esac

expected_setting="GIT_COMMIT_COUNT = $commit_count"
if [ -f "$generated_configuration" ] && grep -qx "$expected_setting" "$generated_configuration"; then
    echo "Git commit build number: $commit_count"
    exit 0
fi

temporary_file="$generated_configuration.tmp.$$"
printf '%s\n' "$expected_setting" > "$temporary_file"
mv "$temporary_file" "$generated_configuration"

echo "Git commit build number: $commit_count"
