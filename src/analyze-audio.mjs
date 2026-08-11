// Local, dependency-free tempo and musical-key estimator for mono f32le PCM.
// It intentionally reports estimates: real recordings can have ambiguous keys,
// changing tempos, half-time/double-time interpretations, or noisy transients.

const runtimeIsDeno = typeof globalThis.Deno !== "undefined";
const args = runtimeIsDeno ? Deno.args : process.argv.slice(2);
if (args.length < 1) {
  throw new Error("Usage: analyze-audio.mjs <mono-f32le-file> [sample-rate]");
}

const inputPath = args[0];
const sampleRate = Number(args[1] || 11025);
const bytes = runtimeIsDeno
  ? await Deno.readFile(inputPath)
  : new Uint8Array(await (await import("node:fs/promises")).readFile(inputPath));

const usableBytes = bytes.byteLength - (bytes.byteLength % 4);
const view = new DataView(bytes.buffer, bytes.byteOffset, usableBytes);
const maximumSamples = Math.min(usableBytes / 4, sampleRate * 120);
const samples = new Float64Array(maximumSamples);
for (let i = 0; i < maximumSamples; i++) {
  const value = view.getFloat32(i * 4, true);
  samples[i] = Number.isFinite(value) ? value : 0;
}

if (samples.length < sampleRate * 5) {
  throw new Error("At least five seconds of audio are required for analysis.");
}

function estimateTempo(signal, rate) {
  const frameSize = 1024;
  const hop = 512;
  const frameCount = Math.floor((signal.length - frameSize) / hop);
  const energy = new Float64Array(frameCount);
  for (let frame = 0; frame < frameCount; frame++) {
    let sum = 0;
    const start = frame * hop;
    for (let i = 0; i < frameSize; i++) {
      const sample = signal[start + i];
      sum += sample * sample;
    }
    energy[frame] = Math.sqrt(sum / frameSize);
  }

  const onset = new Float64Array(frameCount);
  for (let i = 1; i < frameCount; i++) {
    const flux = Math.max(0, energy[i] - energy[i - 1]);
    let localMean = 0;
    const begin = Math.max(0, i - 16);
    for (let j = begin; j < i; j++) localMean += Math.max(0, energy[j] - (j ? energy[j - 1] : 0));
    localMean /= Math.max(1, i - begin);
    onset[i] = Math.max(0, flux - localMean * 0.45);
  }

  const minBpm = 60;
  const maxBpm = 200;
  const minLag = Math.max(1, Math.floor((60 * rate) / (hop * maxBpm)));
  const maxLag = Math.min(frameCount - 1, Math.ceil((60 * rate) / (hop * minBpm)));
  let bestLag = minLag;
  let bestScore = -Infinity;
  const scores = new Float64Array(maxLag + 1);
  for (let lag = minLag; lag <= maxLag; lag++) {
    let dot = 0;
    let left = 0;
    let right = 0;
    for (let i = lag; i < onset.length; i++) {
      dot += onset[i] * onset[i - lag];
      left += onset[i] * onset[i];
      right += onset[i - lag] * onset[i - lag];
    }
    const normalized = dot / Math.sqrt(Math.max(1e-18, left * right));
    const bpm = (60 * rate) / (hop * lag);
    const preference = 1 - Math.min(0.08, Math.abs(bpm - 120) / 2000);
    const score = normalized * preference;
    scores[lag] = score;
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  let refinedLag = bestLag;
  if (bestLag > minLag && bestLag < maxLag) {
    const left = scores[bestLag - 1];
    const center = scores[bestLag];
    const right = scores[bestLag + 1];
    const denominator = left - 2 * center + right;
    if (Math.abs(denominator) > 1e-12) {
      refinedLag += 0.5 * (left - right) / denominator;
    }
  }
  return Math.round((60 * rate) / (hop * refinedLag));
}

function fftMagnitudes(frame) {
  const n = frame.length;
  const real = new Float64Array(n);
  const imag = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const window = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (n - 1));
    real[i] = frame[i] * window;
  }
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      [real[i], real[j]] = [real[j], real[i]];
      [imag[i], imag[j]] = [imag[j], imag[i]];
    }
  }
  for (let length = 2; length <= n; length <<= 1) {
    const angle = (-2 * Math.PI) / length;
    const wLenReal = Math.cos(angle);
    const wLenImag = Math.sin(angle);
    for (let start = 0; start < n; start += length) {
      let wReal = 1;
      let wImag = 0;
      for (let offset = 0; offset < length / 2; offset++) {
        const even = start + offset;
        const odd = even + length / 2;
        const oddReal = real[odd] * wReal - imag[odd] * wImag;
        const oddImag = real[odd] * wImag + imag[odd] * wReal;
        real[odd] = real[even] - oddReal;
        imag[odd] = imag[even] - oddImag;
        real[even] += oddReal;
        imag[even] += oddImag;
        const nextReal = wReal * wLenReal - wImag * wLenImag;
        wImag = wReal * wLenImag + wImag * wLenReal;
        wReal = nextReal;
      }
    }
  }
  const magnitudes = new Float64Array(n / 2);
  for (let i = 0; i < magnitudes.length; i++) magnitudes[i] = Math.hypot(real[i], imag[i]);
  return magnitudes;
}

function estimateKey(signal, rate) {
  const fftSize = 4096;
  const hop = fftSize * 4;
  const chroma = new Float64Array(12);
  for (let start = 0; start + fftSize <= signal.length; start += hop) {
    const magnitudes = fftMagnitudes(signal.subarray(start, start + fftSize));
    for (let bin = 1; bin < magnitudes.length; bin++) {
      const frequency = (bin * rate) / fftSize;
      if (frequency < 55 || frequency > 2000) continue;
      const midi = Math.round(69 + 12 * Math.log2(frequency / 440));
      const pitchClass = ((midi % 12) + 12) % 12;
      chroma[pitchClass] += Math.sqrt(magnitudes[bin]) / Math.sqrt(frequency);
    }
  }

  const majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
  const minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];
  const names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  let best = { score: -Infinity, key: "Unknown" };
  for (let tonic = 0; tonic < 12; tonic++) {
    for (const [mode, profile] of [["major", majorProfile], ["minor", minorProfile]]) {
      let score = 0;
      let normA = 0;
      let normB = 0;
      for (let pitch = 0; pitch < 12; pitch++) {
        const expected = profile[(pitch - tonic + 12) % 12];
        score += chroma[pitch] * expected;
        normA += chroma[pitch] * chroma[pitch];
        normB += expected * expected;
      }
      score /= Math.sqrt(Math.max(1e-18, normA * normB));
      if (score > best.score) best = { score, key: `${names[tonic]} ${mode}` };
    }
  }
  return best.key;
}

const result = {
  tempo: estimateTempo(samples, sampleRate),
  key: estimateKey(samples, sampleRate),
  analyzedSeconds: Math.round((samples.length / sampleRate) * 10) / 10,
  method: "local-estimate"
};

console.log(JSON.stringify(result));
