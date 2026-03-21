---
name: aws-invoice-breakdown
description: Breaks down AWS invoices by team using Cost Explorer. Use when collecting monthly AWS costs or preparing team expense reports.
allowed-tools:
  - Bash(aws:*)
  - Read(*)
---

# AWS Invoice Breakdown

Analyzes AWS invoices and breaks down costs by team across two AWS Organizations.

## Quick Start

1. User provides invoice PDFs (or billing period)
2. Query Cost Explorer for both organizations
3. Map accounts/regions to teams
4. Distribute VAT proportionally
5. Output Russian markdown summary

## AWS Profiles

```bash
# ordercapital org (UAE)
AdministratorAccess-517036156013

# ordercapital-hk org (HK)
AdministratorAccess-084928383109
```

## Workflow

```
Task Progress:
- [ ] Query ordercapital org by linked account
- [ ] Query ordercapital-hk org by linked account
- [ ] Query orca-legacy (583841195053) by region
- [ ] Map all costs to teams using TEAM-MAPPING.md
- [ ] Distribute VAT proportionally
- [ ] List and download invoice PDFs for both orgs
- [ ] Verify totals match invoices
- [ ] Generate Russian markdown report
- [ ] Save to ~/Downloads/aws-invoice-{month}-{year}.md
```

## Cost Explorer Queries

### By Linked Account
```bash
aws ce get-cost-and-usage \
  --profile AdministratorAccess-517036156013 \
  --time-period Start=YYYY-MM-01,End=YYYY-MM-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT
```

### By Region (for orca-legacy)
```bash
aws ce get-cost-and-usage \
  --profile AdministratorAccess-084928383109 \
  --time-period Start=YYYY-MM-01,End=YYYY-MM-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter '{"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": ["583841195053"]}}' \
  --group-by Type=DIMENSION,Key=REGION
```

### By Service (to identify specific costs)
```bash
aws ce get-cost-and-usage \
  --profile AdministratorAccess-084928383109 \
  --time-period Start=YYYY-MM-01,End=YYYY-MM-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter '{"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": ["ACCOUNT_ID"]}}' \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Invoice PDF Download

### List invoices for a billing period
```bash
aws invoicing list-invoice-summaries \
  --profile AdministratorAccess-084928383109 \
  --selector ResourceType=ACCOUNT_ID,Value=084928383109 \
  --filter '{"BillingPeriod":{"Month":MM,"Year":YYYY}}' \
  --output json
```

### Download invoice PDF
```bash
URL=$(aws invoicing get-invoice-pdf \
  --invoice-id EUINAE26-XXXXX \
  --profile AdministratorAccess-084928383109 \
  --query 'InvoicePDF.DocumentUrl' --output text) \
&& curl -s -m 30 -o ~/Downloads/Invoice_EUINAE26_XXXXX.pdf "$URL"
```

Run for both orgs (084928383109 and 517036156013). Save PDFs to `~/Downloads/`.

## VAT Calculation

VAT appears as "NoRegion" in orca-legacy (~5%). Distribute proportionally:

```python
team_vat = total_vat * (team_pre_vat / total_pre_vat)
```

## Output Format

See [OUTPUT-TEMPLATE.md](OUTPUT-TEMPLATE.md) for Russian markdown template.

## Team Mapping Reference

See [TEAM-MAPPING.md](TEAM-MAPPING.md) for account and region to team assignments.

## Troubleshooting

### SSO Session Expired
```bash
aws sso login --profile AdministratorAccess-517036156013
aws sso login --profile AdministratorAccess-084928383109
```

### Totals Don't Match
- Check for rounding errors in VAT distribution
- Verify all linked accounts are included
- Check orca-legacy regional breakdown includes all regions
