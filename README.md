# Multi-Tier Application με Deployment Automation & AWS Migration

Ένα self-managed, multi-tier web application πάνω σε 4-VM lab (VirtualBox / Ubuntu 24.04), με πλήρη network segmentation, automated verified backups, zero-touch deployment automation (health checks + auto-rollback), database schema migrations, και **on-prem → cloud migration** της βάσης σε AWS RDS.

Χτισμένο **manual-first** — κάθε επίπεδο (networking, database, application, deployment, cloud) στήθηκε με το χέρι, χωρίς Ansible/Terraform, ώστε να κατανοηθεί σε βάθος τι κάνει η αυτοματοποίηση από κάτω.

---

## Πίνακας Περιεχομένων

- [Επισκόπηση](#επισκόπηση)
- [Τι δείχνει αυτό το project](#τι-δείχνει-αυτό-το-project)
- [Αρχιτεκτονική](#αρχιτεκτονική)
- [Βασικές σχεδιαστικές αποφάσεις](#βασικές-σχεδιαστικές-αποφάσεις)
- [Το stack ανά φάση](#το-stack-ανά-φάση)
  - [Phase 1 — Networking](#phase-1--networking)
  - [Phase 2 — Database & Backup](#phase-2--database--backup)
  - [Phase 3 — Application Stack](#phase-3--application-stack)
  - [Phase 4 — Deployment Automation](#phase-4--deployment-automation)
  - [Phase 5 — AWS Migration](#phase-5--aws-migration)
- [Δομή του repository](#δομή-του-repository)


---

## Επισκόπηση

Το project προσομοιώνει ένα ρεαλιστικό production περιβάλλον και τον κύκλο ζωής μιας εφαρμογής: από το network segmentation και το database hardening, μέχρι το automated deployment με rollback και τελικά τη μετανάστευση της βάσης στο cloud.

**Topology:** 4 VMs σε VirtualBox (Ubuntu 24.04), με δικτυακό διαχωρισμό σε ξεχωριστά segments/VLANs:

| VM | IP | VLAN/Segment | Ρόλος |
|----|-----|--------------|-------|
| `gw` | 10.0.10.1 / 10.0.20.1 / 10.0.30.1 | όλα (router) | Gateway, NAT, firewall, SSH entry |
| `app` | 10.0.10.10 | frontend | Nginx + Gunicorn + Flask |
| `db` | 10.0.20.10 | VLAN 20 | PostgreSQL 16 |
| `ops` | 10.0.30.10 | VLAN 30 | Management, backups, deploy, migrations |

Το `gw` έχει interface σε κάθε segment («τρία πρόσωπα, ένα μηχάνημα») και είναι ο μοναδικός δρόμος μεταξύ τους και προς το internet.

---

## Τι δείχνει αυτό το project

- **Network engineering:** VLAN segmentation (802.1Q), stateful firewall με nftables, NAT/masquerade, routing, default-deny πολιτική, least-privilege κανόνες ανά ροή.
- **Database administration:** PostgreSQL 16 setup, `pg_hba` host-based auth με /32 CIDR, role/grant management, automated backup με **test-restore verification**.
- **Application deployment:** Nginx reverse proxy → Gunicorn (WSGI) → Flask, systemd service management, environment-based configuration.
- **Deployment automation:** atomic symlink-based deploys, readiness health checks, **automatic rollback** σε αποτυχία, database schema migrations με pre-migration backup.
- **Cloud migration:** on-prem → AWS RDS migration (pg_dump → restore), security groups, IAM, cost-aware teardown automation.
- **Operational mindset:** verify scripts, reboot-persistence, idempotent automation, credential hygiene, systematic debugging.

---

## Αρχιτεκτονική

```
                          Internet
                             │
                        ┌────┴────┐
                        │   gw    │  NAT / firewall / router
                        │ (nftables)
                        └──┬───┬───┬──┘
             frontend │       │       │ VLAN 30 (mgmt)
            10.0.10.0/24│  VLAN 20   │ 10.0.30.0/24
                     │  10.0.20.0/24 │
                ┌────┴───┐  ┌───┴────┐  ┌──┴─────┐
                │  app   │  │   db   │  │  ops   │
                │ Nginx  │  │  PG16  │  │ deploy │
                │Gunicorn│──│        │──│ backup │
                │ Flask  │  │        │  │ verify │
                └────────┘  └────────┘  └────────┘

Request flow:  client → Nginx :80 → Gunicorn :8000 → Flask → PostgreSQL :5432

AWS Migration (Phase 5):
   ops ──pg_dump──> [dump.sql] ──restore──> AWS RDS PostgreSQL 16 (eu-central-1)
                                             (Security Group scoped στο public IP)
```

> Δείτε το `docs/architecture.svg` για το πλήρες διάγραμμα.

---

## Βασικές σχεδιαστικές αποφάσεις

**1. Manual-first, όχι IaC.**
Κάθε επίπεδο στήθηκε με το χέρι (netplan, nftables, PostgreSQL config, systemd units) αντί για Ansible/Terraform. Σκοπός: βαθιά κατανόηση του τι κάνει η αυτοματοποίηση από κάτω. Η αυτοματοποίηση χωρίς κατανόηση των primitives είναι εύθραυστη.

**2. Atomic deploys μέσω symlink.**
Κάθε version ζει σε δικό της φάκελο (`releases/X.Y/`), και ένα `current` symlink δείχνει στην ενεργή. Deploy = swap του symlink + restart. Rollback = swap πίσω. Η αλλαγή είναι ατομική και ακαριαία — δεν υπάρχει ενδιάμεση κατάσταση όπου η εφαρμογή είναι μισο-ενημερωμένη.

**3. Health check = readiness, όχι liveness.**
Το deploy health check χτυπάει το `/` endpoint (που κάνει query στη βάση), όχι το `/health` (που ελέγχει μόνο ότι το process ζει). Ένα liveness check θα περνούσε ένα deploy όπου το app τρέχει αλλά η database logic είναι σπασμένη. *Αυτό ανακαλύφθηκε στην πράξη* (βλ. Debugging Stories).

**4. Migration & deploy σε ξεχωριστά scripts.**
Το `migrate.sh` (schema changes) και το `deploy.sh` (code) είναι χωριστά, γιατί έχουν διαφορετικό risk profile: το code rollback είναι ακαριαίο (symlink), ενώ ένα destructive schema change είναι μη-αναστρέψιμο. Ανακατεύοντάς τα, κάθε deploy θα κουβαλούσε το ρίσκο του migration.

**5. Configuration από environment, όχι hardcoded.**
Τα DB credentials/host έρχονται από environment variables (μέσω του systemd unit), όχι από τον κώδικα. Αυτό απέδωσε άμεσα στο cloud migration: η αλλαγή από την τοπική βάση στο AWS RDS έγινε **χωρίς καμία αλλαγή κώδικα** — μόνο ένα env variable.

**6. Backup χωρίς test-restore είναι ψευδαίσθηση.**
Το `backup.sh` δεν παίρνει απλώς dump — δημιουργεί μια throwaway βάση, κάνει restore, μετράει τα rows, και τα συγκρίνει **δυναμικά** με την πηγή. Ένα backup που δεν έχει επαληθευτεί με restore δεν είναι backup.

---

## Το stack ανά φάση

### Phase 1 — Networking

Πλήρες network segmentation με VLANs και stateful firewall.

- **netplan** στο `gw`: static IPs + VLAN sub-interfaces (802.1Q) σε ένα φυσικό adapter (`enp0s9.20`, `enp0s9.30`).
- **IP forwarding** μέσω sysctl (`net.ipv4.ip_forward=1`, persistent).
- **nftables**: NAT/masquerade για outbound internet, default-deny σε `forward` και `input` chains, με ρητούς allow κανόνες ανά ροή (app→db:5432, ops→όλα:22, ops→app:80, established/related).
- **systemd ordering** για την αποφυγή boot race (το firewall πρέπει να φορτώσει *μετά* τα VLAN interfaces).
- **SSH key auth** (ed25519), passwordless από `ops` προς όλα.
- **`tests.sh`**: verify script με 10+ tests (allow *και* deny paths), PASS/FAIL, exit codes — regression test της υποδομής.

### Phase 2 — Database & Backup

- **PostgreSQL 16** στο `db`: `listen_addresses` στο network interface, `pg_hba.conf` με /32 host rules, role/database/schema grants.
- **`backup.sh`** (στο `ops`): timestamped pg_dump, size check, **automated test-restore verification** (createdb → restore → COUNT → σύγκριση με πηγή → dropdb, μέσω SSH με scoped NOPASSWD sudoers), by-count retention, logging.
- **systemd timer**: καθημερινό backup (03:00), `Persistent=true` για missed runs.

### Phase 3 — Application Stack

- **Flask** app: `/` (query στη βάση → JSON), `/health` (liveness, no DB), version σε μεταβλητή, DB credentials από environment.
- **Gunicorn** (WSGI, 2 workers, bind 127.0.0.1:8000) — production server αντί για τον Flask dev server.
- **Nginx** reverse proxy (:80 → :8000).
- Όλα ως **systemd services** με `enable` (reboot-persistent), `Restart=always` στο app (self-healing).

### Phase 4 — Deployment Automation

**`deploy.sh`** (orchestration από το `ops`):
- Validation (version δόθηκε; release υπάρχει;)
- Capture current version (για rollback)
- Atomic deploy: symlink swap + service restart μέσω SSH
- **Health check με retries** (readiness wait — καλύπτει το restart downtime window)
- **Auto-rollback** σε αποτυχία health check

```bash
# Health check με retry (readiness wait λόγω restart downtime)
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then
        HEALTHY=true; break
    fi
    sleep 2
done

if [ "$HEALTHY" != true ]; then
    echo "Health check FAILED — rolling back to $CURRENT"
    ssh "$APP_USER@$APP_HOST" "ln -sfn $APP_DIR/releases/$CURRENT $APP_DIR/current && sudo systemctl restart flaskapp"
    exit 1
fi
```

**`migrate.sh`** (schema changes, ξεχωριστά από deploy):
- Έλεγχος αν το release έχει `migration.sql`
- **Backup πρώτα** (το δίχτυ — abort αν αποτύχει)
- Εφαρμογή migration (idempotent, `ADD COLUMN IF NOT EXISTS`)

Σειρά χρήσης: `./migrate.sh X.Y` (schema) → `./deploy.sh X.Y` (code).

### Phase 5 — AWS Migration

Μετανάστευση της βάσης από on-prem σε **managed AWS RDS**.

- **IAM user** (όχι root), credentials μέσω `aws configure` (0600), region eu-central-1.
- **RDS PostgreSQL 16** (`db.t3.micro`, free tier), με **security group scoped στο public IP** (inbound 5432 μόνο από το IP μου, `/32` — ίδια λογική με το `pg_hba`).
- **Migration:** `pg_dump` από το on-prem → `CREATE DATABASE` στο RDS → restore στο RDS endpoint.
- **Επαλήθευση:** insert record *μόνο στο cloud* → το τοπικό app (repointed μέσω env variable) το διαβάζει → αποδεικνύει ότι το app→cloud μονοπάτι είναι ζωντανό.
- **Teardown automation** (`aws-teardown.sh`): σβήνει RDS (`--skip-final-snapshot`) και security group με σωστή σειρά dependencies, idempotent, re-fetching resource IDs (όχι εξάρτηση από session variables).

---

## Δομή του repository

```
multi-tier-app-aws-migration/
├── README.md
├── docs/
│   └── architecture.svg
├── scripts/
│   ├── tests.sh              # network verify (allow/deny paths)
│   ├── backup.sh            # dump + test-restore verify + retention
│   ├── deploy.sh            # atomic deploy + health check + rollback
│   ├── migrate.sh           # schema migration (backup-first)
│   └── aws-teardown.sh      # cost-aware AWS cleanup
├── app/
│   ├── app.py               # Flask app (env-based config)
│   └── requirements.txt
├── config/
│   ├── netplan/             # gw + node netplan configs
│   ├── nftables.conf        # firewall + NAT
│   └── pg_hba.conf          # (sanitized)
└── systemd/
    ├── flaskapp.service
    ├── backup.service
    └── backup.timer
```

> **Σημείωση ασφαλείας:** όλα τα secrets (passwords, AWS credentials, `.pgpass`, public IPs) έχουν αντικατασταθεί με placeholders. Τίποτα ευαίσθητο δεν βρίσκεται στο repository.

---

