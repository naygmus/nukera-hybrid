//! Strategy adaptation — the Linux port of the Windows `adapt` /
//! `adapt_sites` / `hybrid_build` / `hybrid_check` CLI features.
//!
//! The Windows build probes every strategy in its pool against a fixed set
//! of probe hosts, picks the winner, writes it into the engine config and
//! restarts the engine. This module does the same for the Linux nfqws
//! engine:
//!
//! * [`adapt_global`] — scan the whole strategy pool against the default
//!   probe targets, pick the best strategy, write it to
//!   `/etc/unblocker/strategy.conf` and restart `unblocker.service`.
//! * [`adapt_sites`] — per-site winners for user-selected hosts (written to
//!   `/etc/unblocker/sites/<host>.conf`, the same format `install-discover`
//!   uses) plus a winners map at `/etc/unblocker/adapt.sites.json`.
//! * [`hybrid_build`] — combine the current base strategy with per-site
//!   winners into one multi-profile nfqws strategy (`--new` groups with
//!   scoped hostlists), the Linux equivalent of the Windows hybrid builder.
//! * [`hybrid_check`] — re-probe every hybrid site with its winner and
//!   re-select/rebuild for the failing ones.
//!
//! Progress is published to `/tmp/unblocker-adapt.json` (world-readable)
//! so the GUI can poll it; cancellation is a flag file
//! `/tmp/unblocker-adapt.cancel` the GUI creates directly.
/// use std::io::Write as _;
use anyhow::Context;
use std::collections::BTreeMap;

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use serde::Serialize;

use crate::routing;
use crate::zapret::probe::{probe_strategy, ProbeResult};
use crate::zapret::{default_strategy_path, load_strategy_file, save_strategy_file};

/// Where the GUI polls adaptation progress.
pub const PROGRESS_FILE: &str = "/tmp/unblocker-adapt.json";
/// Flag file the GUI creates to cancel a running adaptation.
pub const CANCEL_FILE: &str = "/tmp/unblocker-adapt.cancel";
/// Per-site winners map (host → strategy name) for the GUI and hybrid.
pub const SITES_MAP_FILE: &str = "/etc/unblocker/adapt.sites.json";
/// Per-site winner configs, same format `install-discover` writes.
pub const SITES_DIR: &str = "/etc/unblocker/sites";

static CANCELLED: AtomicBool = AtomicBool::new(false);

#[derive(Serialize, Clone)]
struct ProbeOutcome {
    strategy: String,
    host: String,
    ok: bool,
    ms: u64,
    detail: String,
}

#[derive(Serialize, Clone)]
struct BestSoFar {
    strategy: String,
    score: usize,
    avg_ms: u64,
}

#[derive(Serialize)]
struct Progress {
    stage: &'static str, // running | done | cancelled | error
    current: usize,
    total: usize,
    strategy: String,
    host: String,
    best: Option<BestSoFar>,
    results: Vec<ProbeOutcome>,
    error: Option<String>,
}

impl Progress {
    fn new(total: usize) -> Self {
        Self {
            stage: "running",
            current: 0,
            total,
            strategy: String::new(),
            host: String::new(),
            best: None,
            results: Vec::new(),
            error: None,
        }
    }

    fn write(&self) {
        if let Ok(json) = serde_json::to_string(self) {
            let _ = std::fs::write(PROGRESS_FILE, json);
            // The GUI (running as the desktop user) must be able to read it.
            set_progress_mode();
        }
    }
}

fn set_progress_mode() {
    use std::os::unix::fs::PermissionsExt;
    if let Ok(md) = std::fs::metadata(PROGRESS_FILE) {
        let mut perms = md.permissions();
        perms.set_mode(0o644);
        let _ = std::fs::set_permissions(PROGRESS_FILE, perms);
    }
}

fn cancel_requested() -> bool {
    CANCELLED.load(Ordering::Relaxed) || Path::new(CANCEL_FILE).exists()
}

/// Request cancellation from inside the process (used by `adapt-stop`).
pub fn request_cancel() {
    CANCELLED.store(true, Ordering::Relaxed);
    let _ = std::fs::write(CANCEL_FILE, "1");
}

/// Remove the cancel flag (called when a new run starts).
fn clear_cancel() {
    CANCELLED.store(false, Ordering::Relaxed);
    let _ = std::fs::remove_file(CANCEL_FILE);
}

/// Discover the nfqws strategy pool, ordered best-first.
///
/// Mirrors `discover_strategy_pool` in the CLI: the runtime default
/// `/etc/unblocker/strategies/general-hostfakesplit.strat` first (known to
/// work), then the installed pool `/etc/unblocker/strategies/pool`, falling
/// back to the dev-tree copy `config/zapret/strategies/pool`. The
/// `byebyedpi` subpool is skipped — those are byedpi args, not nfqws.
pub fn strategy_pool() -> Vec<PathBuf> {
    let mut out: Vec<PathBuf> = Vec::new();

    let runtime_default = PathBuf::from("/etc/unblocker/strategies/general-hostfakesplit.strat");
    if runtime_default.exists() {
        out.push(runtime_default);
    }

    let mut pool_dirs: Vec<PathBuf> = vec![PathBuf::from("/etc/unblocker/strategies/pool")];
    if let Ok(dev) = std::env::var("NUKERA_POOL_DIR") {
        pool_dirs.insert(0, PathBuf::from(dev));
    }
    // Dev tree: crates/unblocker-core/src → repo root is three levels up.
    let dev_pool = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../config/zapret/strategies/pool");
    pool_dirs.push(dev_pool);

    for dir in &pool_dirs {
        if let Ok(read) = std::fs::read_dir(dir) {
            let mut files: Vec<PathBuf> = read
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.is_file()
                        && p.extension().map(|e| e == "strat").unwrap_or(false)
                        && !p
                            .parent()
                            .map(|d| d.file_name().map(|n| n == "byebyedpi").unwrap_or(false))
                            .unwrap_or(false)
                })
                .collect();
            files.sort();
            for f in files {
                let fname = f.file_name();
                if !out.iter().any(|p| p.file_name() == fname) {
                    out.push(f);
                }
            }
        }
    }
    out
}

fn strat_name(path: &Path) -> String {
    path.file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string())
}

/// Average of the successful probe times, in ms (u64::MAX when none).
fn avg_ms(results: &[ProbeResult]) -> u64 {
    let ok: Vec<u64> = results.iter().filter(|r| r.tcp_443).map(|r| r.ms).collect();
    if ok.is_empty() {
        u64::MAX
    } else {
        ok.iter().sum::<u64>() / ok.len() as u64
    }
}

/// Score a strategy: number of probe targets where TCP:443 connects.
fn score(results: &[ProbeResult]) -> usize {
    results.iter().filter(|r| r.tcp_443).count()
}

/// Write the winning strategy to `/etc/unblocker/strategy.conf` (keeping a
/// `.bak` of the previous one) and restart `unblocker.service`.
pub fn apply_strategy(args: &[String]) -> anyhow::Result<()> {
    let path = std::path::Path::new("/etc/unblocker/strategy.conf").to_path_buf();
    if path.exists() {
        let bak = path.with_extension("conf.bak");
        let _ = std::fs::copy(&path, &bak);
    }
    
    // Если strategy.conf — это ссылка на гибрид, удаляем её
    if path.is_symlink() {
        let _ = std::fs::remove_file(&path);
    }
    
    save_strategy_file(&path, args)?;
    restart_service()
}

pub fn restart_service() -> anyhow::Result<()> {
    // systemd is optional on lightweight distros (Puppy boots sysvinit):
    // fall back to the bundled sysv script; if neither exists, skip the
    // restart — the winner config is already written and the daemon applies
    // it at its next start.
    let systemd = std::path::Path::new("/run/systemd/system").exists();
    let st = if systemd {
        std::process::Command::new("systemctl")
            .args(["restart", "unblocker.service"])
            .status()?
    } else {
        // The installed init script wins; the bundled script is a fallback.
        let sysv = if std::path::Path::new("/etc/init.d/unblocker").exists() {
            "/etc/init.d/unblocker"
        } else {
            "/usr/local/share/unblocker/scripts/nukera-service.sh"
        };
        match std::path::Path::new(sysv).exists() {
            true => std::process::Command::new(sysv).arg("restart").status()?,
            false => {
                eprintln!("adapt: no systemd and no nukera-service.sh — restart skipped");
                return Ok(());
            }
        }
    };
    if st.success() {
        Ok(())
    } else {
        anyhow::bail!("service restart failed: {st}")
    }
}

/// Проверяет, запущен ли основной сервис (systemd или sysv).
pub fn is_service_running() -> bool {
    let systemd = std::path::Path::new("/run/systemd/system").exists();
    if systemd {
        std::process::Command::new("systemctl")
            .args(["is-active", "unblocker.service"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "active")
            .unwrap_or(false)
    } else {
        let sysv = if std::path::Path::new("/etc/init.d/unblocker").exists() {
            "/etc/init.d/unblocker"
        } else {
            "/usr/local/share/unblocker/scripts/nukera-service.sh"
        };
        if !std::path::Path::new(sysv).exists() {
            return false;
        }
        std::process::Command::new(sysv)
            .arg("status")
            .output()
            .map(|o| o.status.success() && !String::from_utf8_lossy(&o.stdout).contains("not running"))
            .unwrap_or(false)
    }
}

pub fn stop_service() -> anyhow::Result<()> {
    let systemd = std::path::Path::new("/run/systemd/system").exists();
    let st = if systemd {
        std::process::Command::new("systemctl")
            .args(["stop", "unblocker.service"])
            .status()?
    } else {
        let sysv = if std::path::Path::new("/etc/init.d/unblocker").exists() {
            "/etc/init.d/unblocker"
        } else {
            "/usr/local/share/unblocker/scripts/nukera-service.sh"
        };
        if std::path::Path::new(sysv).exists() {
            std::process::Command::new(sysv).arg("stop").status()?
        } else {
            return Ok(());
        }
    };
    if st.success() { Ok(()) } else { anyhow::bail!("service stop failed: {st}") }
}

pub fn start_service() -> anyhow::Result<()> {
    let systemd = std::path::Path::new("/run/systemd/system").exists();
    let st = if systemd {
        std::process::Command::new("systemctl")
            .args(["start", "unblocker.service"])
            .status()?
    } else {
        let sysv = if std::path::Path::new("/etc/init.d/unblocker").exists() {
            "/etc/init.d/unblocker"
        } else {
            "/usr/local/share/unblocker/scripts/nukera-service.sh"
        };
        if std::path::Path::new(sysv).exists() {
            std::process::Command::new(sysv).arg("start").status()?
        } else {
            return Ok(());
        }
    };
    if st.success() { Ok(()) } else { anyhow::bail!("service start failed: {st}") }
}

/// RAII-страж: останавливает сервис при создании и запускает при уничтожении,
/// если только не был явно отменён через `dismiss()`.
pub struct ServiceGuard {
    was_running: bool,
    dismissed: bool,
}

impl ServiceGuard {
    pub fn new() -> Self {
        let was_running = is_service_running();
        if was_running {
            let _ = stop_service();
            // Небольшая пауза, чтобы nfqws точно успел освободить очередь
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
        Self { was_running, dismissed: false }
    }

    /// Отменяет восстановление сервиса. Вызывайте, если сервис уже
    /// запущен заново (например, внутри `apply_strategy`).
    pub fn dismiss(&mut self) {
        self.dismissed = true;
    }
}

impl Drop for ServiceGuard {
    fn drop(&mut self) {
        if self.was_running && !self.dismissed {
            let _ = start_service();
        }
    }
}

/// Run the global adaptation: probe every strategy in the pool against the
/// default probe targets, pick the winner and apply it. Returns a short
/// human-readable summary; detailed progress goes to [`PROGRESS_FILE`].
pub async fn adapt_global() -> anyhow::Result<String> {
    clear_cancel();
    let pool = strategy_pool();
    anyhow::ensure!(!pool.is_empty(), "strategy pool is empty");
    let targets = crate::tuner::default_targets();
    let total = pool.len() * targets.len();
    let mut progress = Progress::new(total);
    let mut results: Vec<ProbeOutcome> = Vec::new();
    let mut best: Option<(String, Vec<String>, usize, u64)> = None;

    // Останавливаем основной обход
    let mut guard = ServiceGuard::new();

    for strat_path in &pool {
        let name = strat_name(strat_path);
        progress.strategy = name.clone();
        let args = match load_strategy_file(strat_path) {
            Ok(a) => a,
            Err(e) => {
                let err_msg = format!("unreadable: {e}");
                results.push(ProbeOutcome {
                    strategy: name.clone(),
                    host: "".into(),
                    ok: false,
                    ms: 0,
                    detail: err_msg.clone(),
                });
                progress.current += targets.len();
                progress.results = results.clone();
                progress.write();
                tracing::warn!("adapt_global: skipping {}: {}", name, err_msg);
                continue;
            }
        };
        
        let mut per_strat: Vec<ProbeResult> = Vec::new();
        for t in &targets {
            if cancel_requested() {
                progress.stage = "cancelled";
                progress.write();
                return Ok("cancelled".to_string());
            }
            progress.host = t.host.clone();
            progress.write();
            let r = probe_strategy(&args, &t.host, &t.url).await;
            let ok = r.tcp_443;
            results.push(ProbeOutcome {
                strategy: name.clone(),
                host: t.host.clone(),
                ok,
                ms: r.ms,
                detail: r.error.clone().unwrap_or_default(),
            });
            per_strat.push(r);
            progress.current += 1;
            let s = score(&per_strat);
            if s > 0 {
                let m = avg_ms(&per_strat);
                let better = match &best {
                    None => true,
                    Some((_, _, bs, bm)) => s > *bs || (s == *bs && m < *bm),
                };
                if better {
                    best = Some((name.clone(), args.clone(), s, m));
                    progress.best = Some(BestSoFar {
                        strategy: name.clone(),
                        score: s,
                        avg_ms: m,
                    });
                }
            }
            progress.results = results.clone();
            progress.write();
        }
    }

    match best {
        Some((name, args, s, m)) => {
            apply_strategy(&args)?;
            guard.dismiss();
            progress.stage = "done";
            progress.best = Some(BestSoFar {
                strategy: name.clone(),
                score: s,
                avg_ms: m,
            });
            progress.write();
            Ok(format!("best strategy: {name} ({s}/{}, avg {m} ms)", targets.len()))
        }
        None => {
            progress.stage = "error";
            progress.error = Some("no strategy could reach any probe target".into());
            progress.write();
            anyhow::bail!("no strategy could reach any probe target")
        }
    }
}
/// Run per-site adaptation for the given hosts: probe the pool for each
/// host, write the winner to `/etc/unblocker/sites/<host>.conf` (the same
/// format `install-discover` uses), record it in the winners map and make
/// sure the host is routed through the engine (routing custom domains).
pub async fn adapt_sites(hosts: &[String]) -> anyhow::Result<String> {
    clear_cancel();
    let pool = strategy_pool();
    anyhow::ensure!(!pool.is_empty(), "strategy pool is empty");
    anyhow::ensure!(!hosts.is_empty(), "no hosts given");
    let total = pool.len() * hosts.len();
    let mut progress = Progress::new(total);
    std::fs::create_dir_all(SITES_DIR).context("create per-site config dir")?;
    let mut winners = load_sites_map();
    let mut adapted = 0usize;

    // Страж остановит обход на время проб и запустит обратно при выходе
    let _guard = ServiceGuard::new();

    for host in hosts {
        let host = host.trim().to_lowercase();
        if host.is_empty() {
            continue;
        }
        let url = format!("https://{host}/");
        progress.host = host.clone();
        let mut best: Option<(PathBuf, usize, u64)> = None;
        for strat_path in &pool {
            if cancel_requested() {
                progress.stage = "cancelled";
                progress.write();
                return Ok("cancelled".to_string());
            }
            progress.strategy = strat_name(strat_path);
            progress.write();
            let args = match load_strategy_file(strat_path) {
                Ok(a) => a,
                Err(_) => continue,
            };
            let r = probe_strategy(&args, &host, &url).await;
            let s = usize::from(r.tcp_443);
            if s > 0 {
                let better = match &best {
                    None => true,
                    Some((_, bs, bm)) => s > *bs || (s == *bs && r.ms < *bm),
                };
                if better {
                    best = Some((strat_path.clone(), s, r.ms));
                }
            }
            progress.results.push(ProbeOutcome {
                strategy: strat_name(strat_path),
                host: host.clone(),
                ok: r.tcp_443,
                ms: r.ms,
                detail: r.error.unwrap_or_default(),
            });
            progress.current += 1;
            progress.write();
        }
        if let Some((path, _, _)) = best {
            let safe = sanitize_host(&host);
            std::fs::write(
                format!("{SITES_DIR}/{safe}.conf"),
                format!("{}\n", path.display()),
            )?;
            winners.insert(host.clone(), strat_name(&path));
            adapted += 1;
            
            let mut cfg = routing::RoutingConfig::load();
            if !cfg.custom_domains.iter().any(|d| d == &host) {
                cfg.custom_domains.push(host.clone());
                cfg.save()?;
                cfg.ensure_lists()?;
            }
        }
    }

    save_sites_map(&winners)?;
    progress.stage = "done";
    progress.write();
    
    Ok(format!("adapted {adapted} site(s)"))
}

/// Combine the current base strategy with the per-site winners into one
/// multi-profile nfqws strategy (Windows `hybrid_build`).
///
/// The base profile keeps its hostlists but excludes the hybrid sites, so
/// packets for those hosts fall through to the override profiles (`--new`
/// groups with scoped hostlists). Requires an nfqws that supports `--new`
/// and `--hostlist-exclude`; otherwise the build is refused with a clear
/// error instead of writing a strategy the engine cannot run.

pub fn hybrid_build(nfqws: &Path) -> anyhow::Result<String> {
    anyhow::ensure!(
        routing::nfqws_supports(nfqws, "--new"),
        "installed nfqws does not support --new; hybrid is unavailable"
    );
    anyhow::ensure!(
        routing::nfqws_supports(nfqws, "--hostlist-exclude"),
        "installed nfqws does not support --hostlist-exclude; hybrid is unavailable"
    );

    let winners = load_sites_map();
    anyhow::ensure!(
        !winners.is_empty(),
        "no per-site winners yet — run site adaptation first"
    );

    // 1. Всегда берем ЧИСТУЮ базовую стратегию (чтобы не накладывать гибрид на гибрид)
    let base_path = PathBuf::from("/etc/unblocker/strategies/general-hostfakesplit.strat");
    let base = load_strategy_file(&base_path).or_else(|_| {
        // Fallback, если дефолтного файла нет
        let p = default_strategy_path();
        load_strategy_file(&p)
    })?;
    let base_set: std::collections::BTreeSet<&String> = base.iter().collect();

    // Группируем сайты по их выигрышным стратегиям
    let mut groups: Vec<(PathBuf, Vec<String>)> = Vec::new();
    for (host, strat) in &winners {
        if let Some(path) = resolve_strat(strat) {
            match groups.iter_mut().find(|(p, _)| *p == path) {
                Some((_, hosts)) => hosts.push(host.clone()),
                None => groups.push((path, vec![host.clone()])),
            }
        }
    }

    let hl_dir = PathBuf::from("/etc/unblocker/hostlists");
    let _ = std::fs::create_dir_all(&hl_dir);

    let mut args = Vec::new();
    let mut overrides = 0usize;
    
    // 2. Собираем профили сайтов (они будут первыми)
    for (idx, (path, hosts)) in groups.iter().enumerate() {
        let strat_args = match load_strategy_file(path) {
            Ok(a) => a,
            Err(_) => continue,
        };
        
        let strat_set: std::collections::BTreeSet<&String> = strat_args.iter().collect();
        if strat_set == base_set {
            continue;
        }
        
        let hl = hl_dir.join(format!("hybrid-{idx}.sites"));
        std::fs::write(&hl, hosts.join("\n") + "\n")?;
        
        let hostlist_arg = format!("--hostlist={}", hl.display());
        
        if overrides > 0 {
            args.push("--new".into());
        }
        args.push(hostlist_arg.clone());

        for a in &strat_args {
            if a == "--new" {
                args.push("--new".into());
                args.push(hostlist_arg.clone());
            } else if a.starts_with("--hostlist") || a.starts_with("--qnum") {
                continue;
            } else {
                args.push(a.clone());
            }
        }
        overrides += 1;
    }

    if overrides == 0 {
        return Ok("all winners already match the base strategy — nothing to build".into());
    }

    // 3. Базовая стратегия в конце
    args.push("--new".into());
    args.extend(base);

    // 4. Создаем отдельный файл для гибрида
    let base_name = base_path.file_stem().unwrap_or_default().to_string_lossy();
    let hybrid_path = base_path.with_file_name(format!("{}_hybrid.conf", base_name));
    
    save_strategy_file(&hybrid_path, &args)?;
    
    // 5. Сохраняем ТЕКУЩЕЕ состояние strategy.conf (ссылку или файл)
    let conf_path = Path::new("/etc/unblocker/strategy.conf");
    let prev_path = Path::new("/etc/unblocker/strategy.conf.prev");
    let bak_path = Path::new("/etc/unblocker/strategy.conf.bak");

    if conf_path.is_symlink() {
        if let Ok(target) = std::fs::read_link(conf_path) {
            let _ = std::fs::write(prev_path, target.to_string_lossy().as_bytes());
        }
    } else if conf_path.exists() {
        let _ = std::fs::copy(conf_path, bak_path);
        let _ = std::fs::remove_file(prev_path);
    }

    // 6. Заменяем strategy.conf на ссылку, ведущую на гибрид
    let _ = std::fs::remove_file(conf_path);
    std::os::unix::fs::symlink(&hybrid_path, conf_path)
        .map_err(|e| anyhow::anyhow!("failed to symlink hybrid: {}", e))?;

    restart_service()?;
    Ok(format!(
        "hybrid built: {} (strategy.conf now links to it)",
        hybrid_path.display()
    ))
}
/// Re-check every hybrid site with its winner; re-select and rebuild for
/// the failing ones (Windows `hybrid_check`).
pub async fn hybrid_check(nfqws: &Path) -> anyhow::Result<String> {
    let mut winners = load_sites_map();
    anyhow::ensure!(
        !winners.is_empty(),
        "no per-site winners yet — run site adaptation first"
    );

    // Останавливаем основной обход на время проверки (RAII-страж)
    let mut guard = ServiceGuard::new();

    let mut progress = Progress::new(winners.len());
    let mut reselected = 0usize;
    let mut still_fine = 0usize;

    for (host, strat) in winners.clone() {
        progress.host = host.clone();
        progress.strategy = strat.clone();
        progress.current += 1;
        progress.write();

        if cancel_requested() {
            progress.stage = "cancelled";
            progress.write();
            return Ok("cancelled".into()); // guard запустит сервис при выходе
        }

        // 1) Проверяем текущего победителя для этого сайта
        let mut still_ok = false;
        if let Some(path) = resolve_strat(&strat) {
            if let Ok(args) = load_strategy_file(&path) {
                let r = probe_strategy(&args, &host, &format!("https://{host}/")).await;
                still_ok = r.tcp_443;
            }
        }
        if still_ok {
            still_fine += 1;
            continue;
        }

        // 2) Пересканируем пул стратегий для этого хоста
        let pool = strategy_pool();
        let mut best: Option<(PathBuf, u64)> = None;
        
        for strat_path in &pool {
            if cancel_requested() {
                progress.stage = "cancelled";
                progress.write();
                return Ok("cancelled".into()); // guard запустит сервис
            }
            if let Ok(args) = load_strategy_file(strat_path) {
                let r = probe_strategy(&args, &host, &format!("https://{host}/")).await;
                if r.tcp_443 && best.as_ref().map_or(true, |(_, bm)| r.ms < *bm) {
                    best = Some((strat_path.clone(), r.ms));
                }
            }
        }

        // 3) Если нашли рабочую стратегию — сохраняем её
        if let Some((path, _)) = best {
            let safe = sanitize_host(&host);
            std::fs::create_dir_all(SITES_DIR)?;
            std::fs::write(
                format!("{SITES_DIR}/{safe}.conf"),
                format!("{}\n", path.display()),
            )?;
            winners.insert(host.clone(), strat_name(&path));
            reselected += 1;
        }
    }

    save_sites_map(&winners)?;
    let mut msg = format!(
        "hybrid check done: {reselected} site(s) re-selected, {still_fine} still fine"
    );
    
    if reselected > 0 {
        // Если хоть один сайт был переназначен, собираем гибрид заново.
        // hybrid_build вызовет apply_strategy, который сам перезапустит сервис.
        hybrid_build(nfqws)?; 
        guard.dismiss(); // Отменяем авто-запуск стража, так как сервис уже перезапущен
        msg.push_str("; hybrid rebuilt");
    }
    
    // Если reselected == 0, то сервис запустится автоматически при выходе (Drop)
    Ok(msg)
}
/// Create the cancel flag file (used by `adapt-stop` and the GUI).
pub fn stop_adapt() {
    request_cancel();
}

// ---- sites map helpers --------------------------------------------------

fn sites_map_path() -> PathBuf {
    PathBuf::from(SITES_MAP_FILE)
}

pub fn load_sites_map() -> BTreeMap<String, String> {
    match std::fs::read_to_string(sites_map_path()) {
        Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
        Err(_) => BTreeMap::new(),
    }
}

fn save_sites_map(map: &BTreeMap<String, String>) -> anyhow::Result<()> {
    if let Some(parent) = sites_map_path().parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(map)?;
    std::fs::write(sites_map_path(), json)?;
    set_sites_map_mode();
    Ok(())
}

fn set_sites_map_mode() {
    use std::os::unix::fs::PermissionsExt;
    if let Ok(md) = std::fs::metadata(sites_map_path()) {
        let mut perms = md.permissions();
        perms.set_mode(0o644);
        let _ = std::fs::set_permissions(sites_map_path(), perms);
    }
}

fn resolve_strat(name: &str) -> Option<PathBuf> {
    strategy_pool().into_iter().find(|p| strat_name(p) == name)
}

//fn normalize_host(h: &str) -> String {
 //   h.trim()
  //      .trim_start_matches("http://")
  //      .trim_start_matches("https://")
  //      .trim_end_matches('/')
 //       .to_lowercase()
//}

fn sanitize_host(h: &str) -> String {
    h.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

/// Восстанавливает strategy.conf из предыдущего состояния (отменяет гибрид).
pub fn revert_hybrid() -> anyhow::Result<String> {
    let conf_path = Path::new("/etc/unblocker/strategy.conf");
    let prev_path = Path::new("/etc/unblocker/strategy.conf.prev");
    let bak_path = Path::new("/etc/unblocker/strategy.conf.bak");

    if !prev_path.exists() && !bak_path.exists() {
        anyhow::bail!("нет предыдущей стратегии для отката (файлы .prev или .bak не найдены)");
    }

    let _ = std::fs::remove_file(conf_path);

    // Восстанавливаем ссылку, если она была
    if prev_path.exists() {
        let target_str = std::fs::read_to_string(prev_path)?;
        let target_path = Path::new(target_str.trim());
        if target_path.exists() {
            std::os::unix::fs::symlink(target_path, conf_path)?;
            let _ = std::fs::remove_file(prev_path);
            let _ = std::fs::remove_file(bak_path);
            restart_service()?;
            return Ok(format!("Восстановлена ссылка на {}", target_path.display()));
        }
    }

    // Восстанавливаем обычный файл, если ссылки не было
    if bak_path.exists() {
        std::fs::copy(bak_path, conf_path)?;
        let _ = std::fs::remove_file(bak_path);
        let _ = std::fs::remove_file(prev_path);
        restart_service()?;
        return Ok("Восстановлена предыдущая стратегия из файла".to_string());
    }

    anyhow::bail!("не удалось найти цель для отката");
}