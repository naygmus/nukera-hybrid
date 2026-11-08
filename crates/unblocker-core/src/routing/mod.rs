//! Routing configuration — the Linux port of the Windows build's routing
//! feature (Nukera-win/cli/nukera.py: routing.json + user/exclude lists).
//!
//! The user chooses which sites get DPI-bypass treatment:
//! - mode "all":     every site in the strategy's hostlists is processed;
//! - mode "custom":  only the enabled categories + user's custom domains;
//! - excludes:       domains that are never processed (both modes).
//!
//! State lives in /etc/unblocker/routing.json (written by root via the
//! CLI/helper, read by everyone). The generated hostlists live next to the
//! other hostlists in /etc/unblocker/hostlists/:
//!   nukera-user.sites    — enabled categories + custom domains (custom mode)
//!   nukera-exclude.sites — excluded domains
//!
//! The daemon and the enable path call `apply_to_args()` on the strategy
//! argv before spawning nfqws, so routing takes effect without editing
//! strategy files.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

pub const ROUTING_FILE: &str = "/etc/unblocker/routing.json";
pub const USER_LIST: &str = "/etc/unblocker/hostlists/nukera-user.sites";
pub const EXCLUDE_LIST: &str = "/etc/unblocker/hostlists/nukera-exclude.sites";

/// Routing categories, ported from the Windows build (Nukera-win
/// cli/nukera.py ROUTING_CATEGORIES). Each entry lists the domains that
/// belong to the category; nfqws hostlists match the domain and all its
/// subdomains, so plain domains are enough.
pub const CATEGORIES: &[(&str, &str, &[&str])] = &[
    (
        "youtube",
        "YouTube",
        &[
            "youtube.com",
            "youtu.be",
            "ytimg.com",
            "googlevideo.com",
            "gvt1.com",
            "ggpht.com",
            "yt3.ggpht.com",
            "i.ytimg.com",
            "youtube-nocookie.com",
            "youtubei.googleapis.com",
            "youtube.googleapis.com",
            "youtube-ui.l.google.com",
            "youtube-ui.l.googleusercontent.com",
            "youtubei.l.google.com",
            "play.google.com",
            "googleapis.com",
            "googleusercontent.com",
            "gstatic.com",
            "google.com",
            "googlevideo.com",
            "yt.be",
            "yt3.ggpht.com",
            "ytimg.l.google.com",
            "ytvid.com",
            "youtubekids.com",
            "nflxvideo.net",
        ],
    ),
    (
        "telegram",
        "Telegram Web",
        &[
            "telegram.org",
            "t.me",
            "telegram.me",
            "tdesktop.com",
            "telegra.ph",
            "telesco.pe",
            "tgram.io",
            "tg.dev",
            "tx.me",
            "telegram.dog",
            "telegram-cdn.org",
            "cdn-telegram.org",
            "teleg.run",
            "telegram.space",
        ],
    ),
    (
        "discord",
        "Discord",
        &[
            "discord.com",
            "discord.gg",
            "discordapp.com",
            "discordapp.net",
            "discord.media",
            "discordstatus.com",
            "discordcdn.com",
            "dis.gd",
        ],
    ),
    (
        "meta",
        "Meta (Facebook/Instagram)",
        &[
            "facebook.com",
            "instagram.com",
            "cdninstagram.com",
            "fbcdn.net",
            "fb.com",
            "messenger.com",
            "threads.net",
            "whatsapp.com",
            "whatsapp.net",
        ],
    ),
    (
        "github",
        "GitHub",
        &[
            "github.com",
            "github.io",
            "githubusercontent.com",
            "githubassets.com",
            "github.dev",
            "ghcr.io",
        ],
    ),
    (
        "google",
        "Google AI (Gemini)",
        &[
            "gemini.google.com",
            "aistudio.google.com",
            "generativelanguage.googleapis.com",
            "alkalimakersuite-pa.clients6.google.com",
            "ai.google.dev",
        ],
    ),
];

/// Category ids in a stable order for the GUI.
pub fn category_ids() -> Vec<String> {
    CATEGORIES.iter().map(|(id, _, _)| id.to_string()).collect()
}

pub fn category_label(id: &str) -> &str {
    CATEGORIES
        .iter()
        .find(|(cid, _, _)| *cid == id)
        .map(|(_, label, _)| *label)
        .unwrap_or(id)
}

fn category_domains(id: &str) -> &[&str] {
    CATEGORIES
        .iter()
        .find(|(cid, _, _)| *cid == id)
        .map(|(_, _, domains)| *domains)
        .unwrap_or(&[])
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingConfig {
    /// "all" (default) or "custom".
    #[serde(default = "default_mode")]
    pub mode: String,
    /// Enabled category ids (custom mode).
    #[serde(default)]
    pub categories: Vec<String>,
    /// User-added domains (custom mode).
    #[serde(default)]
    pub custom_domains: Vec<String>,
    /// Domains never processed (both modes).
    #[serde(default)]
    pub excludes: Vec<String>,
}

fn default_mode() -> String {
    "all".to_string()
}

impl Default for RoutingConfig {
    fn default() -> Self {
        Self {
            mode: default_mode(),
            categories: Vec::new(),
            custom_domains: Vec::new(),
            excludes: Vec::new(),
        }
    }
}

impl RoutingConfig {
    /// Load the routing config. Missing or unreadable file → default
    /// (all sites, no excludes) so a fresh install behaves like before.
    pub fn load() -> Self {
        match std::fs::read_to_string(ROUTING_FILE) {
            Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    pub fn save(&self) -> Result<()> {
        if let Some(parent) = Path::new(ROUTING_FILE).parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("create {}", parent.display()))?;
        }
        let body = serde_json::to_string_pretty(self)?;
        std::fs::write(ROUTING_FILE, body)
            .with_context(|| format!("write {ROUTING_FILE}"))?;
        // World-readable so the GUI (running as the desktop user) can read it.
        let _ = std::fs::set_permissions(
            ROUTING_FILE,
            std::os::unix::fs::PermissionsExt::from_mode(0o644),
        );
        Ok(())
    }

    /// The effective user domain list: enabled categories + custom domains,
    /// minus excludes. Deduplicated, lowercased.
    pub fn user_domains(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        let mut push = |d: &str| {
            let d = d.trim().to_lowercase();
            if !d.is_empty() && !out.contains(&d) {
                out.push(d);
            }
        };
        for cat in &self.categories {
            for d in category_domains(cat) {
                push(d);
            }
        }
        for d in &self.custom_domains {
            push(d);
        }
        let excludes: Vec<String> = self
            .excludes
            .iter()
            .map(|d| d.trim().to_lowercase())
            .filter(|d| !d.is_empty())
            .collect();
        out.retain(|d| !excludes.iter().any(|e| d == e || d.ends_with(&format!(".{e}"))));
        out
    }

    /// (Re)generate the routing hostlists from the config. Called by the
    /// daemon at startup and by `routing-set`, so the lists always match
    /// routing.json even if the GUI skipped a step.
    pub fn ensure_lists(&self) -> Result<()> {
        let hostlists_dir = Path::new(USER_LIST)
            .parent()
            .context("hostlists dir")?
            .to_path_buf();
        std::fs::create_dir_all(&hostlists_dir)
            .with_context(|| format!("create {}", hostlists_dir.display()))?;

        let excludes: Vec<String> = self
            .excludes
            .iter()
            .map(|d| d.trim().to_lowercase())
            .filter(|d| !d.is_empty())
            .collect();

        // Exclude list: written whenever there are excludes (works in both
        // modes); removed otherwise so nfqws never sees a stale file.
        if excludes.is_empty() {
            let _ = std::fs::remove_file(EXCLUDE_LIST);
        } else {
            let mut body = String::from("# Nukera routing excludes\n");
            for d in &excludes {
                body.push_str(d);
                body.push('\n');
            }
            std::fs::write(EXCLUDE_LIST, body)
                .with_context(|| format!("write {EXCLUDE_LIST}"))?;
            let _ = std::fs::set_permissions(
                EXCLUDE_LIST,
                std::os::unix::fs::PermissionsExt::from_mode(0o644),
            );
        }

        // User list: only meaningful in custom mode.
        if self.mode == "custom" {
            let mut body = String::from("# Nukera routing user list (custom mode)\n");
            for d in self.user_domains() {
                body.push_str(&d);
                body.push('\n');
            }
            std::fs::write(USER_LIST, body).with_context(|| format!("write {USER_LIST}"))?;
            let _ = std::fs::set_permissions(
                USER_LIST,
                std::os::unix::fs::PermissionsExt::from_mode(0o644),
            );
        } else {
            let _ = std::fs::remove_file(USER_LIST);
        }
        Ok(())
    }

    /// Adjust nfqws argv according to the routing config:
    /// - custom mode: replace every `--hostlist=<stock list>` with the
    ///   generated user list (only selected sites are processed);
    /// - excludes: append `--hostlist-exclude=<exclude list>` when the
    ///   engine supports the flag.
    pub fn apply_to_args(&self, args: &[String], nfqws_bin: &Path) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        let user_list = PathBuf::from(USER_LIST);
        let exclude_list = PathBuf::from(EXCLUDE_LIST);

        let custom = self.mode == "custom" && user_list.exists();
        let exclude = exclude_list.exists()
            && nfqws_supports(nfqws_bin, "--hostlist-exclude");

        let mut i = 0;
        while i < args.len() {
            let a = &args[i];
            if custom && a.starts_with("--hostlist=") {
                // Replace the stock hostlist with the routing user list.
                if !out.iter().any(|x| x.as_str() == format!("--hostlist={}", user_list.display())) {   //if !out.iter().any(|x| x == format!("--hostlist={}", user_list.display())) {
                    out.push(format!("--hostlist={}", user_list.display()));
                }
            } else {
                out.push(a.clone());
            }
            i += 1;
        }
        if exclude && !out.iter().any(|x| x.starts_with("--hostlist-exclude=")) {
            out.push(format!("--hostlist-exclude={}", exclude_list.display()));
        }
        out
    }
}

/// Check (and cache) whether the installed nfqws supports a flag, e.g.
/// `--hostlist-exclude` or `--new`. Older builds exit with an error on
/// unknown flags, so we must not blindly add them to the engine argv.
/*pub fn nfqws_supports(bin: &Path, flag: &str) -> bool {
    use std::sync::OnceLock;
    static CACHE: OnceLock<Vec<String>> = OnceLock::new();
    let help = CACHE.get_or_init(|| {
        std::process::Command::new(bin)
            .arg("--help")
            .output()
            .map(|o| {
                format!(
                    "{} {}",
                    String::from_utf8_lossy(&o.stdout),
                    String::from_utf8_lossy(&o.stderr)
                )
            })
            .unwrap_or_default()
    });
    help.contains(flag)
}*/
pub fn nfqws_supports(bin: &Path, flag: &str) -> bool {
    use std::sync::OnceLock;

    static CACHE: OnceLock<String> = OnceLock::new();

    let help = CACHE.get_or_init(|| {
        std::process::Command::new(bin)
            .arg("--help")
            .output()
            .map(|o| {
                format!(
                    "{}{}",
                    String::from_utf8_lossy(&o.stdout),
                    String::from_utf8_lossy(&o.stderr)
                )
            })
            .unwrap_or_default()
    });

    help.contains(flag)
}

/// Build nfqws args for the per-site winner profiles (Windows parity).
///
/// Each `/etc/unblocker/sites/<host>.conf` holds one strategy path; the site
/// gets its own `--new` profile with a scoped hostlist, and the base profile
/// excludes all per-site hosts so the overrides actually match (nfqws
/// applies the first matching profile). Returns an empty vec when the
/// installed nfqws lacks `--new` / `--hostlist-exclude` support.
pub fn per_site_args(nfqws_bin: &Path) -> Vec<String> {
    let dir = Path::new("/etc/unblocker/sites");
    let mut out: Vec<String> = Vec::new();
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return out,
    };
    if !nfqws_supports(nfqws_bin, "--new") || !nfqws_supports(nfqws_bin, "--hostlist-exclude") {
        eprintln!("per-site profiles skipped: nfqws lacks --new/--hostlist-exclude");
        return out;
    }
    let mut sites: Vec<(String, PathBuf)> = Vec::new();
    for e in entries.flatten() {
        let p = e.path();
        if p.extension().and_then(|s| s.to_str()) != Some("conf") {
            continue;
        }
        let host = p.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
        if !host.is_empty() {
            sites.push((host, p));
        }
    }
    sites.sort();
    if sites.is_empty() {
        return out;
    }
    let hl_dir = Path::new("/etc/unblocker/hostlists");
    let _ = std::fs::create_dir_all(hl_dir);
    
    for (idx, (host, conf)) in sites.iter().enumerate() {
        let strat_path = match std::fs::read_to_string(conf) {
            Ok(s) => s.trim().to_string(),
            Err(_) => continue,
        };
        if strat_path.is_empty() {
            continue;
        }
        let hl = hl_dir.join(format!("site-{idx}.sites"));
        if std::fs::write(&hl, format!("{host}\n")).is_err() {
            continue;
        }
        
        // ВАЖНО: если это первый профиль в цепочке (out пустой), 
        // не ставим --new, иначе nfqws выдаст ошибку.
        if !out.is_empty() {
            out.push("--new".into());
        }
        out.push(format!("--hostlist={}", hl.display()));
        
        // Загружаем флаги стратегии
        if let Ok(toks) = crate::zapret::load_strategy_file(std::path::Path::new(&strat_path)) {
            for a in toks {
                let skip = a.starts_with("--hostlist") || a.starts_with("--qnum") || a == "--new";
                if !skip {
                    out.push(a.to_string());
                }
            }
        }
    }
    
    // БОЛЬШЕ НЕ ДОБАВЛЯЕМ site-exclude.sites — сайты идут первыми, база их не перебьет.
    out
}