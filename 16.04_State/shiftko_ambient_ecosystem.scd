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
- Diskrete Zustaende: Zeilen in ~ecoStateWeights sind Markov-Uebergaenge (naechster Zustand haengt vom aktuellen ab)
- Enge Tonhoehen-Menge (pentatonisch / offene Intervalle)
- Sub <100 Hz nur auf einem Layer, trocken; Mid/High getrennt; Rhythmus gehocht
- Parameter-Inertia: Lag / VarLag / langsame Targets
- Mikro-Variation: Detune, Timing-Jitter

Vier typische Fehler (kurz) und wie diese Datei sie adressiert:
1) Naives Random -> Pwrand/exprand/wchoose, Verankerung (Ratio-Gewichte), Gauss-naeherung fuer Pan
2) BPM-Raster -> keine Impulse fuer Makro; Meso: Dust-Poisson (Sparkle); Mikro: konfligierende LFOs
3) Mud / Masking -> HPF auf Reverb-Send-Summe, Sub trocken, Layer-HPF im Master
4) Zipper/Clipping -> Lag auf Mixer-Controls, Limiter, EnvGen doneAction auf One-shots
5) Raumtiefe als Modell -> distance koppelt LPF + Dry-Level + Reverb-Anteil

Start: gesamten Block auswaehlen und ausfuehren.
Stop: ~ecoStop.() oder Cmd-.

Optional:
- ~ecoEnablePatterns.() fuer quantisierte Pbind-Schicht (TempoClock)
- ~ecoDisablePatterns.()
- ~ecoEnableOSC.() fuer externe OSC-Steuerung
- ~ecoDisableOSC.()
- ~ecoEnableScenes.() fuer optionale Macro-Choreografie (Ptpar-inspiriert)
- ~ecoDisableScenes.()
*/

(
s.quit;
Server.default = s = Server.local;
s.options.numInputBusChannels = 0;
s.options.numOutputBusChannels = 2;
s.options.sampleRate = 44100;
s.options.blockSize = 512;
s.options.memSize = 524288;

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
		f = VarLag.kr(freq.clip(28, 90), glide, warp: \sine);
		sig = SinOsc.ar(f * drift);
		sig = sig + (SinOsc.ar(f * 2 * drift, 0, 0.04));
		sig = tanh(sig * 1.15);
		sig = LPF.ar(sig, 110);
		env = Lag.kr(gate, 2.0);
		Out.ar(out, [sig, sig] * amp * env);
	}).add;

	// 1–2: Mid Pads — lange ASR, pentatonische Obertoene
	SynthDef(\ecoPadVoice, {
		arg out=0, freq=220, amp=0.1, atk=3.5, rel=28, pan=0, detuneCents=6.0, distance=0.65;
		var env, dt, a, b, sig, d, lpfHz, dryMul, spread;
		d = Lag.kr(distance.clip(0, 1), 3.5);
		lpfHz = d.linexp(0, 1, 7000, 900);
		dryMul = d.linlin(0, 1, 1.0, 0.35);
		spread = d.linlin(0, 1, 0.18, 0.9);
		dt = 2 ** (detuneCents / 1200 * LFNoise2.kr(0.04).range(-1, 1));
		a = SinOsc.ar(freq * dt * [0.9994, 1.0002]);
		b = SinOsc.ar(freq * 1.002 * dt * [1.0007, 0.9998]);
		sig = Splay.ar([a[0], b[0], a[1], b[1]], spread: spread, level: 0.42);
		sig = RLPF.ar(sig, (freq * 6).clip(400, lpfHz), 0.35);
		env = EnvGen.kr(Env([0, 1, 0], [atk, rel], [2, -3]), doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp * dryMul, pan));
	}).add;

	// 3–4: Texture / Air (Bandpass noise)
	SynthDef(\ecoAir, {
		arg out=0, amp=0.06, gate=1, center=4200, rq=0.35;
		var n, f, sig, env;
		f = Lag.kr(center, 5.0);
		f = f * SinOsc.kr(0.047).range(0.94, 1.06) * LFNoise2.kr(0.021).range(0.97, 1.03);
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

	// Reserviert (optionaler stummer Layer / Tests)
	SynthDef(\ecoSilence, {
		arg out=0;
		Out.ar(out, Silent.ar(2));
	}).add;

	// Meso-Zeit: Poisson-artige Hochfrequenz-Akzente (Dust), kein Sequenzer-Raster
	SynthDef(\ecoSparkle, {
		arg out=0, dens=0.1, amp=0.032, rootHz=140, gate=1;
		var tr, f0, sig, env, pan;
		tr = Dust.kr(dens.max(0.001));
		f0 = TExpRand.kr(rootHz * 3, rootHz * 14, tr);
		sig = SinOsc.ar(f0);
		sig = sig + (SinOsc.ar(f0 * 2.01, 0, 0.12));
		sig = HPF.ar(sig, 1200);
		sig = LPF.ar(sig, 10000);
		env = EnvGen.kr(Env.perc(0.003, 0.11, 1, -5), tr);
		pan = TRand.kr(-0.92, 0.92, tr);
		Out.ar(out, Pan2.ar(sig * env * amp * Lag.kr(gate, 2.0), pan));
	}).add;

	// Eno-inspirierte "planes": langsame, schwebende Akkordflaeche mit eigener Mikrozeit (Demand UGens)
	SynthDef(\ecoPlane, {
		arg out=0, rootHz=220, amp=0.045, gate=1, distance=0.82;
		var tr, chordSel, chordStep, chord, semis, freqs, sig, env, d, lpfHz, dryMul, spread, wob;
		var chords = Dseq([
			[0, 4, 7, 12],
			[4, 7, 11, 16],
			[-3, 0, 4, 7],
			[-3, 0, 5, 9]
		], inf);
		d = Lag.kr(distance.clip(0, 1), 4.5);
		lpfHz = d.linexp(0, 1, 6000, 700);
		dryMul = d.linlin(0, 1, 0.95, 0.28);
		spread = d.linlin(0, 1, 0.2, 0.95);
		chordSel = Dust.kr(0.018) + Impulse.kr(0);
		chordStep = Demand.kr(chordSel, 0, chords);
		chord = Lag.kr(chordStep, 10.0);
		semis = chord + [0, 12];
		freqs = (rootHz * (2 ** (semis / 12))).clip(90, 5200);
		wob = SinOsc.kr([0.013, 0.017, 0.021, 0.027, 0.031, 0.037, 0.041, 0.047]).range(0.992, 1.008);
		sig = VarSaw.ar(freqs * wob, width: LFNoise2.kr(0.03 ! 8).range(0.15, 0.82), mul: 0.12);
		sig = Splay.ar(sig, spread: spread, level: 0.55);
		sig = LPF.ar(sig, lpfHz);
		sig = HPF.ar(sig, 170);
		env = Lag.kr(gate, 6.0);
		Out.ar(out, [sig, sig] * amp * dryMul * env);
	}).add;

	// Eno/Rumush-inspirierter Feedback-Kern (LocalIn/LocalOut), aber streng begrenzt und langsam moduliert
	SynthDef(\ecoFeedback, {
		arg out=0, rootHz=110, rt=0.24, amp=0.045, fb=0.78, gate=1, distance=0.86;
		var trig, seqHz, src, loc, d, lpfHz, dryMul, spread, sh;
		var seq = Dseq([0, 7, 5, -1, 2, 4, 5], inf);
		d = Lag.kr(distance.clip(0, 1), 5.0);
		lpfHz = d.linexp(0, 1, 5200, 850);
		dryMul = d.linlin(0, 1, 0.92, 0.24);
		spread = d.linlin(0, 1, 0.2, 0.9);
		trig = Impulse.kr(rt.max(0.02));
		seqHz = (rootHz * (2 ** (Demand.kr(trig, 0, seq) / 12))).clip(70, 1400);
		src = Saw.ar(seqHz) * Decay2.kr(trig, 0.01, (1.0 / rt.max(0.02)).clip(0.2, 3.0), 0.18);
		loc = LocalIn.ar(2) + [src, src];
		sh = SinOsc.kr(0.012 ! 2).range(-0.85, 0.85);
		loc = FreqShift.ar(loc, sh);
		loc = loc + DelayC.ar(loc, 0.25, (seqHz.reciprocal).clip(0.002, 0.2));
		loc = DelayC.ar(loc, 2.8, LFNoise2.kr((rt * 0.6) ! 2).range(0.17, 1.8));
		loc = loc + AllpassC.ar(loc, 0.12, LFNoise1.kr((rt * 0.4) ! 2).range(0.035, 0.09), 3.5);
		loc = LPF.ar(loc, lpfHz);
		loc = HPF.ar(loc, 140);
		loc = LeakDC.ar(loc);
		loc = tanh(loc * 1.35);
		LocalOut.ar((loc * fb.clip(0.35, 0.9)) * Lag.kr(gate, 4.0));
		Out.ar(out, Splay.ar(loc, spread: spread, level: amp * dryMul));
	}).add;

	// Swish-Layer (inspiriert von AmbientGenSC swish/wind): kurzer, breiter Noise-Sweep
	SynthDef(\ecoSwish, {
		arg out=0, amp=0.028, panRate=0.06, rise=0.5, fall=5.2, lo=700, hi=4200;
		var n, f, sig, env, pan;
		n = WhiteNoise.ar(0.45);
		f = XLine.kr(lo.max(120), hi.max(lo + 50), (rise + fall).max(0.2));
		sig = BPF.ar(n, f, LFNoise2.kr(0.11).range(0.08, 0.45));
		sig = HPF.ar(sig, 650);
		pan = SinOsc.kr(panRate).range(-0.85, 0.85);
		env = EnvGen.kr(Env.linen(rise, 0.2, fall, curve: \welch), doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp, pan));
	}).add;

	// Sizuku/Droplet-Layer (inspiriert von AmbientGenSC sizuku): seltene, resonante Tropfen
	SynthDef(\ecoDrop, {
		arg out=0, amp=0.02, center=2200, decay=1.8, pan=0;
		var n, sig, env;
		n = WhiteNoise.ar(0.35);
		sig = RLPF.ar(n, center.clip(500, 9000), 0.09);
		sig = sig + DelayN.ar(sig, 0.3, 0.11, 0.35);
		sig = HPF.ar(sig, 800);
		env = EnvGen.kr(Env.perc(0.01, decay, 1, -5), doneAction: 2);
		Out.ar(out, Pan2.ar(sig * amp * env, pan));
	}).add;

	// Foolproof Infinite Ambient Voice:
	// - strikt begrenzte Harmonik (Scale-Auswahl erfolgt in Pattern/Routine)
	// - conflicting cycles auf Cutoff/Pan/Detune
	// - lange ASR, doneAction:2 fuer sauberes Freigeben
	SynthDef(\ecoSafeVoice, {
		arg out=0, revBus=0, freq=220, amp=0.08, gate=1, send=0.62;
		var env, det, sig, cutoff, pan, modA, modB, modC;
		modA = LFNoise2.kr(0.03).range(0.88, 1.12);
		modB = LFNoise2.kr(0.07).range(0.9, 1.1);
		modC = LFNoise2.kr(0.11).range(0.92, 1.08);
		det = [0.997, 1.0, 1.003] * modC;
		sig = LFTri.ar(freq * det, mul: 0.23);
		sig = Splay.ar(sig, spread: 0.55, level: 0.55);
		cutoff = (freq * 5.5 * modA * modB).clip(300, 2400);
		sig = RLPF.ar(sig, cutoff, 0.33);
		pan = LFNoise2.kr(0.07).range(-0.6, 0.6);
		sig = Pan2.ar(sig, pan);
		env = EnvGen.kr(Env.asr(6.0, 1.0, 16.0, curve: [-4, -4]), gate, doneAction: 2);
		sig = sig * env * amp;
		Out.ar(out, sig * (1 - send));
		Out.ar(revBus, sig * send);
	}).add;

	// Fail-safe global reverb bus with hard limiter ceiling
	SynthDef(\ecoSafeReverb, {
		arg in=0, out=0, room=0.94, damp=0.45, hpf=180;
		var sig, wet, sum;
		sig = In.ar(in, 2);
		sig = HPF.ar(sig, hpf);
		wet = FreeVerb2.ar(sig[0], sig[1], mix: 1.0, room: room.clip(0.6, 0.99), damp: damp.clip(0.1, 0.9));
		sum = (sig * 0.22) + (wet * 0.78);
		sum = LeakDC.ar(sum);
		Out.ar(out, Limiter.ar(sum, 0.8, 0.02));
	}).add;

	// Master: 8 stereo layers (16ch interleaved) — per-channel gain, spectral HPF, reverb send.
	// Layer 0 = Sub: dry in sum; reverb send index 0 should stay 0 (sub stays dry).
	SynthDef(\ecoMaster8, {
		arg layerBase=0, out=0, dry=0.88, revAmt=0.42, duckAmt=0.1;
		var inter, drySig, revIn, wet, sparkExcite, duck;
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
		// Zusaetzlicher HPF auf der Reverb-Send-Summe gegen Low-End-Mud im Hall
		revIn = [HPF.ar(revIn[0], 200), HPF.ar(revIn[1], 200)];
		// Leichtes Sidechain-artiges Atmen: Spark-Layer drueckt Pads subtil weg
		sparkExcite = HPF.ar(inter[14] + inter[15], 1800).abs.lag(0.04);
		duck = (1 - (sparkExcite * duckAmt).clip(0, 0.22)).lag(0.25);
		drySig = drySig * duck;
		revIn = revIn * duck;
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
	// Staerkere Verankerung: Grundton > Quinte > Extensions
	~ecoRatioWeights = [0.42, 0.14, 0.2, 0.14, 0.06, 0.04];

	// Gauss-naeherung (Summe uniform) statt Pwhite fuer Pan — weniger Rand-Extreme
	~ecoGaussPan = { ((3.collect({ 1.0.rand2 }).sum / 3) * 0.92).clip(-1, 1) };

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

	// Erster-Ordnung-Markov: Zeile = Uebergangswahrscheinlichkeiten vom aktuellen ~ecoState
	~ecoStepState = {
		var w = ~ecoStateWeights[~ecoState] ? [0.25, 0.25, 0.25, 0.25];
		~ecoState = ~ecoStates.wchoose(w);
		("ECO state -> " ++ ~ecoState).postln;
	};

	~ecoSynths = IdentityDictionary.new;
	~ecoMaster = nil;
	~ecoRunning = false;
	~safeRunning = false;
	~safePat = nil;
	~safeConductor = nil;
	~safeReverb = nil;
	~safeScale = [0, 3, 5, 7, 10];      // C minor pentatonic
	~safeDegW = [0.6, 0.08, 0.07, 0.25, 0.0]; // root + fifth dominant, sparse color tones
	~safeRootMidi = 48;                   // C3
	~safeCutMax = 1900;
	~safeRevRoom = 0.94;
	~ecoPatternPlayers = List.new;
	~ecoScenePlayer = nil;
	~ecoTempo = TempoClock.new(54/60);
	~ecoOscEnabled = false;

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
			~ecoSynths[\spark] = Synth.head(~ecoSrcGroup, \ecoSparkle, [
				\out, ~ecoLayerBase.(7),
				\dens, 0.08,
				\rootHz, ~ecoRootHz,
				\amp, 0.028
			]);
			~ecoSynths[\plane] = Synth.head(~ecoSrcGroup, \ecoPlane, [
				\out, ~ecoLayerBase.(2),
				\rootHz, ~ecoRootHz * 0.5,
				\amp, 0.042,
				\distance, 0.82
			]);
			~ecoSynths[\fdb] = Synth.head(~ecoSrcGroup, \ecoFeedback, [
				\out, ~ecoLayerBase.(6),
				\rootHz, ~ecoRootHz * 0.85,
				\rt, 0.22,
				\fb, 0.74,
				\amp, 0.032,
				\distance, 0.87
			]);

			// Sources: Group.head; Summing+Hall: Group.tail (Creation vs. Control: feste Rollen)
			~ecoMaster = Synth.tail(~ecoFxGroup, \ecoMaster8, [
				\layerBase, ~ecoLayerHub.index,
				\out, ~ecoOut,
				\gain8, [0.85, 0.55, 0.55, 0.35, 0.35, 0.22, 0.22, 0.38],
				\send8, [0.0, 0.35, 0.35, 0.45, 0.45, 0.25, 0.25, 0.5],
				\dry, 0.9,
				\revAmt, 0.38,
				\duckAmt, 0.1
			]);

			~ecoOrchestrator = fork {
				var lastMacro = Main.elapsedTime;
				var lastHarm = Main.elapsedTime;
				var macroNext = exprand(52.0, 135.0);
				var harmNext = exprand(22.0, 58.0);
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
					if((now - lastMacro) > macroNext) {
						~ecoStepState.value;
						lastMacro = now;
						macroNext = exprand(52.0, 135.0);
					};
					if((now - lastHarm) > harmNext) {
						~ecoTargetRoot = (~ecoTargetRoot + [-2, 0, 2, 3].wchoose([0.2, 0.35, 0.25, 0.2])).clip(52, 76);
						~ecoRootHz = ~ecoTargetRoot.midicps;
						if(~ecoSynths[\sub].notNil) {
							~ecoSynths[\sub].set(\freq, ~ecoRootHz * 0.25);
						};
						if(~ecoSynths[\spark].notNil) {
							~ecoSynths[\spark].set(\rootHz, ~ecoRootHz);
						};
						("ECO root MIDI " ++ ~ecoTargetRoot).postln;
						lastHarm = now;
						harmNext = exprand(22.0, 58.0);
					};

					waitT = waitT / densityMul.max(0.15);
					// Mikro-Jitter: Gauss-naeherung statt gleichverteiltem rrand
					waitT = (waitT + ((3.collect({ 1.0.rand2 }).sum / 3) * 0.18)).max(0.35);
					waitT.wait;

					if(1.0.rand < densityMul.linlin(0, 1, 0.2, 0.85)) {
						var r = ~ecoRatios.wchoose(~ecoRatioWeights);
						var f = ~ecoRootHz * r * (2 ** [0, 1].wchoose([0.72, 0.28]));
						var atk = exprand(2.0, 9.5);
						var rel = exprand(10.0, 52.0);
						var pan = ~ecoGaussPan.value;
						var layer = [1, 2].wchoose([0.55, 0.45]);
						Synth.head(~ecoSrcGroup, \ecoPadVoice, [
							\out, ~ecoLayerBase.(layer),
							\freq, f,
							\amp, exprand(0.04, 0.11) * densityMul.linlin(0, 1, 0.4, 1.0),
							\atk, atk,
							\rel, rel,
							\pan, pan,
							\distance, exprand(0.32, 0.96).clip(0, 1)
						]);
					};

					if((1.0.rand < (0.12 * densityMul)) and: { ~ecoState != \dormant }) {
						Synth.head(~ecoSrcGroup, \ecoRhythmGhost, [
							\out, ~ecoLayerBase.([5, 6].choose),
							\amp, exprand(0.025, 0.075),
							\hpf, exprand(88.0, 132.0),
							\lpf, exprand(1200.0, 3600.0),
							\pan, ~ecoGaussPan.value * 0.55
						]);
					};
				};
			};

			~ecoParamTask = fork {
				loop {
					var d = ~ecoState.switch(\dormant, 0.12, \sparse, 0.35, \active, 0.72, \decaying, 0.28, { 0.35 });
					var rv = (0.55 - (d * 0.35)).clip(0.18, 0.52);
					var spD = ~ecoState.switch(\dormant, 0.018, \sparse, 0.07, \active, 0.22, \decaying, 0.045, { 0.06 });
					var planeDist = ~ecoState.switch(\dormant, 0.93, \sparse, 0.84, \active, 0.72, \decaying, 0.88, { 0.84 });
					var fdbDist = ~ecoState.switch(\dormant, 0.95, \sparse, 0.9, \active, 0.78, \decaying, 0.9, { 0.9 });
					var fdbRt = ~ecoState.switch(\dormant, 0.08, \sparse, 0.16, \active, 0.28, \decaying, 0.14, { 0.16 });
					var fdbFb = ~ecoState.switch(\dormant, 0.58, \sparse, 0.68, \active, 0.8, \decaying, 0.64, { 0.68 });
					var fdbAmp = ~ecoState.switch(\dormant, 0.01, \sparse, 0.024, \active, 0.042, \decaying, 0.018, { 0.024 });
					var duck = ~ecoState.switch(\dormant, 0.05, \sparse, 0.08, \active, 0.14, \decaying, 0.09, { 0.08 });
					if(~ecoMaster.notNil) {
						~ecoMaster.set(\revAmt, rv, \duckAmt, duck);
					};
					if(~ecoSynths[\spark].notNil) {
						~ecoSynths[\spark].set(\dens, spD, \rootHz, ~ecoRootHz);
					};
					if(~ecoSynths[\plane].notNil) {
						~ecoSynths[\plane].set(\rootHz, ~ecoRootHz * 0.5, \distance, planeDist);
					};
					if(~ecoSynths[\fdb].notNil) {
						~ecoSynths[\fdb].set(
							\rootHz, ~ecoRootHz * 0.85,
							\rt, fdbRt,
							\fb, fdbFb,
							\amp, fdbAmp,
							\distance, fdbDist
						);
					};
					exprand(5.5, 14.0).wait;
				};
			};

			"ECO started (shiftko_ambient_ecosystem).".postln;
		};
	};

	~ecoStop = {
		~ecoRunning = false;
		~safeRunning = false;
		if(~safePat.notNil) { ~safePat.stop; ~safePat = nil };
		if(~safeConductor.notNil) { ~safeConductor.stop; ~safeConductor = nil };
		if(~safeReverb.notNil) { ~safeReverb.free; ~safeReverb = nil };
		if(~ecoPatternPlayers.notNil) { ~ecoPatternPlayers.do(_.stop); ~ecoPatternPlayers.clear };
		if(~ecoScenePlayer.notNil) { ~ecoScenePlayer.stop; ~ecoScenePlayer = nil };
		if(~ecoOscEnabled) { ~ecoDisableOSC.() };
		if(~ecoOrchestrator.notNil) { ~ecoOrchestrator.stop; ~ecoOrchestrator = nil };
		if(~ecoParamTask.notNil) { ~ecoParamTask.stop; ~ecoParamTask = nil };
		if(~ecoMaster.notNil) { ~ecoMaster.free; ~ecoMaster = nil };
		~ecoSynths.keysValuesDo { |k, v| if(v.notNil) { v.free } };
		~ecoSynths.clear;
		if(~ecoSrcGroup.notNil) { ~ecoSrcGroup.free };
		if(~ecoFxGroup.notNil) { ~ecoFxGroup.free };
		"ECO stopped.".postln;
	};

	// ---- Foolproof Infinite Ambient Mode ----
	~safeStart = {
		if(~safeRunning) {
			"SAFE mode already running.".postln;
		} {
			~safeRunning = true;
			if(~safeReverb.notNil) { ~safeReverb.free; };
			~safeReverb = Synth.tail(~ecoFxGroup, \ecoSafeReverb, [
				\in, ~ecoRevSend.index, \out, ~ecoOut, \room, ~safeRevRoom
			]);

			~safePat = Pbind(
				\type, \note,
				\dur, Pexprand(3.0, 18.0, inf),
				\callback, { |ev|
					var running = (topEnvironment[\safeRunning] ? false).asBoolean;
					var rootMidi = topEnvironment[\safeRootMidi] ? 48;
					var degs = topEnvironment[\safeScale] ? [0, 3, 5, 7, 10];
					var w = topEnvironment[\safeDegW] ? [0.6, 0.08, 0.07, 0.25, 0.0];
					var src = topEnvironment[\ecoSrcGroup];
					var revBus = topEnvironment[\ecoRevSend];
					var degree, freq;
					if(running and: { src.notNil } and: { revBus.notNil }) {
						degree = degs.wchoose(w);
						freq = (rootMidi + degree + ([0, 12].wchoose([0.78, 0.22]))).midicps;
						Synth.head(src, \ecoSafeVoice, [
							\out, topEnvironment[\ecoOut] ? 0,
							\revBus, revBus.index,
							\freq, freq,
							\amp, exprand(0.05, 0.11),
							\send, exprand(0.5, 0.8)
						]);
					};
					nil
				}
			).play(TempoClock.default, quant: 2);

			~safeConductor = Routine({
				loop {
					// very slow bounded drift (30-60s), never leaving safe limits
					~safeCutMax = (~safeCutMax + [ -80, -35, 0, 30, 70 ].wchoose([0.1, 0.18, 0.34, 0.23, 0.15])).clip(1300, 2600);
					~safeRevRoom = (~safeRevRoom + [ -0.02, -0.01, 0.0, 0.01, 0.02 ].wchoose([0.08, 0.18, 0.48, 0.18, 0.08])).clip(0.86, 0.98);
					if(~safeReverb.notNil) { ~safeReverb.set(\room, ~safeRevRoom); };
					rrand(30.0, 60.0).wait;
				}
			}).play(AppClock);
			"SAFE mode started.".postln;
		};
	};

	~safeStop = {
		~safeRunning = false;
		if(~safePat.notNil) { ~safePat.stop; ~safePat = nil };
		if(~safeConductor.notNil) { ~safeConductor.stop; ~safeConductor = nil };
		if(~safeReverb.notNil) { ~safeReverb.free; ~safeReverb = nil };
		"SAFE mode stopped.".postln;
	};

	// ---- Optionale Pattern-/Clock-Schicht (quantisiert) ----
	~ecoEnablePatterns = {
		if(~ecoPatternPlayers.notNil and: { ~ecoPatternPlayers.size > 0 }) {
			"ECO patterns already active.".postln;
		} {
			var padPat, sparkPat;
			padPat = Pbind(
				\type, \note,
				\callback, { |ev|
					var isRunning = (topEnvironment[\ecoRunning] ? false).asBoolean;
					var st = topEnvironment[\ecoState] ? \sparse;
					var ratios = topEnvironment[\ecoRatios] ? [1.0, 1.5, 2.0];
					var ratioWeights = topEnvironment[\ecoRatioWeights] ? [0.6, 0.3, 0.1];
					var srcGroup = topEnvironment[\ecoSrcGroup];
					var layerBaseFn = topEnvironment[\ecoLayerBase];
					var gaussPanFn = topEnvironment[\ecoGaussPan];
					var rootHz = topEnvironment[\ecoRootHz] ? 64.midicps;
					if(isRunning and: { st != \dormant } and: { srcGroup.notNil } and: { layerBaseFn.notNil }) {
						var r = ratios.wchoose(ratioWeights);
						var oct = [0, 1].wchoose([0.76, 0.24]);
						var pan = if(gaussPanFn.notNil) { gaussPanFn.value } { 0.0 };
						Synth.head(srcGroup, \ecoPadVoice, [
							\out, layerBaseFn.([1, 2].wchoose([0.58, 0.42])),
							\freq, rootHz * r * (2 ** oct),
							\amp, exprand(0.028, 0.072),
							\atk, exprand(2.8, 10.0),
							\rel, exprand(14.0, 60.0),
							\pan, pan,
							\distance, exprand(0.45, 0.97).clip(0, 1)
						]);
					};
					nil
				},
				\dur, Pexprand(7.0, 32.0, inf)
			).play(~ecoTempo, quant: 4);

			sparkPat = Pbind(
				\type, \note,
				\callback, { |ev|
					var isRunning = (topEnvironment[\ecoRunning] ? false).asBoolean;
					var st = topEnvironment[\ecoState] ? \sparse;
					var synths = topEnvironment[\ecoSynths];
					if(isRunning and: { synths.notNil } and: { synths[\spark].notNil }) {
						var dens = st.switch(\dormant, 0.01, \sparse, 0.05, \active, 0.2, \decaying, 0.03, { 0.05 });
						synths[\spark].set(\dens, dens);
					};
					nil
				},
				\dur, Pwrand([8, 12, 16, 24], [0.35, 0.3, 0.22, 0.13], inf)
			).play(~ecoTempo, quant: 4);

			~ecoPatternPlayers = [padPat, sparkPat];
			"ECO patterns enabled.".postln;
		};
	};

	~ecoDisablePatterns = {
		if(~ecoPatternPlayers.notNil) { ~ecoPatternPlayers.do(_.stop); ~ecoPatternPlayers.clear };
		"ECO patterns disabled.".postln;
	};

	// ---- Optionale Macro-Szenen (Ptpar-Idee: Ereignis-Zeitleiste mit langen Abstaenden) ----
	~ecoEnableScenes = {
		if(~ecoScenePlayer.notNil) {
			"ECO scenes already active.".postln;
		} {
			~ecoScenePlayer = Task({
				loop {
					if(~ecoRunning) {
						// Szene A: ruhige Luftbewegung
						Synth.head(~ecoSrcGroup, \ecoSwish, [
							\out, ~ecoLayerBase.(4),
							\amp, 0.022,
							\rise, 0.8,
							\fall, 6.0,
							\lo, 750,
							\hi, 3400
						]);
					};
					exprand(14.0, 38.0).wait;
					if(~ecoRunning) {
						// Szene B: seltene Tropfenpunkte
						Synth.head(~ecoSrcGroup, \ecoDrop, [
							\out, ~ecoLayerBase.(7),
							\amp, exprand(0.012, 0.028),
							\center, exprand(1100, 5200),
							\decay, exprand(0.8, 2.6),
							\pan, ~ecoGaussPan.value
						]);
					};
					exprand(9.0, 24.0).wait;
					if(~ecoRunning and: { ~ecoState == \active }) {
						// Szene C: aktiver Schub in aktiver Plateau-Phase
						Synth.head(~ecoSrcGroup, \ecoSwish, [
							\out, ~ecoLayerBase.(3),
							\amp, 0.03,
							\rise, 0.3,
							\fall, 4.8,
							\lo, 900,
							\hi, 4800,
							\panRate, 0.09
						]);
					};
					exprand(18.0, 44.0).wait;
				};
			}).play(~ecoTempo, quant: 4);
			"ECO scenes enabled.".postln;
		};
	};

	~ecoDisableScenes = {
		if(~ecoScenePlayer.notNil) { ~ecoScenePlayer.stop; ~ecoScenePlayer = nil };
		"ECO scenes disabled.".postln;
	};

	// ---- Optionale OSC-Steuerung (externes Processing/TouchOSC/etc.) ----
	~ecoEnableOSC = {
		if(~ecoOscEnabled) {
			"ECO OSC already enabled.".postln;
		} {
			OSCdef(\ecoStateSet, { |msg|
				var key = msg[1].asSymbol;
				if(~ecoStates.includes(key)) { ~ecoState = key; ("ECO state <- " ++ key).postln; };
			}, "/eco/state");

			OSCdef(\ecoRootSet, { |msg|
				var midi = msg[1].asFloat.clip(40, 84);
				~ecoTargetRoot = midi;
				~ecoRootHz = midi.midicps;
				if(~ecoSynths[\sub].notNil) { ~ecoSynths[\sub].set(\freq, ~ecoRootHz * 0.25) };
				if(~ecoSynths[\spark].notNil) { ~ecoSynths[\spark].set(\rootHz, ~ecoRootHz) };
				if(~ecoSynths[\plane].notNil) { ~ecoSynths[\plane].set(\rootHz, ~ecoRootHz * 0.5) };
				if(~ecoSynths[\fdb].notNil) { ~ecoSynths[\fdb].set(\rootHz, ~ecoRootHz * 0.85) };
			}, "/eco/root");

			OSCdef(\ecoReverbSet, { |msg|
				var v = msg[1].asFloat.clip(0.1, 0.7);
				if(~ecoMaster.notNil) { ~ecoMaster.set(\revAmt, v) };
			}, "/eco/rev");

			OSCdef(\ecoSparkSet, { |msg|
				var v = msg[1].asFloat.clip(0.001, 0.6);
				if(~ecoSynths[\spark].notNil) { ~ecoSynths[\spark].set(\dens, v) };
			}, "/eco/spark");

			~ecoOscEnabled = true;
			"ECO OSC enabled: /eco/state /eco/root /eco/rev /eco/spark".postln;
		};
	};

	~ecoDisableOSC = {
		[\ecoStateSet, \ecoRootSet, \ecoReverbSet, \ecoSparkSet].do { |k| OSCdef(k).free };
		~ecoOscEnabled = false;
		"ECO OSC disabled.".postln;
	};

	// ---- Bedienbare UI (Fader/Encoder/Buttons) ----
	~ecoUIWindow = nil;
	~ecoOpenUI = {
		GUI.qt;
		AppClock.sched(0.0, {
			var win, rootKnob, duckKnob, stateMenu;
			var dryFader, revFader, sparkFader;
			var engineView, harmonyView, masterView;
			var dryVal = 0.9, revVal = 0.38, duckVal = 0.1, sparkVal = 0.08, rootVal = 64.0;
			var b = Window.availableBounds ? Rect(40, 40, 1200, 800);
			var r = Rect((b.left + 30).asInteger, (b.top + 30).asInteger, 920, 500);
			var styleEZ;

			if(~ecoUIWindow.notNil and: { ~ecoUIWindow.isClosed.not }) {
				~ecoUIWindow.visible_(true);
				~ecoUIWindow.front;
				~ecoUIWindow.alwaysOnTop_(true);
				~ecoUIWindow.alwaysOnTop_(false);
				"ECO UI reopened.".postln;
				^nil;
			};

			win = Window("SHIFTKO Ecosystem Controls", r).front;
			win.alwaysOnTop_(true);
			win.alwaysOnTop_(false);
			win.view.background_(Color.grey(0.15));
			engineView = CompositeView(win, Rect(0, 0, 1, 1)).background_(Color.grey(0.18));
			harmonyView = CompositeView(win, Rect(0, 0, 1, 1)).background_(Color.grey(0.18));
			masterView = CompositeView(win, Rect(0, 0, 1, 1)).background_(Color.grey(0.18));

			styleEZ = { |ez|
				ez.setColors(
					Color.grey(0.82),
					Color.white,
					Color.grey(0.28),
					Color.grey(0.62),
					Color.white,
					Color(1.0, 0.85, 0.2)
				);
			};

			rootKnob = EZKnob(harmonyView, 96@90, "Root MIDI", ControlSpec(40, 84, \lin, 0.1, rootVal), { |ez|
				rootVal = ez.value;
				~ecoTargetRoot = rootVal.round(1);
				~ecoRootHz = ~ecoTargetRoot.midicps;
				if(~ecoSynths[\sub].notNil) { ~ecoSynths[\sub].set(\freq, ~ecoRootHz * 0.25) };
				if(~ecoSynths[\spark].notNil) { ~ecoSynths[\spark].set(\rootHz, ~ecoRootHz) };
				if(~ecoSynths[\plane].notNil) { ~ecoSynths[\plane].set(\rootHz, ~ecoRootHz * 0.5) };
				if(~ecoSynths[\fdb].notNil) { ~ecoSynths[\fdb].set(\rootHz, ~ecoRootHz * 0.85) };
			}, rootVal);
			styleEZ.value(rootKnob);

			duckKnob = EZKnob(harmonyView, 96@90, "Ducking", ControlSpec(0.0, 0.3, \lin, 0.001, duckVal), { |ez|
				duckVal = ez.value;
				if(~ecoMaster.notNil) { ~ecoMaster.set(\duckAmt, duckVal) };
			}, duckVal);
			duckKnob.centered_(true);
			styleEZ.value(duckKnob);

			dryFader = EZSlider(masterView, 92@240, "Dry", ControlSpec(0.2, 1.2, \lin, 0.001, dryVal), { |ez|
				dryVal = ez.value;
				if(~ecoMaster.notNil) { ~ecoMaster.set(\dry, dryVal) };
			}, dryVal, layout: \vert);
			styleEZ.value(dryFader);

			revFader = EZSlider(masterView, 92@240, "Reverb", ControlSpec(0.1, 0.75, \lin, 0.001, revVal), { |ez|
				revVal = ez.value;
				if(~ecoMaster.notNil) { ~ecoMaster.set(\revAmt, revVal) };
			}, revVal, layout: \vert);
			styleEZ.value(revFader);

			sparkFader = EZSlider(harmonyView, 92@240, "Spark", ControlSpec(0.001, 0.6, \exp, 0.001, sparkVal), { |ez|
				sparkVal = ez.value;
				if(~ecoSynths[\spark].notNil) { ~ecoSynths[\spark].set(\dens, sparkVal) };
			}, sparkVal, layout: \vert);
			styleEZ.value(sparkFader);

			stateMenu = PopUpMenu(engineView, 160@24)
				.items_(["dormant", "sparse", "active", "decaying"])
				.action_({ |m|
					~ecoState = [\dormant, \sparse, \active, \decaying][m.value];
					("ECO state <- " ++ ~ecoState).postln;
				});

			engineView.layout_(
				VLayout(
					StaticText(engineView).string_("ENGINE").align_(\center),
					Button(engineView).states_([["START", Color.black, Color(0.3, 0.95, 0.3)]]).action_({ ~ecoStart.() }),
					Button(engineView).states_([["STOP", Color.white, Color(0.9, 0.2, 0.2)]]).action_({ ~ecoStop.() }),
					Button(engineView).states_([["PATTERN OFF", Color.white, Color.grey(0.25)], ["PATTERN ON", Color.black, Color(0.95, 0.9, 0.2)]])
					.action_({ |bt| if(bt.value == 1) { ~ecoEnablePatterns.() } { ~ecoDisablePatterns.() } }),
					Button(engineView).states_([["SCENES OFF", Color.white, Color.grey(0.25)], ["SCENES ON", Color.black, Color(0.95, 0.9, 0.2)]])
					.action_({ |bt| if(bt.value == 1) { ~ecoEnableScenes.() } { ~ecoDisableScenes.() } }),
					Button(engineView).states_([["OSC OFF", Color.white, Color.grey(0.25)], ["OSC ON", Color.black, Color(0.95, 0.9, 0.2)]])
					.action_({ |bt| if(bt.value == 1) { ~ecoEnableOSC.() } { ~ecoDisableOSC.() } }),
					StaticText(engineView).string_("STATE").align_(\center),
					stateMenu
				).margins_(10).spacing_(8)
			);

			harmonyView.layout_(
				VLayout(
					StaticText(harmonyView).string_("HARMONY").align_(\center),
					rootKnob,
					duckKnob,
					nil,
					sparkFader
				).margins_(10).spacing_(8)
			);

			masterView.layout_(
				VLayout(
					StaticText(masterView).string_("MASTER").align_(\center),
					nil,
					dryFader,
					revFader
				).margins_(10).spacing_(8)
			);

			win.layout_(
				HLayout(
					engineView,
					harmonyView,
					masterView
				).margins_(10).spacing_(14)
			);

			win.onClose_({ ~ecoUIWindow = nil });
			~ecoUIWindow = win;
			"ECO UI ready.".postln;
			nil
		});
	};

	~ecoCloseUI = {
		AppClock.sched(0.0, {
			if(~ecoUIWindow.notNil and: { ~ecoUIWindow.isClosed.not }) { ~ecoUIWindow.close };
			nil
		});
		~ecoUIWindow = nil;
	};

	~ecoVersion = "ecosystem-single-canvas-ui-v6";
	("shiftko_ambient_ecosystem: ready (" ++ ~ecoVersion ++ "). Run ~ecoStart.() and optionally ~ecoOpenUI.()").postln;
	AppClock.sched(0.2, { ~ecoOpenUI.(); "ECO UI auto-open requested.".postln; nil });
};
)
