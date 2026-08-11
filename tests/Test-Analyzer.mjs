import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const rate = 11025;
const seconds = 24;
const samples = new Float32Array(rate * seconds);
const chord = [220.0, 261.6256, 329.6276]; // A minor: A3, C4, E4
let noiseState = 0x5eb12345;
function deterministicNoise() {
  noiseState = (Math.imul(noiseState, 1664525) + 1013904223) >>> 0;
  return (noiseState / 0xffffffff) * 2 - 1;
}
for (let i = 0; i < samples.length; i++) {
  const t = i / rate;
  let value = chord.reduce((sum, frequency) => sum + Math.sin(2 * Math.PI * frequency * t), 0) * 0.08;
  const beatPhase = t % 0.5; // 120 BPM
  if (beatPhase < 0.025) value += 0.75 * Math.exp(-beatPhase * 130) * deterministicNoise();
  samples[i] = Math.max(-1, Math.min(1, value));
}

const folder = await mkdtemp(join(tmpdir(), "yt-seb-analyzer-test-"));
const pcm = join(folder, "test.f32le");
try {
  await writeFile(pcm, new Uint8Array(samples.buffer));
  const analyzer = resolve("src", "analyze-audio.mjs");
  const output = execFileSync(process.execPath, [analyzer, pcm, String(rate)], { encoding: "utf8" });
  const result = JSON.parse(output);
  if (Math.abs(result.tempo - 120) > 4) {
    throw new Error(`Expected approximately 120 BPM; received ${result.tempo}`);
  }
  if (result.key !== "A minor") {
    throw new Error(`Expected A minor; received ${result.key}`);
  }
  console.log(`Analyzer test passed: ${result.tempo} BPM, ${result.key}`);
} finally {
  await rm(folder, { recursive: true, force: true });
}
