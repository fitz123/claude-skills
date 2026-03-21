---
name: ssl-troubleshoot
description: Diagnoses SSL/TLS certificate issues. Use when curl fails with SSL errors, certificate chain problems, or hostname mismatches.
allowed-tools:
  - Bash(curl:*)
  - Bash(openssl:*)
  - Bash(ssh:*)
  - Bash(python3:*)
  - Read(*)
---

# SSL/TLS Troubleshooting

Diagnose and fix SSL certificate issues including chain validation, SAN mismatches, and intermediate CA problems.

## Quick Diagnosis

```bash
# Fast check - shows HTTP code or SSL error
curl -sm 10 https://HOSTNAME/ -o /dev/null -w "HTTP: %{http_code}\n"
```

```bash
# Verbose SSL - shows full handshake (look for SSL/certificate/error lines)
curl -svm 10 https://HOSTNAME/ -o /tmp/ssl_body.txt
```

## Common Errors & Diagnosis

### Error: "no alternative certificate subject name matches"

Certificate missing the hostname in SANs.

```bash
# Save served certificate to file
openssl s_client -connect HOSTNAME:443 -servername HOSTNAME </dev/null > /tmp/ssl_cert.pem
```

```bash
# Check SANs in served certificate
openssl x509 -in /tmp/ssl_cert.pem -noout -text
```

Then use Grep tool to find "Subject Alternative Name" in the output.

**Fix:** Add missing hostname to certificate SANs via PKI role or template config.

### Error: "Invalid certificate chain"

Chain integrity issue - AKI/SKI mismatch between certificates.

```bash
# Get full chain to file
openssl s_client -connect HOSTNAME:443 -servername HOSTNAME -showcerts </dev/null > /tmp/ssl_chain.txt
```

Then use Grep tool to find `s:` and `i:` lines showing subject/issuer chain.

Run the chain analysis script (see Core Operations).

### Error: "certificate is not trusted"

Root CA not in trust store or chain incomplete.

```bash
# Verify chain with OpenSSL - look for "Verify return code" line
openssl s_client -connect HOSTNAME:443 -servername HOSTNAME </dev/null > /tmp/ssl_verify.txt
```

Then use Grep tool on `/tmp/ssl_verify.txt` for "Verify return".

If OpenSSL says OK but curl fails: macOS SecureTransport issue (uses Keychain, ignores --cacert).

## Core Operations

### Check Certificate Details

```bash
# Subject, issuer, dates
openssl s_client -connect HOSTNAME:443 -servername HOSTNAME </dev/null > /tmp/ssl_cert.pem
```

```bash
openssl x509 -in /tmp/ssl_cert.pem -noout -subject -issuer -dates
```

```bash
# Full certificate text (read with Read tool, use Grep for specific fields)
openssl x509 -in /tmp/ssl_cert.pem -noout -text > /tmp/ssl_cert_text.txt
```

### Verify Chain Integrity (AKI/SKI)

```bash
# Extract chain to file
openssl s_client -connect HOSTNAME:443 -servername HOSTNAME -showcerts </dev/null > /tmp/chain.pem
```

```bash
# Split and analyze (Python)
python3 << 'EOF'
import re, subprocess

with open('/tmp/chain.pem', 'r') as f:
    content = f.read()

certs = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', content, re.DOTALL)

for i, cert in enumerate(certs, 1):
    with open(f'/tmp/cert-{i}.pem', 'w') as f:
        f.write(cert + '\n')

for i in range(1, len(certs) + 1):
    print(f"=== Cert {i} ===")
    subprocess.run(['openssl', 'x509', '-in', f'/tmp/cert-{i}.pem', '-noout', '-subject', '-issuer'])

    result = subprocess.run(['openssl', 'x509', '-in', f'/tmp/cert-{i}.pem', '-noout', '-text'],
                          capture_output=True, text=True)
    for line in result.stdout.split('\n'):
        if 'Subject Key Identifier' in line or 'Authority Key Identifier' in line:
            idx = result.stdout.split('\n').index(line)
            print(line.strip())
            print(result.stdout.split('\n')[idx+1].strip())
    print()
EOF
```

**Valid chain:** Each cert's AKI must match the next cert's SKI.

### Verify Cert/Key Match

```bash
# On the server - modulus must match
openssl x509 -in /path/to/cert.pem -noout -modulus
```

```bash
openssl rsa -in /path/to/key.pem -noout -modulus
```

Compare the modulus output — they must be identical.

### Test from Remote Host

```bash
# Test from another server (rules out local trust store issues)
ssh REMOTE_HOST "curl -sm 10 https://HOSTNAME/ -o /dev/null -w 'HTTP: %{http_code}\n'"
```

```bash
# Verbose from remote (look for SSL/certificate/error lines)
ssh REMOTE_HOST "curl -svm 10 https://HOSTNAME/ -o /dev/null"
```

### Check Certificate Fingerprints

```bash
# Get cert from HOST1
openssl s_client -connect HOST1:443 -showcerts </dev/null > /tmp/cert_host1.pem
```

```bash
openssl x509 -in /tmp/cert_host1.pem -noout -fingerprint -sha256
```

```bash
# Get cert from HOST2
openssl s_client -connect HOST2:443 -showcerts </dev/null > /tmp/cert_host2.pem
```

```bash
openssl x509 -in /tmp/cert_host2.pem -noout -fingerprint -sha256
```

## Troubleshooting Workflow

```
SSL Issue Diagnosis:
- [ ] 1. Quick curl test (HTTP code or error)
- [ ] 2. Check SANs include the hostname
- [ ] 3. Verify chain with OpenSSL (Verify return code)
- [ ] 4. If OpenSSL OK but curl fails: test from Linux host
- [ ] 5. Compare chain to working service
- [ ] 6. Check AKI/SKI match through chain
- [ ] 7. Verify cert/key modulus match
```

## macOS SecureTransport Notes

macOS curl uses SecureTransport which:
- Ignores `--cacert` flag
- Uses Keychain for trust decisions
- May cache intermediate certificates

**Workaround:** Test from Linux host or use `openssl s_client` for verification.

## Quick Reference

| Check | Command |
|-------|---------|
| SANs | `openssl x509 -in cert.pem -noout -text` (grep for "Subject Alternative") |
| Dates | `openssl x509 -in cert.pem -noout -dates` |
| Issuer | `openssl x509 -in cert.pem -noout -issuer` |
| Chain | `openssl s_client -connect HOST:443 -showcerts` |
| Verify | `openssl s_client -connect HOST:443` (grep for "Verify return") |
| Fingerprint | `openssl x509 -in cert.pem -noout -fingerprint -sha256` |
