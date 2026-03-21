# Output Template (Russian)

## File naming

`~/Downloads/aws-invoice-{month}-{year}.md`

Example: `aws-invoice-december-2025.md`

---

## Template

```markdown
# Расходы AWS за {месяц} {год}

## Итого по командам

| Команда | USD |
|---------|-----|
| **crypto-team** | **${crypto_total}** |
| **china-team** | **${china_total}** |
| **common** | **${common_total}** |
| **website** | **${website_total}** |
| **inia-team** | **${inia_total}** |
| **ИТОГО** | **${grand_total}** |

---

## Детализация по командам

### crypto-team — ${crypto_total}

| Источник | USD |
|----------|-----|
| ordercapital org (N аккаунтов crypto-team) | $X,XXX.XX |
| ordercapital-hk org (N аккаунтов + dev) | $X,XXX.XX |
| ordercapital-hk master (Enterprise Support) | $X,XXX.XX |
| orca-legacy: Tokyo (ap-northeast-1) | $XX,XXX.XX |
| orca-legacy: Frankfurt (eu-central-1) | $XXX.XX |
| orca-legacy: VAT (пропорционально) | $X,XXX.XX |

### china-team — ${china_total}

| Источник | USD |
|----------|-----|
| orca-legacy: Hong Kong (ap-east-1) | $X,XXX.XX |
| orca-legacy: VAT (пропорционально) | $XXX.XX |

### common — ${common_total}

| Источник | USD |
|----------|-----|
| orca-legacy: Ireland (eu-west-1) | $XXX.XX |
| orca-legacy: Singapore (ap-southeast-1) — EBS Snapshots | $XXX.XX |
| orca-legacy: UAE (me-central-1) | $XX.XX |
| orca-legacy: Stockholm (eu-north-1) | $XX.XX |
| orca-legacy: Sao Paulo (sa-east-1) — EBS Volumes | $X.XX |
| orca-legacy: Mumbai (ap-south-1) — EBS Volumes | $X.XX |
| orca-legacy: Other regions | $X.XX |
| orca-legacy: VAT (пропорционально) | $XX.XX |

### website — ${website_total}

| Источник | USD |
|----------|-----|
| orca-website (584077517270) | $XX.XX |

### inia-team — ${inia_total}

| Источник | USD |
|----------|-----|
| orca-inia-team (226030784639) | $XX.XX |

---

## Инвойсы

| Инвойс | Аккаунт | USD |
|--------|---------|-----|
| {invoice_id} | ordercapital (517036156013) | $X,XXX.XX |
| {invoice_id} | ordercapital-hk (084928383109) | $X,XXX.XX |
| {invoice_id} | orca-legacy (583841195053) | $XX,XXX.XX |
| **ИТОГО** | | **${grand_total}** |
```

---

## Month Names (Russian)

| EN | RU |
|----|-----|
| January | январь |
| February | февраль |
| March | март |
| April | апрель |
| May | май |
| June | июнь |
| July | июль |
| August | август |
| September | сентябрь |
| October | октябрь |
| November | ноябрь |
| December | декабрь |
