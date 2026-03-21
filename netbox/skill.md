---
name: netbox
description: Manage IP addresses and network resources in NetBox. Use for IP reservations, checking availability, and network documentation before creating VMs or network resources.
allowed-tools:
  - Bash(curl:*)
  - Bash(jq:*)
  - Read(*)
  - Grep(*)
---

# NetBox IP Address Management Skill

This skill provides integration with NetBox for IP address management and network resource documentation.

## When This Skill Activates

This skill automatically activates when:
- Creating VMs that need IP addresses
- Reserving or checking IP availability
- Documenting network resources
- Looking up existing IP assignments

## Environment Setup

Required environment variables:
```bash
NETBOX_API_TOKEN=<your-token>
NETBOX_URL=https://netbox.ingress.infra.hel.k8s.ordercapital.com
```

## Authentication

**IMPORTANT**: When using curl with POST/PUT/DELETE requests, the `$NETBOX_API_TOKEN` variable may not expand correctly. Use the literal token value instead:

```bash
# GET requests - variable works
curl -s "$NETBOX_URL/api/..." -H "Authorization: Token $NETBOX_API_TOKEN"

# POST/PUT/DELETE - use literal token to avoid expansion issues
curl -s -X POST "$NETBOX_URL/api/..." \
  -H "Authorization: Token $NETBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'
```

## Core Operations

### 1. List IPs in a Subnet

```bash
# List all IPs in a /28 subnet
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?parent=62.112.217.80/28" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | \
  jq -r '.results[] | "\(.address) - \(.dns_name) - \(.description)"'

# With status
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?parent=62.112.217.80/28" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | \
  jq -r '.results[] | "\(.address) - \(.dns_name) - \(.status.value)"'
```

### 2. Check IP Availability

Before reserving an IP, always check which IPs are already used:

```bash
# Get all used IPs in range (sorted)
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?parent=62.112.217.80/28" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | \
  jq -r '.results[].address' | sort -t. -k4 -n
```

For a /28 subnet (62.112.217.80/28):
- Network: .80 (not usable)
- Usable range: .81 - .94
- Broadcast: .95 (not usable)
- Gateway is typically .81

### 3. Register New IP Address

```bash
# Reserve a new IP (use literal token)
curl -s -X POST "$NETBOX_URL/api/ipam/ip-addresses/" \
  -H "Authorization: Token <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "address": "62.112.217.94/28",
    "status": "active",
    "dns_name": "myhost.hel.vm.ordercapital.com",
    "description": "Description of the host"
  }' | jq .
```

**Response includes:**
- `id` - NetBox record ID (useful for updates)
- `address` - The registered IP with CIDR
- `dns_name` - FQDN for the host

### 4. Search for IP by Name

```bash
# Find IP by dns_name
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?dns_name__ic=amnezia" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | jq .

# Find by description
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?description__ic=vpn" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | jq .
```

### 5. Update Existing IP

```bash
# Update IP record by ID
curl -s -X PATCH "$NETBOX_URL/api/ipam/ip-addresses/<ID>/" \
  -H "Authorization: Token <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Updated description"
  }' | jq .
```

### 6. Delete IP Reservation

```bash
# Delete IP by ID
curl -s -X DELETE "$NETBOX_URL/api/ipam/ip-addresses/<ID>/" \
  -H "Authorization: Token <TOKEN>"
```

## Common Workflows

### VM Creation Workflow

1. **Check available IPs in target subnet:**
```bash
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?parent=62.112.217.80/28" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | \
  jq -r '.results[].address' | sort -t. -k4 -n
```

2. **Register the new IP:**
```bash
curl -s -X POST "$NETBOX_URL/api/ipam/ip-addresses/" \
  -H "Authorization: Token <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "address": "62.112.217.94/28",
    "status": "active",
    "dns_name": "newvm.hel.vm.ordercapital.com",
    "description": "Purpose of the VM"
  }' | jq .
```

3. **Create VM manifest with the reserved IP**

4. **Update bd ticket with NetBox reservation details**

### IP Audit Workflow

```bash
# Get all IPs with their assignments
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?limit=1000" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | \
  jq -r '.results[] | "\(.address)\t\(.dns_name)\t\(.description)"' | \
  column -t -s $'\t'
```

## API Reference

### Base URL
```
https://netbox.ingress.infra.hel.k8s.ordercapital.com/api/
```

### Key Endpoints

| Endpoint | Description |
|----------|-------------|
| `/api/ipam/ip-addresses/` | IP address management |
| `/api/ipam/prefixes/` | Subnet/prefix management |
| `/api/dcim/devices/` | Physical devices |
| `/api/virtualization/virtual-machines/` | VMs |

### Query Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `parent` | Filter by parent prefix | `?parent=62.112.217.80/28` |
| `dns_name__ic` | Case-insensitive contains | `?dns_name__ic=amnezia` |
| `description__ic` | Search in description | `?description__ic=vpn` |
| `status` | Filter by status | `?status=active` |
| `limit` | Results per page | `?limit=100` |

### Status Values

- `active` - IP is in use
- `reserved` - IP is reserved for future use
- `deprecated` - IP is deprecated
- `dhcp` - Assigned via DHCP

### Role Values (optional)

- `loopback` - Loopback address
- `secondary` - Secondary address
- `anycast` - Anycast address
- `vip` - Virtual IP (e.g., gateway)
- `vrrp` - VRRP address
- `hsrp` - HSRP address
- `glbp` - GLBP address
- `carp` - CARP address

## Best Practices

1. **Always check availability first** - Never assume an IP is free
2. **Use meaningful dns_name** - Follow pattern: `hostname.datacenter.vm.ordercapital.com`
3. **Add descriptions** - Document the purpose of each IP
4. **Update bd tickets** - Record NetBox reservation IDs in ticket comments
5. **Use active status** - For IPs that will be used immediately

## HEL Datacenter Specifics

### Public IP Ranges (VLAN 203)
- `62.112.217.80/28` - Public VMs (gateway: .81)

### Common Templates
- Ubuntu 24.04: vmid 10003
- Ubuntu 22.04: vmid 10002

### Standard VM DNS Pattern
```
<hostname>.hel.vm.ordercapital.com
```

## Troubleshooting

### Token not working
If you get "Invalid token header", ensure:
1. Token is valid: `echo "Length: ${#NETBOX_API_TOKEN}"`
2. For POST requests, use literal token instead of variable

### Empty results
Check the query parameters - NetBox returns empty results for invalid filters rather than errors.

### Permission denied
Verify your token has write permissions for POST/PUT/DELETE operations.
