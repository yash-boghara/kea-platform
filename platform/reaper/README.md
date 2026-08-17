# Reaper

The safety net. ArgoCD prunes environments when a PR closes; the reaper catches
everything that path misses:

- PRs left open for weeks with a live environment nobody is using
- Namespaces orphaned when an Application was deleted but resources lingered
- Environments whose PR was closed while the cleanup workflow was failing

## Deletion criteria

A namespace labelled `kea.platform/kind=preview` is reaped when **any** holds:

1. Age exceeds its `kea.platform/ttl` annotation (default 24h)
2. Its PR is closed or merged (checked against the GitHub API)
3. No ingress traffic for `IDLE_HOURS` (default 12), per Prometheus

## Build it in this order

**Write dry-run mode first, and run it for a full week before enabling deletion.**
A reaper bug that removes a live namespace is a genuinely bad afternoon. If you
hit one anyway, write it up — `docs/postmortems/` is more valuable than a clean
record.

- [ ] `--dry-run` flag: log what would be deleted, delete nothing. Default true.
- [ ] Prometheus metrics: `kea_reaper_orphans_found`, `kea_reaper_deleted_total`,
      `kea_reaper_errors_total`, `kea_reaper_last_run_timestamp`
- [ ] Never reap a namespace lacking the `kea.platform/kind=preview` label — belt
      and braces against a selector bug reaching platform namespaces
- [ ] Refuse to run if the selector matches more than `MAX_DELETIONS` (default 10)
      in one pass. A run that wants to delete everything is a bug, not a busy week.
- [ ] Emit a summary to Slack, not just logs
- [ ] CronJob every 15 minutes

## Interview talking point

The three independent teardown paths — ArgoCD prune, the cleanup workflow, and
this — are the same defence-in-depth argument as the three policy layers, applied
to cost instead of security. Any one can fail without leaving you paying for it.
Being able to articulate *why* the redundancy exists is the point.
