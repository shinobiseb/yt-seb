// Small dependency-free helpers shared by the macOS shell command.
// Compatible with both Deno and Node.js.

const runtimeIsDeno = typeof globalThis.Deno !== "undefined";
const args = runtimeIsDeno ? Deno.args : process.argv.slice(2);

async function readText(path) {
  if (runtimeIsDeno) return await Deno.readTextFile(path);
  return await (await import("node:fs/promises")).readFile(path, "utf8");
}

const [operation, ...values] = args;

function utf8Length(value) {
  return new TextEncoder().encode(value).byteLength;
}

function safeComponent(rawValue, rawCharacterLimit = 70, rawByteLimit = 90) {
  const characterLimit = Math.max(1, Number(rawCharacterLimit || 70));
  const byteLimit = Math.max(1, Number(rawByteLimit || 90));
  let value = String(rawValue || "Unknown")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[. ]+$/g, "");
  let result = "";
  for (const character of [...value].slice(0, characterLimit)) {
    if (utf8Length(result + character) > byteLimit) break;
    result += character;
  }
  result = result.trim().replace(/[. ]+$/g, "");
  return result || "Unknown";
}

if (operation === "json-field") {
  const [path, field] = values;
  if (!path || !field) throw new Error("Usage: runtime-helper.mjs json-field <file> <field>");
  const parsed = JSON.parse(await readText(path));
  const value = parsed[field];
  if (value === undefined || value === null) DenoOrNodeWrite("");
  else if (Array.isArray(value)) DenoOrNodeWrite(value.join(", ").replace(/\s+/g, " ").trim());
  else DenoOrNodeWrite(String(value).replace(/\s+/g, " ").trim());
} else if (operation === "safe-component") {
  DenoOrNodeWrite(safeComponent(values[0], values[1], values[2]));
} else if (operation === "song-basename") {
  const [rawTitle, rawArtist, rawTempo, rawKey] = values;
  const title = safeComponent(rawTitle, 70, 90);
  const artist = safeComponent(rawArtist, 55, 70);
  const tempo = safeComponent(rawTempo, 4, 4);
  const key = safeComponent(rawKey, 20, 30);
  const basename = `${title} │ ${artist} │ ${tempo} BPM │ ${key} │ [YT-Seb]`;
  if (utf8Length(`${basename} (9999).mp3`) > 255) {
    throw new Error("The generated filename exceeds the macOS byte limit.");
  }
  DenoOrNodeWrite(basename);
} else {
  throw new Error("Unknown runtime-helper operation.");
}

function DenoOrNodeWrite(value) {
  if (runtimeIsDeno) {
    const bytes = new TextEncoder().encode(value);
    Deno.stdout.writeSync(bytes);
  } else {
    process.stdout.write(value);
  }
}
