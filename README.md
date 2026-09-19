# iptables-portforward

> Efficiently configure port forwarding from one machine to another.

A lightweight Bash-based tool for managing Linux `iptables` port forwarding rules through a simple configuration file.

## Features

- Configuration-based port forwarding
- Automatically synchronize `iptables` rules
- Prevent duplicate rules
- Uses dedicated `iptables` chains
- Safely removes rules managed by this tool
- Supports Bash and Zsh completion
- Designed to be safe to re-run

## Requirements

- Linux
- Bash
- `iptables`
- Root privileges

The tool is primarily designed for Linux systems using `iptables`.

## Installation

Clone the repository:

```bash
git clone https://github.com/USERNAME/iptables-portforward.git
cd iptables-portforward
```

Install the command:

```bash
sudo install -m 755 portforward /usr/local/bin/portforward
```

If the project provides an installation script, it can be used instead.

## Usage

```text
Usage: sudo portforward [action]
```

### Actions

| Action | Description |
|---|---|
| `apply` | Sync and apply rules from configuration |
| `edit` | Edit the configuration file; run `apply` afterwards |
| `rm` | Remove this tool's chains and jump rules |
| `completion` | Install Bash and Zsh tab completion |
| `help` | Display documentation |

### Examples

Apply the current configuration:

```bash
sudo portforward apply
```

Edit the port forwarding configuration:

```bash
sudo portforward edit
```

Remove the rules managed by this tool:

```bash
sudo portforward rm
```

Install shell completion:

```bash
sudo portforward completion
```

## Configuration

The port forwarding rules are stored in:

```text
/etc/port_forwards.json
```

The configuration defines how incoming traffic should be forwarded from one interface or machine to another.

A typical rule conceptually looks like:

```text
External Port
      │
      ▼
Input Interface
      │
      ▼
  iptables
      │
      ▼
Destination IP:Port
```

After modifying the configuration, run:

```bash
sudo portforward apply
```

## How It Works

The tool creates and manages dedicated `iptables` chains instead of directly modifying every rule in the main chains.

Conceptually:

```text
iptables
│
├── INPUT
│
├── OUTPUT
│
└── FORWARD
      │
      └── FORWARD_TOOL
             │
             ├── Port Forward Rule 1
             ├── Port Forward Rule 2
             └── Port Forward Rule 3
```

This makes the rules easier to identify, update, and remove.

The tool also checks whether jump rules already exist before adding them, preventing unnecessary duplication.

## Rule Management

The tool uses its own identifier/tag to distinguish rules managed by the application.

When applying a new configuration, legacy rules belonging to the tool can be removed before the new configuration is synchronized.

This allows the configuration file to act as the source of truth.

```text
Configuration
      │
      ▼
  Synchronize
      │
      ▼
 Remove old rules
      │
      ▼
 Add current rules
      │
      ▼
   iptables
```

## Files

| File | Description |
|---|---|
| `/etc/port_forwards.json` | Port forwarding configuration |
| `$COMPLETION_FILE` | Bash completion |
| `$ZSH_COMPLETION_FILE` | Zsh completion |

## Help

Run:

```bash
sudo portforward help
```

or simply:

```bash
sudo portforward
```

The default action is `help`.

## Design Goals

The project focuses on:

- Simple configuration
- Efficient rule synchronization
- Minimal rule duplication
- Easy maintenance
- Safe repeated execution
- Clear separation between managed and unmanaged `iptables` rules

## License

This project is open source. See [`LICENSE`](LICENSE) for details.
