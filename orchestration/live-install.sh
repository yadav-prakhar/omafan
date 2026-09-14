#!/usr/bin/env bash
# orchestration/live-install.sh — orchestrator tool: put the working tree into
# the shell's plugin directory, enable it, rescan, and report. Never destructive:
# the operator's shell.json is backed up before any change and `remove` puts it
# back.
#
# Usage: orchestration/live-install.sh install|verify|remove|revert
set -uo pipefail

ID="io.github.yadav-prakhar.omafan"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$HOME/.config/omarchy/plugins/$ID"
shell_json="$HOME/.config/omarchy/shell.json"
backup_dir="$repo/orchestration/backups"

export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(basename "$(ls -d /run/user/"$(id -u)"/hypr/*/ 2>/dev/null | head -1)")}"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

log() { printf '%s\n' "$*"; }

do_install() {
    mkdir -p "$backup_dir"
    cp -p "$shell_json" "$backup_dir/shell.json.$(date +%Y%m%d-%H%M%S).bak"
    log "backed up shell.json -> $backup_dir"

    mkdir -p "$dest"
    # Copy the working tree without VCS metadata or build scratch.
    rsync -a --delete --exclude '.git' --exclude '.recon' --exclude 'orchestration/logs' \
        "$repo"/ "$dest"/ 2>/dev/null || {
        # rsync may be absent; tar is always there.
        (cd "$repo" && tar -cf - --exclude='.git' --exclude='.recon' --exclude='orchestration/logs' .) |
            (cd "$dest" && tar -xf -)
    }
    chmod +x "$dest"/bin/* "$dest"/tests/*.sh "$dest"/tests/fixtures/fake-afanctl 2>/dev/null
    log "copied working tree -> $dest"

    omarchy plugin validate "$dest" || return 1
    omarchy plugin enable "$ID" --section right || return 1
    omarchy-shell shell rescanPlugins
    sleep 2
    omarchy plugin list --json | jq -c --arg id "$ID" '.[] | select(.id == $id) | {id, enabled, active, kinds}'
}

do_verify() {
    echo "--- plugin registry"
    omarchy plugin list --json | jq -c --arg id "$ID" '.[] | select(.id == $id) | {id, enabled, active}'
    echo "--- shell IPC"
    omarchy-shell "$ID" state 2>&1 | head -c 400
    echo
    echo "--- shell log (errors mentioning omafan in the last 200 lines)"
    qs log -p "$OMARCHY_PATH/shell" --tail 200 2>/dev/null | grep -iE "omafan|ERROR|error" | tail -20 || echo "(no matches)"
    echo "--- bar layout entry"
    jq -c --arg id "$ID" '[.bar.layout[]?[]? | select(.id == $id)]' "$shell_json"
}

do_remove() {
    omarchy plugin remove "$ID" --yes
    log "removed $ID from the shell"
}

do_revert() {
    latest="$(ls -t "$backup_dir"/shell.json.*.bak 2>/dev/null | head -1)"
    if [[ -n $latest ]]; then
        cp -p "$latest" "$shell_json"
        log "restored shell.json from $latest"
    else
        log "no shell.json backup found in $backup_dir"
    fi
    [[ -d $dest ]] && rm -rf "$dest" && log "deleted $dest"
    omarchy-shell -q shell rescanPlugins
}

case "${1:-}" in
    install) do_install ;;
    verify) do_verify ;;
    remove) do_remove ;;
    revert) do_revert ;;
    *) echo "usage: $0 install|verify|remove|revert" >&2; exit 2 ;;
esac
