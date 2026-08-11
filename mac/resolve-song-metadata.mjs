#!/usr/bin/env node

/**
 * Resolve yt-dlp metadata into a song title, artist credit, and source label.
 * This is a dependency-free Node.js/Deno port of src/Resolve-SongMetadata.ps1.
 */

function metadataText(value) {
  const values = (Array.isArray(value) ? value : [value])
    .filter((item) => item !== null && item !== undefined)
    .map((item) => String(item).trim())
    .filter(Boolean);
  return values.length ? values.join(", ") : null;
}

function removeVideoTitleDecoration(value) {
  if (value === null || value === undefined || !String(value).trim()) return null;
  const clean = String(value)
    .trim()
    .replace(
      /\s*[\[(](?:official\s+)?(?:music\s+)?(?:video|audio|lyric(?:s)?|visuali[sz]er)(?:\s+video)?[\])].*$/i,
      "",
    )
    .trim();
  return clean || null;
}

function splitArtistTitle(value) {
  const clean = removeVideoTitleDecoration(value);
  if (!clean) return null;

  // Only explicit, spaced separators are boundaries. Colons and "by" would
  // misparse titles such as "Symphony No. 5: Allegro" and "Stand by Me".
  const match = clean.match(/^\s*(.+?)\s+(?:-|–|—|\|)\s+(.+?)\s*$/i);
  if (!match) return null;
  const artist = match[1].trim();
  const title = match[2].trim();
  return artist && title ? { artist, title } : null;
}

function splitFeaturedArtistCredit(value) {
  const clean = removeVideoTitleDecoration(value);
  if (!clean) return null;

  const wrapped = clean.match(
    /^(.*?)\s*[\[(]\s*(?:feat(?:uring)?\.?|ft\.?)\s+([^\])]+?)\s*[\])]\s*(.*)$/i,
  );
  if (wrapped) {
    return {
      title: [wrapped[1].trim(), wrapped[3].trim()].filter(Boolean).join(" ").trim(),
      featured: wrapped[2].trim(),
    };
  }

  const terminal = clean.match(/^(.+?)\s+(?:feat(?:uring)?\.?|ft\.?)\s+(.+?)\s*$/i);
  if (!terminal) return { title: clean, featured: null };

  let title = terminal[1].trim();
  let featured = terminal[2].trim();
  const qualified = featured.match(
    /^(.+?)\s+([\[(](?:remix|mix|version|edit|remaster(?:ed)?|live|acoustic|radio\s+edit)[\])])$/i,
  );
  if (qualified) {
    featured = qualified[1].trim();
    title = `${title} ${qualified[2]}`;
  }
  return { title, featured };
}

function normalizeArtistName(value) {
  if (value === null || value === undefined || !String(value).trim()) return null;
  const clean = String(value)
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\s+-\s+Topic$/i, "")
    .trim()
    .replace(/VEVO$/i, "")
    .trim()
    .replace(/\s+Official(?:\s+(?:Artist|Music))?$/i, "")
    .trim();
  return clean || null;
}

function joinUniqueArtistValues(...values) {
  const names = [];
  const visit = (value) => {
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    const name = normalizeArtistName(value);
    if (name && !names.some((existing) => existing.toLowerCase() === name.toLowerCase())) {
      names.push(name);
    }
  };
  values.forEach(visit);
  return names.join(", ");
}

export function resolveSongMetadata(metadata, selectedTitle = null) {
  metadata = metadata && typeof metadata === "object" ? metadata : {};

  let rawTitle = metadataText(metadata.title);
  if (!rawTitle) rawTitle = metadataText(selectedTitle);

  let parsed = splitArtistTitle(rawTitle);
  if (!parsed && selectedTitle && selectedTitle !== rawTitle) {
    parsed = splitArtistTitle(selectedTitle);
  }

  const track = metadataText(metadata.track);
  const initialTitle = track || parsed?.title || removeVideoTitleDecoration(rawTitle);
  const primaryCredit = splitFeaturedArtistCredit(initialTitle);
  const parsedCredit = parsed ? splitFeaturedArtistCredit(parsed.title) : null;
  let songTitle = primaryCredit?.title || initialTitle || "Unknown Song";
  songTitle = removeVideoTitleDecoration(songTitle) || "Unknown Song";

  let artist = joinUniqueArtistValues(metadata.artists);
  let artistSource = "artists";
  if (!artist) {
    artist = joinUniqueArtistValues(metadata.artist);
    artistSource = "artist";
  }
  if (!artist) {
    artist = joinUniqueArtistValues(metadata.creators);
    artistSource = "creators";
  }
  if (!artist) {
    artist = joinUniqueArtistValues(metadata.creator);
    artistSource = "creator";
  }
  if (!artist && parsed) {
    artist = normalizeArtistName(parsed.artist) || "";
    artistSource = "title";
  }
  if (!artist) {
    artist = normalizeArtistName(metadataText(metadata.channel)) || "";
    artistSource = "channel";
  }
  if (!artist) {
    artist = normalizeArtistName(metadataText(metadata.uploader)) || "";
    artistSource = "uploader";
  }

  const featured = joinUniqueArtistValues(primaryCredit?.featured, parsedCredit?.featured);
  if (featured) {
    artist = joinUniqueArtistValues(artist, featured);
    if (!artistSource.endsWith("+featured")) artistSource += "+featured";
  }

  if (!artist) {
    artist = "Unknown Artist";
    artistSource = "fallback";
  }

  return { songTitle, artist, artistSource };
}

function runtimeArgs() {
  if (typeof Deno !== "undefined") return Deno.args;
  if (typeof process !== "undefined") return process.argv.slice(2);
  return [];
}

async function readStdin() {
  if (typeof Deno !== "undefined") return new Response(Deno.stdin.readable).text();
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function isMainModule() {
  if (typeof Deno !== "undefined") return import.meta.main;
  if (typeof process === "undefined" || !process.argv[1]) return false;
  const modulePath = decodeURIComponent(new URL(import.meta.url).pathname)
    .replace(/^\/([A-Za-z]:)/, "$1")
    .replace(/\\/g, "/");
  return modulePath === process.argv[1].replace(/\\/g, "/");
}

async function runCli() {
  const args = runtimeArgs();
  let selectedTitle = null;
  let inputJson = null;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--selected-title") selectedTitle = args[++index] ?? null;
    else if (arg === "--metadata-json") inputJson = args[++index] ?? null;
    else if (arg === "--help" || arg === "-h") {
      console.log(
        "Usage: resolve-song-metadata.mjs [--metadata-json JSON] [--selected-title TITLE]\n" +
          "If --metadata-json is omitted, read JSON from stdin. Input may be yt-dlp metadata\n" +
          "or {\"metadata\": {...}, \"selectedTitle\": \"...\"}. Output is JSON.",
      );
      return;
    } else throw new Error(`Unknown argument: ${arg}`);
  }

  if (inputJson === null) inputJson = await readStdin();
  if (!inputJson.trim()) throw new Error("No metadata JSON was provided.");
  const input = JSON.parse(inputJson);
  const wrapped = input && typeof input === "object" && "metadata" in input;
  const metadata = wrapped ? input.metadata : input;
  if (wrapped && selectedTitle === null) selectedTitle = input.selectedTitle ?? null;
  console.log(JSON.stringify(resolveSongMetadata(metadata, selectedTitle)));
}

if (isMainModule()) {
  runCli().catch((error) => {
    console.error(`resolve-song-metadata: ${error.message}`);
    if (typeof Deno !== "undefined") Deno.exit(1);
    else process.exitCode = 1;
  });
}
