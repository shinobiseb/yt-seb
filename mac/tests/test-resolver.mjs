import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolveSongMetadata } from "../resolve-song-metadata.mjs";

const cases = [
  {
    name: "native track and artist win",
    metadata: { track: "One More Time", artist: "Daft Punk", title: "Daft Punk - One More Time (Official Video)" },
    selectedTitle: "Daft Punk - One More Time (Official Video)",
    songTitle: "One More Time",
    artist: "Daft Punk",
  },
  {
    name: "title supplies artist even when track exists",
    metadata: { track: "One More Time", title: "Daft Punk - One More Time (Official Video)" },
    selectedTitle: "Daft Punk - One More Time (Official Video)",
    songTitle: "One More Time",
    artist: "Daft Punk",
  },
  {
    name: "plural artists are retained and unique",
    metadata: { track: "Under Pressure", artists: ["Queen", "David Bowie", "queen"], title: "Under Pressure (Official Video)" },
    songTitle: "Under Pressure",
    artist: "Queen, David Bowie",
  },
  {
    name: "plural creators fill artist gap",
    metadata: { track: "Leave the Door Open", creators: ["Bruno Mars", "Anderson .Paak", "Silk Sonic"] },
    songTitle: "Leave the Door Open",
    artist: "Bruno Mars, Anderson .Paak, Silk Sonic",
  },
  {
    name: "Omen result retains Donnie Trumpet",
    metadata: {
      track: "48 Laws",
      artist: "Omen",
      artists: ["Omen"],
      title: "Omen - 48 Laws ft. Donnie Trumpet",
      uploader: "OmenVEVO",
    },
    selectedTitle: "Omen - 48 Laws ft. Donnie Trumpet",
    songTitle: "48 Laws",
    artist: "Omen, Donnie Trumpet",
  },
  {
    name: "wrapped feature keeps following remix label",
    metadata: {
      track: "Song (feat. Guest) [Remix]",
      artist: "Base Artist",
      title: "Base Artist - Song (feat. Guest) [Remix]",
    },
    songTitle: "Song [Remix]",
    artist: "Base Artist, Guest",
  },
  {
    name: "terminal feature does not consume remix qualifier",
    metadata: { title: "Artist - Song feat. Guest (Remix)" },
    songTitle: "Song (Remix)",
    artist: "Artist, Guest",
  },
  {
    name: "featured artists deduplicate case-insensitively",
    metadata: { track: "48 Laws", artist: "Omen", title: "Omen - 48 Laws feat. omen" },
    songTitle: "48 Laws",
    artist: "Omen",
  },
  {
    name: "Topic channel suffix is removed",
    metadata: { track: "Fast Car", title: "Fast Car", channel: "Tracy Chapman - Topic" },
    songTitle: "Fast Car",
    artist: "Tracy Chapman",
  },
  {
    name: "Official Music channel suffix is removed",
    metadata: { track: "Song", channel: "Example Artist Official Music" },
    songTitle: "Song",
    artist: "Example Artist",
  },
  {
    name: "VEVO suffix is removed",
    metadata: { track: "Teardrop", uploader: "MassiveAttackVEVO" },
    songTitle: "Teardrop",
    artist: "MassiveAttack",
  },
  {
    name: "video decoration is removed",
    metadata: { title: "Fleetwood Mac – Dreams (Official Music Video)" },
    songTitle: "Dreams",
    artist: "Fleetwood Mac",
  },
  {
    name: "Stand by Me does not create a false artist",
    metadata: { title: "Stand by Me", channel: "Ben E. King" },
    songTitle: "Stand by Me",
    artist: "Ben E. King",
  },
  {
    name: "classical colon does not create a false artist",
    metadata: { title: "Symphony No. 5: I. Allegro", channel: "London Symphony Orchestra" },
    songTitle: "Symphony No. 5: I. Allegro",
    artist: "London Symphony Orchestra",
  },
  {
    name: "live colon prefix remains in title",
    metadata: { title: "Live: Comfortably Numb", channel: "Pink Floyd" },
    songTitle: "Live: Comfortably Numb",
    artist: "Pink Floyd",
  },
  {
    name: "selected title fills absent metadata title",
    metadata: { uploader: "Sade" },
    selectedTitle: "Sade - Smooth Operator (Official Video)",
    songTitle: "Smooth Operator",
    artist: "Sade",
  },
  {
    name: "unknown values are explicit",
    metadata: { title: "Orphan Song (Official Audio)", artist: "  ", channel: "  " },
    songTitle: "Orphan Song",
    artist: "Unknown Artist",
  },
];

for (const testCase of cases) {
  const result = resolveSongMetadata(testCase.metadata, testCase.selectedTitle);
  assert.equal(result.songTitle, testCase.songTitle, `[${testCase.name}] songTitle`);
  assert.equal(result.artist, testCase.artist, `[${testCase.name}] artist`);
}

const resolverPath = fileURLToPath(new URL("../resolve-song-metadata.mjs", import.meta.url));
const cliOutput = execFileSync(
  process.execPath,
  [resolverPath, "--selected-title", "Omen - 48 Laws ft. Donnie Trumpet"],
  {
    encoding: "utf8",
    input: JSON.stringify({ track: "48 Laws", artists: ["Omen"], title: "Omen - 48 Laws ft. Donnie Trumpet" }),
  },
);
assert.deepEqual(JSON.parse(cliOutput), {
  songTitle: "48 Laws",
  artist: "Omen, Donnie Trumpet",
  artistSource: "artists+featured",
});

console.log(`macOS resolver tests passed (${cases.length} library cases + CLI).`);
