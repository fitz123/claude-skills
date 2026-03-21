# Team Mapping Reference

## Teams

- **crypto-team** - Cryptocurrency trading infrastructure
- **china-team** - China/HK operations
- **website** - Public website
- **inia-team** - INIA project
- **steno-team** - Steno project
- **common** - Shared infrastructure, orphaned resources

---

## ordercapital org (517036156013)

| Account ID | Account Name | Team |
|------------|--------------|------|
| 584077517270 | orca-website | website |
| 226030784639 | orca-inia-team | inia-team |
| 543897291006 | orca-china-team | china-team |
| 717188665119 | orca-steno-team | steno-team |
| 159883943111 | orca-network | common |
| 517036156013 | ordercapital (master) | common |
| 568438991262 | orca-crypto-team-acchnt04 | crypto-team |
| 242441136136 | orca-crypto-team-acchnt02 | crypto-team |
| 295849062328 | orca-crypto-team-acchnt05 | crypto-team |
| 547381267195 | orca-crypto-team-acchnt13 | crypto-team |
| 642384808145 | orca-crypto-team-acchnt08 | crypto-team |
| 114035886913 | orca-crypto-team-acchnt09 | crypto-team |
| 837765878978 | orca-crypto-team-acchnt07 | crypto-team |
| 333428665647 | orca-crypto-team-acchnt06 | crypto-team |
| 903558039863 | orca-crypto-team-acchnt12 | crypto-team |
| 488340573752 | orca-crypto-team-acchnt03 | crypto-team |
| 843141405725 | orca-crypto-team-acchnt11 | crypto-team |
| 918033868888 | orca-crypto-team-acchnt10 | crypto-team |

**Rule:** Any account matching `orca-crypto-team-*` → crypto-team

---

## ordercapital-hk org (084928383109)

| Account ID | Account Name | Team | Notes |
|------------|--------------|------|-------|
| 084928383109 | ordercapital-hk (master) | crypto-team | Enterprise Support charged here |
| 583841195053 | orca-legacy | **BY REGION** | See region mapping below |
| 628913891171 | orca-crypto-team-dev | crypto-team | |
| 544109288671 | orca-crypto-team-acchnt01 | crypto-team | |
| 083314013498 | orca-crypto-team-acchnt04 | crypto-team | |
| 172982316382 | orca-crypto-team-acchnt05 | crypto-team | |
| 753093280313 | orca-crypto-team-acchnt03 | crypto-team | |
| 914392294944 | orca-crypto-team-acchnt02 | crypto-team | |

**Rule:** Any account matching `orca-crypto-team-*` → crypto-team

---

## orca-legacy Regional Breakdown (583841195053)

orca-legacy has no sub-accounts. Costs are mapped by AWS region.

| Region | Region Name | Team |
|--------|-------------|------|
| ap-northeast-1 | Tokyo | crypto-team |
| eu-central-1 | Frankfurt | crypto-team |
| ap-east-1 | Hong Kong | china-team |
| eu-west-1 | Ireland | common |
| me-central-1 | UAE | common |
| eu-north-1 | Stockholm | common |
| ap-southeast-1 | Singapore | common (orphaned EBS snapshots) |
| sa-east-1 | Sao Paulo | common (orphaned EBS volumes) |
| ap-south-1 | Mumbai | common (orphaned EBS volumes) |
| *other regions* | - | common |
| NoRegion | VAT (5%) | **distribute proportionally** |

---

## VAT Distribution Formula

```
crypto_vat = total_vat × (crypto_pre_vat / total_pre_vat)
china_vat = total_vat × (china_pre_vat / total_pre_vat)
common_vat = total_vat × (common_pre_vat / total_pre_vat)
```

Where `total_pre_vat = crypto_pre_vat + china_pre_vat + common_pre_vat`
