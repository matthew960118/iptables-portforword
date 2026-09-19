#!/bin/bash

set -Eeuo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/port_forwards.json}"

TAG="FORWARD_TOOL"
EXT_IF="ppp0"
INT_IF="wg0"
DNAT_CHAIN="FORWARD_TOOL_DNAT"
FORWARD_CHAIN="FORWARD_TOOL_FORWARD"
SNAT_CHAIN="FORWARD_TOOL_SNAT"

COMPLETION_FILE="/etc/bash_completion.d/portforward"
ZSH_COMPLETION_FILE="/usr/local/share/zsh/site-functions/_portforward"

error() {
    echo "ERROR: $*" >&2
    exit 1
}

require_root() {
    [[ "$EUID" -eq 0 ]] || error "This script must be run with sudo."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

show_help() {
    echo "========================================================"
    echo " Port Forwarding Tool Usage"
    echo "========================================================"
    echo "Usage: sudo portforward [action]"
    echo
    echo "Supported actions:"
    echo "  apply   : Sync and apply rules from configuration"
    echo "  edit    : Edit $CONFIG_FILE only; run apply afterwards"
    echo "  rm      : Remove this tool's chains and jump rules"
    echo "  completion : Install Bash and zsh tab completion"
    echo "  help    : Display this documentation (Default)"
    echo
    echo "Files:"
    echo "  edit modifies: $CONFIG_FILE"
    echo "  completion modifies: $COMPLETION_FILE and $ZSH_COMPLETION_FILE"
    echo "========================================================"
}

edit_config() {
    require_command jq
    [[ -f "$CONFIG_FILE" ]] || error "Configuration file not found: $CONFIG_FILE"
    local editor_command="${VISUAL:-${EDITOR:-nano}}"
    command -v "$editor_command" >/dev/null 2>&1 || error "Editor not found: $editor_command"
    "$editor_command" "$CONFIG_FILE"
}

write_bash_completion() {
    printf '%s\n' \
        '_portforward() {' \
        '    local current_word="${COMP_WORDS[COMP_CWORD]}"' \
        '    local actions="apply edit rm completion help"' \
        '' \
        '    if (( COMP_CWORD == 1 )); then' \
        '        COMPREPLY=("$(compgen -W "$actions" -- "$current_word")")' \
        '    fi' \
        '}' \
        '' \
        'complete -F _portforward portforward'
}

write_zsh_completion() {
    printf '%s\n' \
        '#compdef portforward' \
        '' \
        '_portforward() {' \
        '    _arguments '\''1:action:(apply edit rm completion help)'\''' \
        '}' \
        '' \
        '_portforward "$@"'
}

install_completion_file() {
    local mode="$1"
    local destination="$2"
    local writer="$3"
    local temporary_file

    temporary_file=$(mktemp) || error "Unable to create temporary completion file."
    if ! "$writer" > "$temporary_file"; then
        rm -f "$temporary_file"
        error "Unable to generate completion for $destination."
    fi
    if ! install -D -m "$mode" "$temporary_file" "$destination"; then
        rm -f "$temporary_file"
        error "Unable to install completion to $destination."
    fi
    rm -f "$temporary_file"
}

install_completion() {
    install_completion_file 0644 "$COMPLETION_FILE" write_bash_completion
    install_completion_file 0644 "$ZSH_COMPLETION_FILE" write_zsh_completion
    echo "SUCCESS: Bash completion installed to $COMPLETION_FILE."
    echo "SUCCESS: zsh completion installed to $ZSH_COMPLETION_FILE."
    echo "Run 'source $COMPLETION_FILE' in Bash or 'source ~/.zshrc' in zsh."
}

chain_exists() {
    local table="$1"
    local chain="$2"
    iptables -t "$table" -L "$chain" -n >/dev/null 2>&1
}

ensure_chain() {
    local table="$1"
    local chain="$2"

    if ! chain_exists "$table" "$chain"; then
        iptables -t "$table" -N "$chain" || error "Unable to create $table/$chain."
    fi
}

ensure_jump() {
    local table="$1"
    local parent="$2"
    local chain="$3"
    shift 3
    local match=("$@")

    if ! iptables -t "$table" -C "$parent" "${match[@]}" -j "$chain" >/dev/null 2>&1; then
        iptables -t "$table" -A "$parent" "${match[@]}" -j "$chain" || \
            error "Unable to add jump $table/$parent -> $chain."
    fi
}

remove_jump() {
    local table="$1"
    local parent="$2"
    local chain="$3"
    shift 3
    local match=("$@")

    while iptables -t "$table" -C "$parent" "${match[@]}" -j "$chain" >/dev/null 2>&1; do
        iptables -t "$table" -D "$parent" "${match[@]}" -j "$chain" || \
            error "Unable to remove jump $table/$parent -> $chain."
    done
}

flush_chain() {
    local table="$1"
    local chain="$2"
    chain_exists "$table" "$chain" || return 0
    iptables -t "$table" -F "$chain" || error "Unable to flush $table/$chain."
}

remove_chain() {
    local table="$1"
    local chain="$2"
    chain_exists "$table" "$chain" || return 0
    iptables -t "$table" -F "$chain" || error "Unable to flush $table/$chain."
    iptables -t "$table" -X "$chain" || error "Unable to delete $table/$chain."
}

remove_legacy_rules() {
    local table="$1"
    local parent="$2"
    local rules
    local rule
    local -a rule_args

    rules=$(iptables -t "$table" -S "$parent") || error "Unable to inspect $table/$parent."
    while IFS= read -r rule; do
        [[ "$rule" == *"--comment $TAG"* ]] || continue
        read -r -a rule_args <<< "$rule"
        rule_args[0]=-D
        iptables -t "$table" "${rule_args[@]}" || \
            error "Unable to remove legacy rule from $table/$parent."
    done <<< "$rules"
}

valid_ipv4() {
    local ip="$1"
    local octet
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        ((10#$octet <= 255)) || return 1
    done
}

validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Configuration file not found: $CONFIG_FILE"
    jq -e '
        type == "array" and
        all(.[];
            (.name | type == "string" and test("^[A-Za-z0-9_.:-]+$")) and
            (.proto | type == "string" and (. == "tcp" or . == "udp" or . == "tcp+udp")) and
            (.local_port | type == "number" and floor == . and . >= 1 and . <= 65535) and
            (.target_ip | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")) and
            (.target_port | type == "number" and floor == . and . >= 1 and . <= 65535)
        )
    ' "$CONFIG_FILE" >/dev/null || error "Invalid JSON or port forwarding entry in $CONFIG_FILE."

    local name proto local_port target_ip target_port
    local -a rule
    while IFS=$'\t' read -r name proto local_port target_ip target_port; do
        valid_ipv4 "$target_ip" || error "Invalid target_ip for $name: $target_ip"
        [[ "$proto" == "tcp" || "$proto" == "udp" || "$proto" == "tcp+udp" ]] || error "Invalid protocol for $name: $proto"
        rule=("$local_port" "$target_port")
        [[ "${rule[0]}" =~ ^[1-9][0-9]*$ && "${rule[0]}" -le 65535 ]] || error "Invalid local_port for $name."
        [[ "${rule[1]}" =~ ^[1-9][0-9]*$ && "${rule[1]}" -le 65535 ]] || error "Invalid target_port for $name."
    done < <(jq -r '.[] | [.name, .proto, .local_port, .target_ip, .target_port] | @tsv' "$CONFIG_FILE")
}

load_rules() {
    mapfile -t CONFIG_RULES < <(jq -r '.[] | [.name, .proto, .local_port, .target_ip, .target_port] | @tsv' "$CONFIG_FILE")
}

save_rules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        echo "STATUS: Saving active rules to netfilter-persistent..."
        netfilter-persistent save || error "netfilter-persistent save failed."
    else
        require_command iptables-save
        echo "STATUS: Saving active rules via iptables-save..."
        mkdir -p /etc/iptables || error "Unable to create /etc/iptables."
        iptables-save > /etc/iptables/rules.v4 || error "iptables-save persistence failed."
    fi
}

show_managed_chains() {
    echo "=== $DNAT_CHAIN ==="
    iptables -t nat -L "$DNAT_CHAIN" -n -v --line-numbers || error "Unable to list $DNAT_CHAIN."
    echo
    echo "=== $FORWARD_CHAIN ==="
    iptables -L "$FORWARD_CHAIN" -n -v --line-numbers || error "Unable to list $FORWARD_CHAIN."
    echo
    echo "=== $SNAT_CHAIN ==="
    iptables -t nat -L "$SNAT_CHAIN" -n -v --line-numbers || error "Unable to list $SNAT_CHAIN."
}

apply_rules() {
    require_command iptables
    require_command jq
    require_command iptables-save
    validate_config
    load_rules

    ensure_chain nat "$DNAT_CHAIN"
    ensure_chain filter "$FORWARD_CHAIN"
    ensure_chain nat "$SNAT_CHAIN"

    ensure_jump nat PREROUTING "$DNAT_CHAIN" -i "$EXT_IF"
    ensure_jump filter FORWARD "$FORWARD_CHAIN" -i "$EXT_IF" -o "$INT_IF"
    ensure_jump nat POSTROUTING "$SNAT_CHAIN" -o "$INT_IF"

    remove_legacy_rules nat PREROUTING
    remove_legacy_rules filter FORWARD
    remove_legacy_rules nat POSTROUTING
    flush_chain nat "$DNAT_CHAIN"
    flush_chain filter "$FORWARD_CHAIN"
    flush_chain nat "$SNAT_CHAIN"

    local name proto local_port target_ip target_port comment expanded_proto
    local -a protocols
    local -a rule
    for rule in "${CONFIG_RULES[@]}"; do
        IFS=$'\t' read -r name proto local_port target_ip target_port <<< "$rule"
        echo "Configuring [$name]: $local_port -> $proto://$target_ip:$target_port"

        if [[ "$proto" == "tcp+udp" ]]; then
            protocols=(tcp udp)
        else
            protocols=("$proto")
        fi

        for expanded_proto in "${protocols[@]}"; do
            comment="$TAG:$name:$expanded_proto"
            iptables -t nat -A "$DNAT_CHAIN" -i "$EXT_IF" -p "$expanded_proto" --dport "$local_port" \
                -j DNAT --to-destination "$target_ip:$target_port" \
                -m comment --comment "$comment" || error "Unable to add DNAT rule for $name ($expanded_proto)."

            iptables -A "$FORWARD_CHAIN" -i "$EXT_IF" -o "$INT_IF" -p "$expanded_proto" -d "$target_ip" --dport "$target_port" \
                -j ACCEPT -m comment --comment "$comment" || error "Unable to add FORWARD rule for $name ($expanded_proto)."

            iptables -t nat -A "$SNAT_CHAIN" -s 192.168.1.0/24 -o "$INT_IF" -p "$expanded_proto" -d "$target_ip" --dport "$target_port" \
                -j MASQUERADE -m comment --comment "$comment" || error "Unable to add SNAT rule for $name ($expanded_proto)."
        done
    done

    show_managed_chains
    save_rules
    echo "SUCCESS: All port forwarding rules synchronized."
}

remove_all_rules() {
    require_command iptables
    remove_jump nat PREROUTING "$DNAT_CHAIN" -i "$EXT_IF"
    remove_jump filter FORWARD "$FORWARD_CHAIN" -i "$EXT_IF" -o "$INT_IF"
    remove_jump nat POSTROUTING "$SNAT_CHAIN" -o "$INT_IF"
    remove_legacy_rules nat PREROUTING
    remove_legacy_rules filter FORWARD
    remove_legacy_rules nat POSTROUTING
    remove_chain nat "$DNAT_CHAIN"
    remove_chain filter "$FORWARD_CHAIN"
    remove_chain nat "$SNAT_CHAIN"
    save_rules
    echo "SUCCESS: All port forwarding rules have been removed."
}

require_root
ACTION=${1:-help}

case "$ACTION" in
    apply) apply_rules ;;
    edit) edit_config ;;
    rm) remove_all_rules ;;
    completion) install_completion ;;
    help|-h|--help) show_help ;;
    *) echo "ERROR: Unknown action: $ACTION" >&2; show_help; exit 1 ;;
esac
