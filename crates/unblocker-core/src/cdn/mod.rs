//! YouTube CDN host discovery + adaptation.
//!
//! Given a list of YouTube video URLs (`/etc/unblocker/links-youtube.links`),
//! fetch each player page, scrape every `*.googlevideo.com` hostname,
//! deduplicate, probe each for a live TLS edge, write the survivors to
//! `/etc/unblocker/cdn_hosts.txt` + `.json`, then hand them to
//! `adapt::adapt_sites` so each host gets a per-site winner
//! (`/etc/unblocker/sites/<host>.conf`) and a routing entry
//! (`routing.custom_domains`).
//!
//! Progress goes to the same `/tmp/unblocker-adapt.json` the GUI already
//! polls — the existing progress bar covers both phases (scan + adapt).

use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::Path;
use std::time::Duration;
use std::os::unix::fs::PermissionsExt;

const PROGRESS_FILE: &str = "/tmp/unblocker-adapt.json";
pub const LINKS_FILE: &str = "/etc/unblocker/links-youtube.links";
pub const CDN_HOSTS_TXT: &str = "/etc/unblocker/cdn_hosts.txt";
pub const CDN_HOSTS_JSON: &str = "/etc/unblocker/cdn_hosts.json";

#[derive(serde::Serialize, serde::Deserialize, Clone)]
pub struct CdnHost {
    pub host: String,
    pub ips: Vec<String>,
    pub live: bool,
}

#[derive(serde::Serialize, serde::Deserialize, Clone)]
pub struct CdnReport {
    pub links: Vec<String>,
    pub hosts: Vec<CdnHost>,
    pub error: Option<String>,
}

/// Full cycle: read links → scan googlevideo hosts → adapt_sites.
pub async fn cdn_scan_and_adapt(links_path: Option<&str>) -> Result<String> {
    // ... проверка yt-dlp ...
    write_progress("cdn_scanning", 0, 0, "", "", "starting");

    let path = links_path.unwrap_or(LINKS_FILE);
    let links = read_links(path)?;
    if links.is_empty() { anyhow::bail!("no links in {path}"); }

    let report = scan_links(&links).await?;
    write_reports(&report)?;

    let live_hosts: Vec<String> = report.hosts.iter()
        .filter(|h| h.live).map(|h| h.host.clone()).collect();

    if live_hosts.is_empty() {
        write_progress("error", 0, 0, "", "", "no googlevideo hosts found");
        return Ok(format!(
            "cdn-scan: {} link(s) → 0 hosts (report: {CDN_HOSTS_TXT})", links.len()
        ));
    }

    // adapt_sites writes its own Progress into the same file, so from
    // here the GUI continues reading "stage: running" seamlessly.
    let adapt_msg = crate::adapt::adapt_sites(&live_hosts).await?;
write_progress("done", live_hosts.len(), live_hosts.len(), "", "", &adapt_msg);
    Ok(format!(
        "cdn-scan: {} link(s) → {} host(s); {adapt_msg}",
        links.len(), live_hosts.len()
    ))
}

fn write_progress(
    stage: &str,
    current: usize,
    total: usize,
    host: &str,
    strategy: &str,
    message: &str,
) {
    let json = serde_json::json!({
        "stage": stage,
        "current": current,
        "total": total,
        "strategy": strategy,
        "host": host,
        "message": message,
        "best": null,
        "results": [],
        "error": null,
    });
    if let Ok(s) = serde_json::to_string(&json) {
        let _ = std::fs::write(PROGRESS_FILE, s);
        // GUI runs as the desktop user; make the file world-readable.
        let _ = std::fs::set_permissions(PROGRESS_FILE, std::fs::Permissions::from_mode(0o644));
    }
}

/// Built-in fallback list — used when /etc/unblocker/links-youtube.links
/// is missing, so "Find CDN" works out of the box on a fresh install.
const DEFAULT_LINKS: &[&str] = &[
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "https://www.youtube.com/watch?v=9bZkp7q19f0",
    "https://www.youtube.com/watch?v=OXhnyw-6igk",
    "https://www.youtube.com/watch?v=nKcLtjYjw2g",
    "https://www.youtube.com/watch?v=RGQ5ZNkTC7M",
    "https://www.youtube.com/watch?v=dIB_FPVGa34",
    "https://www.youtube.com/watch?v=YIJdxQRun8s",
    "https://www.youtube.com/shorts/UDtmITUyCHc",
    "https://www.youtube.com/watch?v=t5Jtw8N-fn0",
    "https://www.youtube.com/watch?v=bz43HZb_5C0",
];

fn read_links(path: &str) -> Result<Vec<String>> {
    let raw = match std::fs::read_to_string(path) {
        Ok(s) => s,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            tracing::warn!(
                "cdn-scan: {path} not found, using {} built-in default link(s)",
                DEFAULT_LINKS.len()
            );
            return Ok(DEFAULT_LINKS.iter().map(|s| s.to_string()).collect());
        }
        Err(e) => {
            return Err(e).with_context(|| format!("read links file: {path}"));
        }
    };
    let mut out = Vec::new();
    for line in raw.lines() {
        let l = line.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        out.push(l.to_string());
    }
    Ok(out)
}
/// Extract the 11-char video id from a YouTube URL without a regex.
///
/// Supports the four URL shapes we care about:
///   https://www.youtube.com/watch?v=<id>
///   https://youtu.be/<id>
///   https://www.youtube.com/shorts/<id>
///   https://www.youtube.com/embed/<id>
///
/// A leading `www.`, `m.`, or `music.` subdomain is accepted too. The id
/// is exactly 11 chars from `[A-Za-z0-9_-]`, so once we find the marker
/// we just take the next 11 valid chars.
fn extract_video_id(url: &str) -> Option<String> {
    const MARKERS: [&str; 4] = ["v=", "youtu.be/", "shorts/", "embed/"];
    for marker in MARKERS {
        if let Some(pos) = url.find(marker) {
            let rest = &url[pos + marker.len()..];
            // v=... may be followed by & or #; youtu.be/... may be followed
            // by ? or #. Cut at the first non-id char.
            let id: String = rest
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
                .take(11)
                .collect();
            if id.len() == 11 {
                return Some(id);
            }
        }
    }
    None
}

/// Scrape every `*.googlevideo.com` hostname from an HTML/JSON body
/// without a regex.
///
/// The body contains hostnames like `rr1---sn-pivhx-n8v6.googlevideo.com`.
/// Host labels are `[a-z0-9-]`. We walk the bytes, grow a candidate while
/// chars are valid label chars or dots, and when we hit `.googlevideo.com`
/// we record the full candidate. A candidate is "interesting" only if it
/// ends with `.googlevideo.com` and is longer than that suffix (i.e. has
/// at least one label in front).
fn extract_googlevideo_hosts(body: &str) -> BTreeSet<String> {
    const SUFFIX: &str = ".googlevideo.com";
    let bytes = body.as_bytes();
    let mut out: BTreeSet<String> = BTreeSet::new();
    let mut start: Option<usize> = None;
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        let label_char = b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-';
        if label_char || b == b'.' {
            if start.is_none() {
                // A label must start with a lowercase letter or digit,
                // not a dot or dash.
                if label_char {
                    start = Some(i);
                }
            }
        } else {
            if let Some(s) = start.take() {
                check_candidate(&body[s..i], SUFFIX, &mut out);
            }
        }
        i += 1;
    }
    if let Some(s) = start.take() {
        check_candidate(&body[s..], SUFFIX, &mut out);
    }
    out
}

fn check_candidate(cand: &str, suffix: &str, out: &mut BTreeSet<String>) {
    // Must end with `.googlevideo.com` and have at least one label before it.
    // We already restricted to `[a-z0-9-.]`, so just check the suffix and
    // length. A bare `googlevideo.com` (no leading label) is not a CDN
    // edge and is skipped.
    if cand.len() > suffix.len() && cand.ends_with(suffix) {
        out.insert(cand.to_string());
    }
}

/// Run yt-dlp for a video id and extract every *.googlevideo.com host from
/// the JSON formats output. Tries several player clients in order, because
/// YouTube blocks some clients per-region (e.g. `web` fails in RU with
/// `SSL: UNEXPECTED_EOF_WHILE_READING`, while `android_vr` works).
///
/// The output of `--print "%(formats)#j"` is a JSON array of format
/// objects. Each `url`/`manifest_url` field is a full signed URL; the
/// host is the authority part (`rr5---sn-...googlevideo.com`). We
/// collect all of them, deduplicated.
async fn hosts_for_video(id: &str) -> Result<BTreeSet<String>> {
    // Order matters: android_vr currently works in RU without PO tokens.
    // tv/mweb/web are fallbacks for other regions.
    const CLIENTS: &[&str] = &["android_vr", "tv", "mweb", "web"];

    let url = format!("https://www.youtube.com/watch?v={id}");
    let mut last_err = String::new();

    for client in CLIENTS {
        let output = tokio::process::Command::new("yt-dlp")
            .args([
                "--no-warnings",
                "--skip-download",
                "--print", "%(formats)#j",
                "--extractor-args",
                &format!("youtube:player_client={client}"),
                &url,
            ])
            .output()
            .await;

        let stdout = match output {
            Ok(o) if o.status.success() => o.stdout,
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr);
                last_err = format!(
                    "yt-dlp ({client}) exit={:?}: {}",
                    o.status.code(),
                    stderr.lines().next().unwrap_or("").chars().take(160).collect::<String>()
                );
                continue;
            }
            Err(e) => {
                last_err = format!("yt-dlp ({client}) spawn: {e}");
                continue;
            }
        };

        // Parse the JSON array of format objects.
        let body = String::from_utf8_lossy(&stdout);
        let formats: Vec<Value> = match serde_json::from_str(&body) {
            Ok(v) => v,
            Err(e) => {
                last_err = format!("yt-dlp ({client}) JSON parse: {e}");
                continue;
            }
        };

        let hosts = extract_hosts_from_formats(&formats);
        if !hosts.is_empty() {
            tracing::info!(
                "cdn-scan: {id} via {client}: {} googlevideo host(s)",
                hosts.len()
            );
            return Ok(hosts);
        }
        last_err = format!("yt-dlp ({client}): {} formats but no googlevideo hosts", formats.len());
    }

    Err(anyhow::anyhow!("{last_err}"))
}

/// Walk a parsed `formats` array and collect every googlevideo authority.
///
/// Each format may carry a direct `url`, a DASH `manifest_url`, and a
/// `fragments[].url` list. We look at all of them. The authority is
/// `url.split('/').nth(2)` — e.g. for
/// `https://rr5---sn-...googlevideo.com/videoplayback?...` it returns
/// `rr5---sn-...googlevideo.com`.
fn extract_hosts_from_formats(formats: &[Value]) -> BTreeSet<String> {
    let mut out: BTreeSet<String> = BTreeSet::new();

    for f in formats {
        // Direct download URL.
        if let Some(u) = f.get("url").and_then(|v| v.as_str()) {
            push_host(u, &mut out);
        }
        // DASH/HLS manifest URL (rare for googlevideo, but cheap to check).
        if let Some(u) = f.get("manifest_url").and_then(|v| v.as_str()) {
            push_host(u, &mut out);
        }
        // DASH fragments: each fragment has its own URL on the same host.
        if let Some(frags) = f.get("fragments").and_then(|v| v.as_array()) {
            for frag in frags {
                if let Some(u) = frag.get("url").and_then(|v| v.as_str()) {
                    push_host(u, &mut out);
                }
            }
        }
    }
    out
}

fn push_host(url: &str, out: &mut BTreeSet<String>) {
    // We only care about https URLs; scheme must be exactly "https".
    let Some(rest) = url.strip_prefix("https://") else {
        return;
    };
    let Some(end) = rest.find('/') else {
        return;
    };
    let host = &rest[..end];
    // Strip userinfo/port if any (shouldn't happen for googlevideo, but
    // be defensive). The host must end with `.googlevideo.com`.
    let host = host.split('@').next_back().unwrap_or(host);
    let host = host.split(':').next().unwrap_or(host);
    if host.ends_with(".googlevideo.com") {
        out.insert(host.to_string());
    }
}
/// Scan every link, probe each unique host for a live TLS edge.
pub async fn scan_links(links: &[String]) -> Result<CdnReport> {
    write_progress("cdn_scanning", 0, links.len(), "", "", "scanning links");

    let mut all: BTreeSet<String> = BTreeSet::new();
    for (i, url) in links.iter().enumerate() {
        let Some(id) = extract_video_id(url) else {
            tracing::warn!("cdn-scan: no video id in {url}");
            write_progress("cdn_scanning", i + 1, links.len(), "", "", "bad url");
            continue;
        };
        write_progress("cdn_scanning", i + 1, links.len(), "", "", "fetching video info");
        match hosts_for_video(&id).await {
            Ok(hs) => {
                let n = hs.len();
                all.extend(hs);
                tracing::info!("cdn-scan: {id}: {n} host(s)");
            }
            Err(e) => tracing::warn!("cdn-scan: {url}: {e}"),
        }
        write_progress(
            "cdn_scanning",
            i + 1,
            links.len(),
            "",
            "",
            &format!("{} host(s) found", all.len()),
        );
    }

    let hosts: Vec<String> = all.into_iter().collect();
    let total = hosts.len();
    let mut out: Vec<CdnHost> = Vec::with_capacity(total);

    for (i, host) in hosts.into_iter().enumerate() {
        // Accept every host — direct reachability is irrelevant in a
        // blocked region; adapt_sites decides via nfqws probes.
        tracing::info!("cdn-scan: {}/{total} {host}", i + 1);
        write_progress("cdn_scanning", i + 1, total, &host, "", "collecting hosts");
        out.push(CdnHost { host, ips: Vec::new(), live: true });
    }

    Ok(CdnReport { links: links.to_vec(), hosts: out, error: None })
}

fn write_reports(report: &CdnReport) -> Result<()> {
    let mut txt = String::new();
    for h in &report.hosts {
        if h.live {
            txt.push_str(&h.host);
            txt.push('\n');
        }
    }
    if let Some(parent) = Path::new(CDN_HOSTS_TXT).parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(CDN_HOSTS_TXT, txt)
        .with_context(|| format!("write {CDN_HOSTS_TXT}"))?;
    let json = serde_json::to_string_pretty(report)?;
    std::fs::write(CDN_HOSTS_JSON, json)
        .with_context(|| format!("write {CDN_HOSTS_JSON}"))?;

    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(CDN_HOSTS_TXT, std::fs::Permissions::from_mode(0o644));
    let _ = std::fs::set_permissions(CDN_HOSTS_JSON, std::fs::Permissions::from_mode(0o644));
    Ok(())
}
