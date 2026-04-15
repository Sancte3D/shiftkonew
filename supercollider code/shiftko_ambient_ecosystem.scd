/*
SHIFTKO Ambient Ecosystem (separate generative engine)
=====================================================
Design: "Creation vs. Control" — autonomes Klang-Ökosystem mit streng begrenzter Stochastik,
langsamen Zeitskalen und spektraler Trennung (8-Layer / virtueller Mixer).

Nicht gedacht als Ersatz fuer shiftko_ambient_mathematical.scd, sondern als klarer,
experimentierbarer Architektur-Prototyp.

Anforderungen (Kurz):
- Sparse / irregular timing (kein starres Raster): exponential waits, state-abhaengig
- Langsame Envelopes (Attack/Release gross)
- Gewichtete Zufallsentscheidungen (Pwrand / gewichtete Routine-Logik)
- Diskrete Zustaende mit langsamen, probabilistischen Uebergaengen
- Enge Tonhoehen-Menge (pentatonisch / offene Intervalle)
- Sub <100 Hz nur auf einem Layer, trocken; Mid/High getrennt; Rhythmus gehocht
- Parameter-Inertia: Lag / VarLag / langsame Targets
- Mikro-Variation: Detune, Timing-Jitter

Start: gesamten Block auswaehlen und ausfuehren.
Stop: ~ecoStop.() oder Cmd-.
*/

(
s.quit;
Server.default = s = Server.local;
s.options.numInputBusChannels = 0;
s.options.numOutputBusChannels = 2;
s.options.sampleRate = 44100;
s.options.blockSize = 512;
s.options.memSize = 262144 * 2;

s.waitForBoot {

	// --- Groups & Buses (16ch = 8x stereo interleaved) ---
	~ecoSrcGroup = Group.head(s);
	~ecoFxGroup = Group.after(~ecoSrcGroup);

	~ecoLayerHub = Bus.audio(s, 16);
	~ecoRevSend = Bus.audio(s, 2);
	~ecoOut = 0;

	// Layer indices: stereo pair i uses channels base + i*2
	~ecoLayerBase = { |i| ~ecoLayerHub.index + (i * 2) };

	// --- SynthDefs ---

	// 0: Sub — nur tief, minimal Bewegung, trocken (kein Hall auf diesem Layer im Mixer)
	SynthDef(\ecoSub, {
		arg out=0, freq=55, amp=0.28, gate=1, glide=6.0, driftAmt=0.004;
		var f, drift, sig, env;
		drift = LFNoise2.kr(0.02).range(1 - driftAmt, 1 + driftAmt);
		f = Lag.kr(freq.clip(28, 90), glide);
		sig = SinOsc.ar(f * drift);
		sig = sig + (SinOsc.ar(f * 2 * drift, 0, 0.04));
		sig = tanh(sig * 1.15);
		sig = LPF.ar(sig, 110);
		env = Lag.kr(gate, 2.0);
		Out.ar(out, [sig, sig] * amp * env);
	}).add;

	// 1–2: Mid Pads — lange ASR, pentatonische Obertoene
	SynthDef(\ecoPadVoice, {
		arg out=0, freq=220, amp=0.1, atk=3.5, rel=28, pan=0, detuneCents=6.0;
		var env, dt, a, b, sig;
		dt = 2 ** (detuneCents / 1200 * LFNoise2.kr(0.04).range(-1, 1));
		a = SinOsc.ar(freq * dt);
		b = SinOsc.ar(freq * 1.002 * dt);
		sig = Mix([a, b]) * 0.5;
		sig = RLPF.ar(sig, (freq * 6).clip(400, 7000), 0.35);
		env = EnvGen.kr(Env([0, 1, 0], [atk, rel], [2, -3]), doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp, pan));
	}).add;

	// 3–4: Texture / Air (Bandpass noise)
	SynthDef(\ecoAir, {
		arg out=0, amp=0.06, gate=1, center=4200, rq=0.35;
		var n, f, sig, env;
		f = Lag.kr(center, 5.0);
		n = PinkNoise.ar(0.5) + (BrownNoise.ar(0.15));
		sig = BPF.ar(n, f * LFNoise1.kr(0.03).range(0.92, 1.08), rq);
		sig = HPF.ar(sig, 900);
		env = Lag.kr(gate, 3.0);
		Out.ar(out, [sig, sig] * amp * env);
	}).add;

	// 5–6: Sparse „rhythm as texture“ — weiches Rausch-Impuls, kein transient-scharfer Break
	SynthDef(\ecoRhythmGhost, {
		arg out=0, amp=0.07, atk=0.4, rel=2.5, hpf=110, lpf=2400, pan=0;
		var imp, sig, env;
		imp = PinkNoise.ar(1) * EnvGen.kr(Env.perc(atk, 0.02, 1, -3), doneAction: 0);
		sig = imp + (BPF.ar(WhiteNoise.ar(0.6), lpf * 0.5, 0.5) * 0.3);
		sig = HPF.ar(sig, hpf);
		sig = LPF.ar(sig, lpf);
		env = EnvGen.kr(Env([0, 1, 0], [atk, rel], [3, -4]), doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp, pan));
	}).add;

	// 7: optional FX return placeholder (unused by default — reserved for future send FX)
	SynthDef(\ecoSilence, {
		arg out=0;
		Out.ar(out, Silent.ar(2));
	}).add;

	// Master: 8 stereo layers (16ch interleaved) — per-channel gain, spectral HPF, reverb send.
	// Layer 0 = Sub: dry in sum; reverb send index 0 should stay 0 (sub stays dry).
	SynthDef(\ecoMaster8, {
		arg layerBase=0, out=0, dry=0.88, revAmt=0.42;
		var inter, drySig, revIn, wet;
		var g = Lag.kr(\gain8.kr(0.5 ! 8), 0.8);
		var sv = Lag.kr(\send8.kr(0.18 ! 8), 1.0);
		var hp = [25, 130, 130, 400, 950, 950, 100, 500];
		inter = In.ar(layerBase, 16);
		drySig = [0, 0];
		revIn = [0, 0];
		(0..7).do { |i|
			var lo = i * 2;
			var x = HPF.ar(inter[lo], hp[i]);
			var y = HPF.ar(inter[lo + 1], hp[i]);
			var gg = g[i];
			var svl = sv[i] * (if(i == 0) { 0.0 } { 1.0 });
			drySig = [drySig[0] + (x * gg), drySig[1] + (y * gg)];
			revIn = [revIn[0] + (x * gg * svl), revIn[1] + (y * gg * svl)];
		};
		wet = FreeVerb2.ar(revIn[0], revIn[1], mix: 0.55, room: 0.92, damp: 0.5);
		wet = [HPF.ar(wet[0], 200), HPF.ar(wet[1], 200)];
		Out.ar(out, Limiter.ar((drySig * dry) + (wet * revAmt), 0.95, 0.02));
	}).add;

	s.sync;

	// --- Runtime state ---
	~ecoStates = [\dormant, \sparse, \active, \decaying];
	~ecoState = \sparse;
	~ecoStateWeights = (
		dormant:  [0.55, 0.25, 0.12, 0.08],
		sparse:   [0.15, 0.45, 0.28, 0.12],
		active:   [0.10, 0.35, 0.35, 0.20],
		decaying: [0.35, 0.30, 0.15, 0.20]
	);

	~ecoRootHz = 64.midicps;
	~ecoTargetRoot = 64;
	~ecoHarmClock = 0.0;

	// Pentatonische Verhaeltnisse (rein genug, keine kleinen Sekunden)
	~ecoRatios = [1.0, 1.125, 1.25, 1.5, 1.6875, 2.0];
	~ecoRatioWeights = [0.34, 0.12, 0.22, 0.18, 0.08, 0.06];

	~ecoNextWait = {
		var st = ~ecoState;
		var lo, hi;
		#lo, hi = switch(st,
			\dormant, { [18.0, 48.0] },
			\sparse, { [6.0, 22.0] },
			\active, { [2.0, 12.0] },
			\decaying, { [10.0, 32.0] },
			{ [8.0, 24.0] }
		);
		exprand(lo, hi)
	};

	~ecoStepState = {
		var w = ~ecoStateWeights[~ecoState] ? [0.25, 0.25, 0.25, 0.25];
		~ecoState = ~ecoStates.wchoose(w);
		("ECO state -> " ++ ~ecoState).postln;
	};

	~ecoSynths = IdentityDictionary.new;
	~ecoMaster = nil;
	~ecoRunning = false;

	~ecoStart = {
		if(~ecoRunning) { "ECO already running.".postln } {
			~ecoRunning = true;
			~ecoSrcGroup = Group.head(s);
			~ecoFxGroup = Group.after(~ecoSrcGroup);

			~ecoSynths[\sub] = Synth.head(~ecoSrcGroup, \ecoSub, [
				\out, ~ecoLayerBase.(0),
				\freq, ~ecoRootHz * 0.25,
				\amp, 0.26,
				\glide, 8.0
			]);
			~ecoSynths[\airA] = Synth.head(~ecoSrcGroup, \ecoAir, [
				\out, ~ecoLayerBase.(3),
				\amp, 0.045,
				\center, 3800
			]);
			~ecoSynths[\airB] = Synth.head(~ecoSrcGroup, \ecoAir, [
				\out, ~ecoLayerBase.(4),
				\amp, 0.04,
				\center, 6200
			]);

			~ecoMaster = Synth.tail(s, \ecoMaster8, [
				\layerBase, ~ecoLayerHub.index,
				\out, ~ecoOut,
				\gain8, [0.85, 0.55, 0.55, 0.35, 0.35, 0.22, 0.22, 0.0],
				\send8, [0.0, 0.35, 0.35, 0.45, 0.45, 0.25, 0.25, 0.0],
				\dry, 0.9,
				\revAmt, 0.38
			]);

			~ecoOrchestrator = fork {
				var lastMacro = Main.elapsedTime;
				var lastHarm = Main.elapsedTime;
				loop {
					var now = Main.elapsedTime;
					var waitT = ~ecoNextWait.value;
					var densityMul = switch(~ecoState,
						\dormant, { 0.15 },
						\sparse, { 0.45 },
						\active, { 1.0 },
						\decaying, { 0.35 },
						{ 0.4 }
					);
					if((now - lastMacro) > rrand(48.0, 120.0)) {
						~ecoStepState.value;
						lastMacro = now;
					};
					if((now - lastHarm) > rrand(22.0, 58.0)) {
						~ecoTargetRoot = (~ecoTargetRoot + [-2, 0, 2, 3].wchoose([0.2, 0.35, 0.25, 0.2])).clip(52, 76);
						~ecoRootHz = ~ecoTargetRoot.midicps;
						if(~ecoSynths[\sub].notNil) {
							~ecoSynths[\sub].set(\freq, ~ecoRootHz * 0.25);
						};
						("ECO root MIDI " ++ ~ecoTargetRoot).postln;
						lastHarm = now;
					};

					waitT = waitT / densityMul.max(0.15);
					waitT = (waitT + rrand(-0.15, 0.15)).max(0.35);
					waitT.wait;

					if(1.0.rand < densityMul.linlin(0, 1, 0.2, 0.85)) {
						var r = ~ecoRatios.wchoose(~ecoRatioWeights);
						var f = ~ecoRootHz * r * (2 ** [0, 1].wchoose([0.72, 0.28]));
						var atk = rrand(2.5, 9.0);
						var rel = rrand(10.0, 55.0);
						var pan = rrand(-0.85, 0.85);
						var layer = [1, 2].wchoose([0.55, 0.45]);
						Synth.head(~ecoSrcGroup, \ecoPadVoice, [
							\out, ~ecoLayerBase.(layer),
							\freq, f,
							\amp, rrand(0.05, 0.11) * densityMul.linlin(0, 1, 0.4, 1.0),
							\atk, atk,
							\rel, rel,
							\pan, pan
						]);
					};

					if((1.0.rand < (0.12 * densityMul)) and: { ~ecoState != \dormant }) {
						Synth.head(~ecoSrcGroup, \ecoRhythmGhost, [
							\out, ~ecoLayerBase.([5, 6].choose),
							\amp, rrand(0.03, 0.07),
							\hpf, rrand(90, 130),
							\lpf, rrand(1400, 3200),
							\pan, rrand(-0.5, 0.5)
						]);
					};
				};
			};

			~ecoParamTask = fork {
				loop {
					var d = ~ecoState.switch(\dormant, 0.12, \sparse, 0.35, \active, 0.72, \decaying, 0.28, { 0.35 });
					var rv = (0.55 - (d * 0.35)).clip(0.18, 0.52);
					if(~ecoMaster.notNil) {
						~ecoMaster.set(\revAmt, rv);
					};
					rrand(6.0, 14.0).wait;
				};
			};

			"ECO started (shiftko_ambient_ecosystem).".postln;
		};
	};

	~ecoStop = {
		~ecoRunning = false;
		if(~ecoOrchestrator.notNil) { ~ecoOrchestrator.stop; ~ecoOrchestrator = nil };
		if(~ecoParamTask.notNil) { ~ecoParamTask.stop; ~ecoParamTask = nil };
		if(~ecoMaster.notNil) { ~ecoMaster.free; ~ecoMaster = nil };
		~ecoSynths.keysValuesDo { |k, v| if(v.notNil) { v.free } };
		~ecoSynths.clear;
		if(~ecoSrcGroup.notNil) { ~ecoSrcGroup.free };
		if(~ecoFxGroup.notNil) { ~ecoFxGroup.free };
		"ECO stopped.".postln;
	};

	"shiftko_ambient_ecosystem: ready. Run ~ecoStart.()".postln;
};
)
