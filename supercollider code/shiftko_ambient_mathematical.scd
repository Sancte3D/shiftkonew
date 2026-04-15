/*
SHIFTKO -> SuperCollider (mathematische Neuimplementierung)
-----------------------------------------------------------
Phase-1-Extrakt (Pd DSP-Essenz):
- GUI/Busse: bpm, mood-raw, reverb-room-base, drone-level, notes-level, noise-level,
  texture-level, master-vol, transport, root-hz, chord/pedal-level, 7x Scale-Weights.
- Cutoff-Mathematik: filterCutoff = base * lfoMul * rndMul * chaosMul, danach Clamp.
- Reverb-Raum: reverbRoom = reverbBase * lfoMul * rndMul, danach Clamp.
- line~/vline~ => zeitliche Interpolation/Envelope-Generator.
- catch~/throw~ => Summenbusse (drone, notes, texture, noise), danach FX-Kette.
*/

(
// Robuster Server-Start mit Device-Fallback fuer Live-Sessions
// Kein hartes Speaker-Modul pinnen: Default-Systemroute nutzen, bis finale Hardware feststeht.
var preferredOutDevice = "Default";
var preferredInDevice = "Default";

s.quit;
Server.default = s = Server.local;
s.options.numInputBusChannels = 0;
s.options.numOutputBusChannels = 2;
s.options.sampleRate = 44100;
s.options.blockSize = 512;
s.options.memSize = 262144;
s.options.maxNodes = 32768;
s.options.numWireBufs = 512;
s.options.inDevice = preferredInDevice;
s.options.outDevice = preferredOutDevice;

s.waitForBoot {
	var hasJPverb = \JPverb.asClass.notNil;
	SynthDef(\shiftkoAmbientMath, { |out=0,
		// GUI-Args (aus Pd abgeleitet)
		bpm=60, moodRaw=0.3, reverbRoomBase=0.4, droneLevel=0.6, notesLevel=0.5,
		noiseLevel=0.06, textureLevel=0.1, masterVol=0.4, transport=1,
		deprecatedHeadphoneMode=0, rootHz=256, droneGate=1, notesGate=1, noiseGate=1, textureGate=1,
		chordLevel=0.6, pedalLevel=0.08, cosmicW=100, wonderW=0, hopefulW=0, kotoW=0,
		ragaW=0, pelogW=0, safir16W=0, filterCutoffBase=1800, wholeTime=4000, macroGate=1, noiseType=0,
		chaosDepth=0.12, safeMode=1, mixMode=0, textureDuck=0.6, weightEvolve=0,
		noteDensity=0.9, calmness=0.5, auxInEnable=0, auxInLevel=0.0, auxInBlend=0.0,
		autoGainProtect=1, loudnessTarget=0.26
	|
		var bpmS, mood, roomBase, dLvl, nLvl, nzLvl, texLvl, mVol, tr, rtHz;
		var dGate, nGate, nzGate, tGate, chLvl, pdLvl, fBase, mGate;
		var weights, weightNorm, scaleSel, scaleHz, trigRate, trig, noteTrig;
		var scaleCosmic, scaleWonder, scaleHopeful, scaleKoto, scaleRaga, scalePelog, scaleSafir16;
		var root, sub, octave, fifth, droneCore, droneLfoL, droneLfoR, droneStereo;
		var detuneA, detuneB, noteHz, noteEnv, noteSig, textureSig, noiseSig, chaosRateJitter, chaosPitchDrift;
		var notesEnergy, textureDuckCtrl, textureDucker;
		var lfoMul, rndMul, chaosMul, cutoff, roomMulRnd, roomCtrl;
		var textureCap, noiseCap, notesCap, droneCap, safeMix, safeCtrl, chaosDepthSm, mixModeSm, notesSoloMix;
		var wEvolve, wDrift;
		var densityCtrl, calmCtrl, effectiveChaos, effectiveTex, effectiveNoise;
		var dryL, dryR, wetL, wetR, mix, hpSafety;
		var protectOn, loudTarget, outEnv, gainGuard;
		var auxGate, auxLvl, auxBlend, auxL, auxR, auxSig;

		// Alle kritischen Steuerwerte mit Lag.kr glätten (Anti-Zipper/Anti-Klick)
		bpmS   = Lag.kr(bpm.clip(30, 100), 0.3);
		mood   = Lag.kr(moodRaw.clip(0, 1), 1.2);
		roomBase = Lag.kr(reverbRoomBase.clip(0.001, 0.8), 1.0);
		dLvl   = Lag.kr(droneLevel.clip(0.001, 0.8), 1.5);
		nLvl   = Lag.kr(notesLevel.clip(0.001, 0.8), 1.5);
		nzLvl  = Lag.kr(noiseLevel.clip(0, 0.3), 1.0);
		texLvl = Lag.kr(textureLevel.clip(0, 0.16), 1.0);
		mVol   = Lag.kr(masterVol.clip(0.001, 0.55), 1.0);
		tr     = Lag.kr(transport.clip(0, 1), 0.2);
		rtHz   = Lag.kr(rootHz.clip(32, 1600), 2.0);
		dGate  = Lag.kr(droneGate.clip(0, 1), 0.3);
		nGate  = Lag.kr(notesGate.clip(0, 1), 0.3);
		nzGate = Lag.kr(noiseGate.clip(0, 1), 0.3);
		tGate  = Lag.kr(textureGate.clip(0, 1), 0.3);
		chLvl  = Lag.kr(chordLevel.clip(0, 0.8), 1.2);
		pdLvl  = Lag.kr(pedalLevel.clip(0, 0.3), 1.2);
		fBase  = Lag.kr(filterCutoffBase.clip(120, 12000), 2.5);
		mGate  = Lag.kr(macroGate.clip(0, 1), 3.0);
		chaosDepthSm = Lag.kr(chaosDepth.clip(0, 0.4), 2.0);
		safeCtrl = Lag.kr(safeMode.clip(0, 1), 0.3);
		mixModeSm = Lag.kr(mixMode.clip(0, 1), 0.15);
		textureDuckCtrl = Lag.kr(textureDuck.clip(0, 1), 1.2);
		wEvolve = Lag.kr(weightEvolve.clip(0, 1), 2.5);
		densityCtrl = Lag.kr(noteDensity.clip(0.2, 1.0), 1.5);
		calmCtrl = Lag.kr(calmness.clip(0, 1), 2.0);
		effectiveChaos = chaosDepthSm * LinLin.kr(calmCtrl, 0, 1, 1.4, 0.45);
		effectiveTex = LinLin.kr(calmCtrl, 0, 1, 1.15, 0.55);
		effectiveNoise = LinLin.kr(calmCtrl, 0, 1, 1.2, 0.5);
		auxGate = Lag.kr(auxInEnable.clip(0, 1), 0.25);
		auxLvl = Lag.kr(auxInLevel.clip(0, 0.9), 1.0);
		auxBlend = Lag.kr(auxInBlend.clip(0, 1), 1.0);
		protectOn = Lag.kr(autoGainProtect.clip(0, 1), 0.2);
		loudTarget = Lag.kr(loudnessTarget.clip(0.12, 0.45), 0.8);

		// Gewichtete Skalenwahl (Pd-Gedanke: "Chords_Scales" + Weight-Slider)
		wDrift = [
			LFDNoise1.kr(1/45),
			LFDNoise1.kr(1/51),
			LFDNoise1.kr(1/58),
			LFDNoise1.kr(1/63),
			LFDNoise1.kr(1/71),
			LFDNoise1.kr(1/77),
			LFDNoise1.kr(1/83)
		].linlin(-1, 1, 0.65, 1.35);
		weights = ([cosmicW, wonderW, hopefulW, kotoW, ragaW, pelogW, safir16W] * SelectX.kr(wEvolve, [1 ! 7, wDrift])).max(0.001);
		weightNorm = weights / (weights.sum + 1e-9);
		// Skalen als Frequenzverhaeltnisse zur root-Frequenz
		scaleCosmic  = [1, 9/8, 5/4, 4/3, 3/2, 5/3, 2];
		scaleWonder  = [1, 16/15, 9/8, 6/5, 4/3, 3/2, 8/5, 2];
		scaleHopeful = [1, 9/8, 5/4, 45/32, 3/2, 5/3, 15/8, 2];
		scaleKoto    = [1, 9/8, 4/3, 3/2, 16/9, 2];
		scaleRaga    = [1, 16/15, 6/5, 4/3, 3/2, 8/5, 9/5, 2];
		scalePelog   = [1, 1.07, 1.18, 1.32, 1.52, 1.74, 2];
		scaleSafir16 = [1, 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 9/5, 15/8, 2];

		chaosRateJitter = LinLin.kr(A2K.kr(LorenzL.ar(0.08)), -1, 1, 0.93, 1.07);
		trigRate = (((bpmS / 60) / 2) * chaosRateJitter).clip(0.05, 4);
		trig = Impulse.kr(trigRate) * tr * nGate * mGate;
		noteTrig = CoinGate.kr(densityCtrl, trig);
		// Wichtig fuer Live-Weights: Skala bei JEDEM Note-Trigger neu nach aktuellen Gewichten waehlen.
		scaleSel = TWChoose.kr(
			trig: noteTrig,
			array: [0, 1, 2, 3, 4, 5, 6],
			weights: weightNorm
		);

		scaleHz = Select.kr(
			scaleSel,
			[
				TChoose.kr(noteTrig, scaleCosmic),
				TChoose.kr(noteTrig, scaleWonder),
				TChoose.kr(noteTrig, scaleHopeful),
				TChoose.kr(noteTrig, scaleKoto),
				TChoose.kr(noteTrig, scaleRaga),
				TChoose.kr(noteTrig, scalePelog),
				TChoose.kr(noteTrig, scaleSafir16)
			]
		) * rtHz;

		// Filter-Multiplikatoren wie in Pd-Mix-Patches (LFO + Random + Chaos)
		lfoMul = SinOsc.kr(0.001).range(0.4, 2.5);
		rndMul = LFDNoise1.kr(1/600).range(0.65, 1.35);
		chaosMul = LFDNoise3.kr(1/17).range(0.72, 1.28);
		cutoff = (fBase * lfoMul * rndMul * chaosMul).clip(120, 14000);

		// Drone: harmonische Schichtung (sub + root + octave + fifth), leicht stereo-bewegt
		root = SinOsc.ar(rtHz);
		sub = SinOsc.ar(rtHz * 0.5) * 0.20;
		octave = (SinOsc.ar(rtHz * 2) + (Saw.ar(rtHz * 2) * 0.15)) * 0.24;
		fifth = SinOsc.ar(rtHz * 3) * 0.10;
		droneCore = (root * 0.44 + sub + octave + fifth) * dLvl * dGate;

		droneLfoL = SinOsc.kr(0.013).range(0.76, 1.0);
		droneLfoR = SinOsc.kr(0.017).range(0.76, 1.0);
		droneStereo = [droneCore * droneLfoL, droneCore * droneLfoR];

		// Notes: duale Detune-Voices + lange Ambient-Release-Zeit
		detuneA = 1.001;
		detuneB = 0.999;
		chaosPitchDrift = LinExp.kr(A2K.kr(LorenzL.ar(0.11)), -1, 1, 1 - (effectiveChaos * 0.03), 1 + (effectiveChaos * 0.03));
		noteHz = Lag.kr(scaleHz * chaosPitchDrift, 1.2);
		noteEnv = EnvGen.kr(Env.perc(0.02, 16.0, 0.7, curve: -4), gate: noteTrig);
		noteSig = (
			SinOsc.ar(noteHz * detuneA) +
			SinOsc.ar(noteHz * detuneB) +
			(Saw.ar(noteHz * 0.5) * 0.2)
		) * noteEnv * nLvl * 0.42;
		noteSig = [noteSig * SinOsc.kr(0.021).range(0.72, 1.0), noteSig * SinOsc.kr(0.029).range(0.72, 1.0)];
		safeMix = LinLin.kr(safeCtrl, 0, 1, 0, 1);
		notesCap = Lag.kr(SelectX.kr(safeMix, [0.85, 0.62]), 0.2);
		noteSig = noteSig.clip2(notesCap);

		// Texture + Noise Layer
		textureSig = HPF.ar(PinkNoise.ar(0.14), 500) * LPF.kr(SinOsc.kr(0.02).range(2800, 7600), 4);
		textureSig = textureSig ! 2 * texLvl * effectiveTex * tGate * 0.12;
		// Adaptive Ducking: wenn Notes prae gnant sind, geht Texture gezielt zurueck.
		notesEnergy = Amplitude.kr(Mix.ar(noteSig), 0.05, 0.25).clip(0, 1);
		textureDucker = (1 - (notesEnergy * textureDuckCtrl * 0.75)).clip(0.35, 1);
		textureSig = textureSig * textureDucker;
		textureCap = Lag.kr(SelectX.kr(safeMix, [0.28, 0.18]), 0.2);
		textureSig = textureSig.clip2(textureCap);

		noiseSig = SelectX.ar(noiseType.clip(0, 1), [WhiteNoise.ar(1), PinkNoise.ar(1)]);
		noiseSig = HPF.ar(noiseSig, 120) ! 2 * nzLvl * effectiveNoise * nzGate * 0.12;
		noiseCap = Lag.kr(SelectX.kr(safeMix, [0.2, 0.12]), 0.2);
		noiseSig = noiseSig.clip2(noiseCap);

		droneCap = Lag.kr(SelectX.kr(safeMix, [0.7, 0.55]), 0.2);
		droneStereo = droneStereo.clip2(droneCap);

		// Optionaler AUX-In Pfad (nur aktiv wenn Hardware-ADC/Input vorhanden).
		auxL = SoundIn.ar(0);
		auxR = SoundIn.ar(1);
		auxSig = [auxL, auxR] * auxGate * auxLvl;
		auxSig = HPF.ar(auxSig, 40);
		auxSig = LeakDC.ar(auxSig);
		auxSig = Compander.ar(auxSig, auxSig, 0.6, 1, 0.6, 0.01, 0.1);
		auxSig = auxSig.clip2(0.45);

		// Summenbus + Filter + Reverb-Proxy
		notesSoloMix = noteSig + (noiseSig * 0.12);
		dryL = droneStereo[0] + noteSig[0] + textureSig[0] + noiseSig[0] + (chLvl * 0.02) + (pdLvl * 0.01);
		dryR = droneStereo[1] + noteSig[1] + textureSig[1] + noiseSig[1] + (chLvl * 0.02) + (pdLvl * 0.01);
		dryL = dryL + (auxSig[0] * auxBlend);
		dryR = dryR + (auxSig[1] * auxBlend);
		dryL = SelectX.ar(mixModeSm, [dryL, notesSoloMix[0]]);
		dryR = SelectX.ar(mixModeSm, [dryR, notesSoloMix[1]]);
		dryL = RLPF.ar(dryL, cutoff, 0.55);
		dryR = RLPF.ar(dryR, cutoff * 0.99, 0.58);

		roomMulRnd = LFDNoise1.kr(1/600).range(0.75, 1.25);
		roomCtrl = (roomBase * roomMulRnd).clip(0.02, 0.88);
		// Reverb-Fallback: falls JPverb nicht verfuegbar ist, auf FreeVerb2 zurueckfallen.
		wetL = SelectX.ar(
			hasJPverb.if(1, 0),
			[
				FreeVerb2.ar(dryL, dryR, mix: roomCtrl.linlin(0.02, 0.88, 0.18, 0.68), room: 0.84, damp: 0.52)[0],
				JPverb.ar(dryL, t60: roomCtrl.linlin(0.02, 0.88, 0.8, 7.5), damp: 0.45, size: 2.8)
			]
		);
		wetR = SelectX.ar(
			hasJPverb.if(1, 0),
			[
				FreeVerb2.ar(dryL, dryR, mix: roomCtrl.linlin(0.02, 0.88, 0.18, 0.68), room: 0.84, damp: 0.52)[1],
				JPverb.ar(dryR, t60: roomCtrl.linlin(0.02, 0.88, 0.8, 7.5), damp: 0.43, size: 2.9)
			]
		);

		mix = XFade2.ar([dryL, dryR], [wetL, wetR], roomCtrl.linlin(0.02, 0.88, -0.4, 0.7));
		hpSafety = HPF.ar(mix, 20);

		// Anti-Clipping-Airbag: Soft-Clip + Limiter
		mix = LeakDC.ar(hpSafety);
		mix = tanh(mix * 1.10);
		outEnv = Amplitude.kr(Mix.ar(mix), 0.02, 0.2);
		gainGuard = SelectX.kr(protectOn, [1, (loudTarget / outEnv.max(loudTarget)).clip(0.45, 1)]);
		mix = mix * Lag.kr(gainGuard, 0.15);
		mix = Limiter.ar(mix, 0.95, 0.01);
		mix = Compander.ar(mix, mix, 0.55, 1, 0.45, 0.01, 0.12);

		Out.ar(out, mix * mVol * tr);
	}).add;

	s.sync;

	~uiControls = IdentityDictionary.new;
	~paramState = IdentityDictionary.new;
	~statePath = Platform.userAppSupportDir +/+ "shiftko_ambient_state.archive";
	~arrangementMacroPath = Platform.userAppSupportDir +/+ "shiftko_arrangement_macros.archive";
	~samplePaths = (
		breaks: [
			"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170bpm_AmenBreak_Tremen.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170BPM_AmenBreak_2,823sec.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170bpm_hotpants_2,823sek.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170BPM_Attack_Break_2,832sec.wav"
		],
		bass: [
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/19 Bass - 6A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/Aura Bass - 9B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/Illicit Bass - 9B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/Let Roll Bass - 2B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/Moomin 808 - 5A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/Type Bass - 4B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/bass/Worries Sub - 5A.wav"
		],
		fxCore: [
			"/Users/mrmouse/Developer/shiftkonew/samples/fx/core/Aura Rise - 3A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/fx/core/Centuries Vocode - 5B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/fx/core/Sonic Dolphins - 5A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/fx/core/Spring Metal - 9A.wav"
		],
		atmosPads: [
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/19 Pad - 6A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Apollo VCF Pad - 10B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Careless Pad - 6A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Connected Modu Pad - 6A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Face Pads - 7A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Freedom Pad - 5A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/God Chord Pad - 6A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Gravitational Pad - 9A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Inna Pad - 7B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Inner Pad - 11A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Reflections Pad - 3B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Revelation Pad - 1B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Seatown Pad - 5A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Ten Pad - 9B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Touch Vocal Pad - 8A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/pads/Western Pad.wav"
		],
		atmosVocals: [
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/vocals/All The People Vox - 8A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/vocals/Bouncer Vox.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/vocals/Peace Sign Vox - 7B.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/vocals/Soul Vox - 6A.wav",
			"/Users/mrmouse/Developer/shiftkonew/samples/atmos/vocals/Terrorist Vox Hit - 9A.wav"
		]
	);
	~sampleMeta = (
		"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170bpm_AmenBreak_Tremen.wav": (category: \break, sourceBpm: 170),
		"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170BPM_AmenBreak_2,823sec.wav": (category: \break, sourceBpm: 170),
		"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170bpm_hotpants_2,823sek.wav": (category: \break, sourceBpm: 170),
		"/Users/mrmouse/Developer/shiftkonew/samples/breaks/170BPM_Attack_Break_2,832sec.wav": (category: \break, sourceBpm: 170)
	);
	~getSampleMeta = { |path| ~sampleMeta[path] };
	~getSampleSourceBpm = { |path, fallback=170|
		var m = ~getSampleMeta.(path);
		(m.notNil and: { m[\sourceBpm].notNil }).if({ m[\sourceBpm] }, { fallback });
	};
	~breakPaths = ~samplePaths[\breaks];
	~bassPaths = ~samplePaths[\bass];
	~fxCorePaths = ~samplePaths[\fxCore];
	~atmosPadPaths = ~samplePaths[\atmosPads];
	~vocalPaths = ~samplePaths[\atmosVocals];
	~defaultDnbBreakPath = "/Users/mrmouse/Developer/shiftkonew/samples/breaks/170bpm_AmenBreak_Tremen.wav";
	~performanceSafeLock = false;
	~performanceSafeCaps = (
		masterVol: 0.45,
		textureLevel: 0.08,
		noiseLevel: 0.09,
		dnbVol: 0.55,
		dnbKickAmp: 0.7,
		dnbSidechainDepth: 0.35,
		reverbRoomBase: 0.65,
		dnbRev: 0.5
	);
	~defaultState = [
		\safeMode, 1, \mixMode, 0, \chaosDepth, 0.12, \textureDuck, 0.6, \weightEvolve, 0.18, \noteDensity, 0.9, \calmness, 0.62,
		\auxInEnable, 0, \auxInLevel, 0.0, \auxInBlend, 0.0,
		\autoGainProtect, 1, \loudnessTarget, 0.26,
		\dnbVol, 0.0, \dnbChaos, 0.3, \dnbRoll, 0.0, \dnbStutter, 0.08, \dnbBreakHPF, 90, \dnbKickAmp, 0.45, \dnbSidechainDepth, 0.18,
		\dnbRateOffset, 1.0, \dnbRev, 0.12, \dnbTargetBpm, 170, \dnbSourceBpm, 135,
		\textureLevel, 0.035, \noiseLevel, 0.03, \notesLevel, 0.55, \droneLevel, 0.56,
		\cosmicW, 70, \wonderW, 20, \hopefulW, 10, \kotoW, 0, \ragaW, 0, \pelogW, 0, \safir16W, 0
	];
	~setParam = { |param, value, syncUI=true|
		var v = value;
		if(~performanceSafeLock and: { ~performanceSafeCaps[param].notNil }) {
			v = v.min(~performanceSafeCaps[param]);
		};
		if(~setDnbParam.notNil and: { [\dnbVol, \dnbChaos, \dnbRoll, \dnbStutter, \dnbBreakHPF, \dnbKickAmp, \dnbSidechainDepth, \dnbRateOffset, \dnbRev, \dnbTargetBpm, \dnbSourceBpm].includes(param) }) {
			~setDnbParam.(param, v);
		};
		~paramState[param] = v;
		if(~shiftko.notNil) { ~shiftko.set(param, v); };
		if(syncUI and: { ~uiControls[param].notNil }) { ~uiControls[param][\set].(v); };
		if(~sendMidiFeedback.notNil) { ~sendMidiFeedback.(param, v); };
	};
	~applyParams = { |arr, syncUI=true|
		arr.clump(2).do { |pair| ~setParam.(pair[0], pair[1], syncUI); };
	};
	~saveState = {
		var d = IdentityDictionary.new;
		~paramState.keysValuesDo { |k, v| d[k] = v; };
		d.writeArchive(~statePath);
		"SHIFTKO state saved.".postln;
	};
	~loadState = {
		if(PathName(~statePath).isFile) {
			var d = Object.readArchive(~statePath);
			if(d.notNil) {
				d.keysValuesDo { |k, v| ~setParam.(k, v, true); };
				~lockAllMappedPickups.value;
				"SHIFTKO state loaded.".postln;
			};
		};
	};

	// Startinstanz
	~shiftko = Synth(\shiftkoAmbientMath);
	~applyParams.(~defaultState, false);
	~scenePresets = (
		safe: [\safeMode, 1, \mixMode, 0, \chaosDepth, 0.10, \textureDuck, 0.72, \weightEvolve, 0.10, \noteDensity, 0.82, \calmness, 0.78, \auxInEnable, 0, \auxInLevel, 0.0, \auxInBlend, 0.0, \autoGainProtect, 1, \loudnessTarget, 0.24, \dnbVol, 0.0, \dnbChaos, 0.25, \dnbRoll, 0.0, \dnbStutter, 0.06, \dnbBreakHPF, 120, \dnbKickAmp, 0.32, \dnbSidechainDepth, 0.14, \dnbRateOffset, 1.0, \dnbRev, 0.1, \textureLevel, 0.035, \noiseLevel, 0.03, \notesLevel, 0.52, \droneLevel, 0.55],
		focus: [\safeMode, 1, \mixMode, 0, \chaosDepth, 0.14, \textureDuck, 0.8, \weightEvolve, 0.08, \noteDensity, 0.95, \calmness, 0.7, \auxInEnable, 0, \auxInLevel, 0.0, \auxInBlend, 0.0, \autoGainProtect, 1, \loudnessTarget, 0.26, \dnbVol, 0.0, \dnbChaos, 0.35, \dnbRoll, 0.15, \dnbStutter, 0.10, \dnbBreakHPF, 90, \dnbKickAmp, 0.45, \dnbSidechainDepth, 0.18, \dnbRateOffset, 1.0, \dnbRev, 0.18, \textureLevel, 0.03, \noiseLevel, 0.025, \notesLevel, 0.62, \droneLevel, 0.5, \cosmicW, 20, \wonderW, 45, \hopefulW, 35, \kotoW, 0, \ragaW, 0, \pelogW, 0, \safir16W, 0],
		wild: [\safeMode, 0, \mixMode, 0, \chaosDepth, 0.24, \textureDuck, 0.45, \weightEvolve, 0.45, \noteDensity, 0.98, \calmness, 0.22, \auxInEnable, 0, \auxInLevel, 0.0, \auxInBlend, 0.0, \autoGainProtect, 1, \loudnessTarget, 0.3, \dnbVol, 0.0, \dnbChaos, 0.5, \dnbRoll, 0.25, \dnbStutter, 0.18, \dnbBreakHPF, 70, \dnbKickAmp, 0.6, \dnbSidechainDepth, 0.26, \dnbRateOffset, 1.05, \dnbRev, 0.22, \textureLevel, 0.08, \noiseLevel, 0.06, \notesLevel, 0.6, \droneLevel, 0.62]
	);
	~sceneMorph = 0.0;
	~pairsToDict = { |arr|
		var d = IdentityDictionary.new;
		arr.clump(2).do { |p| d[p[0]] = p[1]; };
		d;
	};
	~sceneMorphKeys = [
		\safeMode, \mixMode, \chaosDepth, \textureDuck, \weightEvolve, \noteDensity, \calmness, \autoGainProtect, \loudnessTarget,
		\dnbVol, \dnbChaos, \dnbRoll, \dnbStutter, \dnbBreakHPF, \dnbKickAmp, \dnbSidechainDepth, \dnbRateOffset, \dnbRev, \dnbTargetBpm, \dnbSourceBpm,
		\auxInEnable, \auxInLevel, \auxInBlend,
		\textureLevel, \noiseLevel, \notesLevel, \droneLevel,
		\cosmicW, \wonderW, \hopefulW, \kotoW, \ragaW, \pelogW, \safir16W
	];
	~applySceneMorph = { |morph=0.0|
		var m = morph.clip(0, 1);
		var a, b, t, da, db;
		var out = List.new;
		if(m <= 0.5) {
			a = ~scenePresets[\safe];
			b = ~scenePresets[\focus];
			t = m * 2;
		} {
			a = ~scenePresets[\focus];
			b = ~scenePresets[\wild];
			t = (m - 0.5) * 2;
		};
		da = ~pairsToDict.(a);
		db = ~pairsToDict.(b);
		~sceneMorphKeys.do { |k|
			var va = da[k] ? (~paramState[k] ? 0);
			var vb = db[k] ? va;
			var v = va + ((vb - va) * t);
			if(k == \safeMode or: { k == \mixMode or: { k == \auxInEnable } }) { v = (v >= 0.5).asInteger; };
			out.add(k); out.add(v);
		};
		~sceneMorph = m;
		~applyParams.(out.asArray, true);
		~lockPickupForParams.(~sceneMorphKeys);
		~currentScene = if(m < 0.34) { \safe } { if(m < 0.67) { \focus } { \wild } };
		~sendStatusFeedback.(\scene, (~sceneIndex.(~currentScene) + 1));
	};
	~applyScene = { |name|
		if(~shiftko.notNil and: { ~scenePresets[name].notNil }) {
			~currentScene = name;
			~sceneMorph = if(name == \safe) { 0.0 } { if(name == \focus) { 0.5 } { 1.0 } };
			~applyParams.(~scenePresets[name], true);
			~lockPickupForParams.(~scenePresets[name].clump(2).collect { |p| p[0] });
			~sendStatusFeedback.(\scene, (~sceneIndex.(name) + 1));
		};
	};
	~paramSpecs = (
		bpm: [30, 100, \lin], moodRaw: [0, 1, \lin], rootHz: [64, 768, \exp],
		filterCutoffBase: [120, 12000, \exp], reverbRoomBase: [0.001, 0.8, \lin], masterVol: [0.001, 0.55, \lin],
		droneLevel: [0.001, 0.8, \lin], notesLevel: [0.001, 0.8, \lin], noiseLevel: [0, 0.2, \lin], textureLevel: [0, 0.16, \lin],
		chaosDepth: [0, 0.4, \lin], textureDuck: [0, 1, \lin], weightEvolve: [0, 1, \lin], noteDensity: [0.2, 1, \lin], calmness: [0, 1, \lin],
		autoGainProtect: [0, 1, \lin], loudnessTarget: [0.12, 0.45, \lin],
		dnbVol: [0, 1, \lin], dnbChaos: [0, 1, \lin], dnbRoll: [0, 1, \lin], dnbStutter: [0, 0.35, \lin], dnbBreakHPF: [30, 1200, \exp], dnbKickAmp: [0, 1, \lin], dnbSidechainDepth: [0, 0.6, \lin], dnbRateOffset: [0.25, 2.0, \lin], dnbRev: [0, 1, \lin], dnbTargetBpm: [80, 220, \lin], dnbSourceBpm: [60, 220, \lin],
		auxInEnable: [0, 1, \lin], auxInLevel: [0, 0.9, \lin], auxInBlend: [0, 1, \lin]
	);
	~midiMap = (1: \textureLevel, 2: \notesLevel, 3: \droneLevel, 4: \masterVol, 5: \calmness, 6: \chaosDepth, 7: \weightEvolve, 8: \noteDensity, 9: \reverbRoomBase, 10: \filterCutoffBase, 11: \textureDuck, 12: \moodRaw, 13: \auxInLevel, 14: \auxInBlend, 15: \dnbVol, 16: \dnbChaos, 17: \dnbRoll, 18: \dnbRateOffset, 19: \dnbRev, 20: \dnbStutter, 21: \dnbBreakHPF, 22: \dnbKickAmp, 23: \dnbSidechainDepth);
	// Relative Encoder-Map (CC -> [Param, Step]). Decoder: Two's Complement / Sign-Magnitude tolerant.
	~encoderMap = (31: [\filterCutoffBase, 0.03], 32: [\reverbRoomBase, 0.025], 33: [\chaosDepth, 0.03], 34: [\noteDensity, 0.025]);
	// Feedback-MIDI (SC -> Teensy), CC layout frei anpassbar.
	~feedbackMap = (\textureLevel: 41, \notesLevel: 42, \droneLevel: 43, \masterVol: 44, \calmness: 45, \chaosDepth: 46, \weightEvolve: 47, \noteDensity: 48, \reverbRoomBase: 49, \filterCutoffBase: 50, \textureDuck: 51, \moodRaw: 52, \auxInEnable: 53, \auxInLevel: 54, \auxInBlend: 55);
	~feedbackMap.put(\dnbVol, 56).put(\dnbChaos, 57).put(\dnbRoll, 58).put(\dnbRateOffset, 59).put(\dnbRev, 66).put(\dnbTargetBpm, 67).put(\dnbSourceBpm, 68).put(\dnbStutter, 69).put(\dnbBreakHPF, 76).put(\dnbKickAmp, 77).put(\dnbSidechainDepth, 78);
	~feedbackQuantMidi = (\textureLevel: 1, \notesLevel: 1, \droneLevel: 1, \masterVol: 1, \calmness: 1, \chaosDepth: 1, \weightEvolve: 1, \noteDensity: 1, \reverbRoomBase: 1, \filterCutoffBase: 2, \textureDuck: 1, \moodRaw: 1, \auxInEnable: 1, \auxInLevel: 1, \auxInBlend: 1, \dnbVol: 1, \dnbChaos: 1, \dnbRoll: 1, \dnbRateOffset: 2, \dnbRev: 1, \dnbTargetBpm: 1, \dnbSourceBpm: 1, \dnbStutter: 1, \dnbBreakHPF: 2, \dnbKickAmp: 1, \dnbSidechainDepth: 1);
	~statusFeedbackMap = (\scene: 60, \safeMode: 61, \mixMode: 62, \autoScene: 63, \feedbackPage: 64, \midiFeedback: 65);
	~oledFeedbackMap = (masterVol: 70, filterCutoffBase: 71, dnbChaos: 72, reverbRoomBase: 73, bpm: 74, statusFlags: 75);
	~midiProfilePath = Platform.userAppSupportDir +/+ "shiftko_midi_profile.archive";
	~midiPickup = IdentityDictionary.new;
	~pickupLocked = IdentityDictionary.new;
	~strictPickupMode = true;
	~pickupOverride = false;
	~midiLastSent = IdentityDictionary.new;
	~encoderState = IdentityDictionary.new;
	~midiDebug = false;
	~midiFeedback = false;
	~midiOut = nil;
	~midiOutNameHint = "Teensy";
	~midiFeedbackLast = IdentityDictionary.new;
	~midiFeedbackDeadband = 1;
	~feedbackPages = (
		full: [\textureLevel, \notesLevel, \droneLevel, \masterVol, \calmness, \chaosDepth, \weightEvolve, \noteDensity, \reverbRoomBase, \filterCutoffBase, \textureDuck, \moodRaw, \auxInEnable, \auxInLevel, \auxInBlend, \dnbVol, \dnbChaos, \dnbRoll, \dnbStutter, \dnbBreakHPF, \dnbKickAmp, \dnbSidechainDepth, \dnbRateOffset, \dnbRev, \dnbTargetBpm, \dnbSourceBpm],
		performance: [\masterVol, \notesLevel, \droneLevel, \textureLevel, \noteDensity, \calmness],
		timbre: [\filterCutoffBase, \reverbRoomBase, \chaosDepth, \textureDuck, \weightEvolve, \moodRaw, \auxInBlend, \dnbRev],
		breakbeat: [\dnbVol, \dnbChaos, \dnbRoll, \dnbStutter, \dnbBreakHPF, \dnbKickAmp, \dnbSidechainDepth, \dnbRateOffset, \dnbRev, \dnbTargetBpm, \dnbSourceBpm],
		rhythm: [\noteDensity, \weightEvolve, \chaosDepth, \calmness, \notesLevel, \textureLevel]
	);
	~feedbackPage = \performance;
	~feedbackRateHz = 20;
	~oledAutoRateHz = 10;
	~oledAutoEnabled = false;
	~oledTask = nil;
	~midiFeedbackLastTime = IdentityDictionary.new;
	~currentScene = \safe;
	~learnMode = false;
	~learnTargetParam = \textureLevel;
	~learnTargetType = \absolute;
	~decodeRelative = { |val|
		// Common relative encodings:
		// 1..63 => +step ; 65..127 => -step ; 64/0 => no movement.
		if(val == 0 or: { val == 64 }) { 0 } {
			if(val <= 63) { 1 } { -1 }
		}
	};
	~countLockedPickups = {
		var c = 0;
		~pickupLocked.keysValuesDo { |k, v| if(v == true) { c = c + 1; }; };
		c;
	};
	~lockPickupForParams = { |params|
		params.do { |p|
			if(~midiMap.values.includes(p)) {
				~pickupLocked[p] = true;
				~midiPickup[p] = false;
			};
		};
	};
	~lockAllMappedPickups = {
		~lockPickupForParams.(~midiMap.values.asArray);
	};
	~stopMidi = {
		if(~ccDefs.notNil) { ~ccDefs.do { |d| d.free; }; };
		~ccDefs = List.new;
	};
	~removeCcFromMaps = { |cc|
		~midiMap.removeAt(cc);
		~encoderMap.removeAt(cc);
	};
	~saveMidiProfile = {
		var d = IdentityDictionary.new;
		d[\midiMap] = ~midiMap.copy;
		d[\encoderMap] = ~encoderMap.copy;
		d[\feedbackMap] = ~feedbackMap.copy;
		d[\feedbackQuantMidi] = ~feedbackQuantMidi.copy;
		d[\statusFeedbackMap] = ~statusFeedbackMap.copy;
		d.writeArchive(~midiProfilePath);
		"MIDI profile saved.".postln;
	};
	~loadMidiProfile = {
		if(PathName(~midiProfilePath).isFile) {
			var d = Object.readArchive(~midiProfilePath);
			if(d.notNil) {
				if(d[\midiMap].notNil) { ~midiMap = d[\midiMap].copy; };
				if(d[\encoderMap].notNil) { ~encoderMap = d[\encoderMap].copy; };
				if(d[\feedbackMap].notNil) { ~feedbackMap = d[\feedbackMap].copy; };
				if(d[\feedbackQuantMidi].notNil) { ~feedbackQuantMidi = d[\feedbackQuantMidi].copy; };
				if(d[\statusFeedbackMap].notNil) { ~statusFeedbackMap = d[\statusFeedbackMap].copy; };
				if(~strictPickupMode) { ~lockAllMappedPickups.value; };
				~setupMidi.value;
				~setupMidiOut.value;
				"MIDI profile loaded.".postln;
			};
		};
	};
	~setupMidiOut = {
		var idx = nil;
		MIDIClient.destinations.do { |ep, i|
			if(idx.isNil and: { ep.device.asString.contains(~midiOutNameHint) or: { ep.name.asString.contains(~midiOutNameHint) } }) {
				idx = i;
			};
		};
		if(idx.isNil and: { MIDIClient.destinations.size > 0 }) { idx = 0; };
		if(idx.notNil) {
			~midiOut = MIDIOut.new(idx);
			("MIDI out attached: " ++ MIDIClient.destinations[idx].device ++ " / " ++ MIDIClient.destinations[idx].name).postln;
		} {
			~midiOut = nil;
			"MIDI out not found.".postln;
		};
	};
	~toMidiVal = { |param, value|
		var spec = ~paramSpecs[param];
		if(spec.isNil) { value.clip(0, 127).round(1).asInteger } {
			(if(spec[2] == \exp) {
			value.clip(spec[0], spec[1]).explin(spec[0], spec[1], 0, 127)
		} {
			value.clip(spec[0], spec[1]).linlin(spec[0], spec[1], 0, 127)
		}).round(1).clip(0, 127).asInteger
		};
	};
	~feedbackPageContains = { |param|
		var active = ~feedbackPages[~feedbackPage] ? ~feedbackPages[\full];
		active.includes(param);
	};
	~feedbackPageIndex = { |name|
		var names = [\performance, \timbre, \rhythm, \breakbeat, \full];
		var idx = names.indexOf(name) ? 0;
		idx.asInteger;
	};
	~sceneIndex = { |name|
		var names = [\safe, \focus, \wild];
		var idx = names.indexOf(name) ? 0;
		idx.asInteger;
	};
	// -------------------------
	// DnB / Jungle Subsystem
	// -------------------------
	~dnb = (
		buf: nil,
		step: 0,
		player: nil,
		clock: TempoClock.new(170/60)
	);
	SynthDef(\dnbSlicePlayer, { |out=0, buf=0, slice=0, slicesTotal=16, amp=0.4, rate=1.0, pan=0, revMix=0.15, cutoff=15000, hpf=90|
		var sig, env, sliceFrames, startPos, dry, wet, cutoffSm, hpfSm;
		sliceFrames = BufFrames.kr(buf) / slicesTotal;
		startPos = slice * sliceFrames;
		env = EnvGen.kr(
			Env([0, 1, 1, 0], [0.003, 0.9, 0.06], [-4, 0, -4]),
			timeScale: (sliceFrames / SampleRate.ir) / rate.max(0.001),
			doneAction: 2
		);
		sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, startPos: startPos);
		hpfSm = Lag.kr(hpf.clip(30, 1200), 0.05);
		sig = HPF.ar(sig, hpfSm);
		cutoffSm = Lag.kr(cutoff.clip(100, 18000), 0.05);
		sig = RLPF.ar(sig, cutoffSm, 0.9);
		dry = Pan2.ar(sig * env, pan);
		wet = FreeVerb2.ar(dry[0], dry[1], mix: 0.35, room: 0.86, damp: 0.45);
		Out.ar(out, SelectX.ar(revMix.clip(0, 1), [dry, wet]) * amp);
	}).add;
	SynthDef(\dnbKick, { |out=0, amp=0.55, pan=0, revMix=0.03|
		var env, pitchEnv, body, click, sig, dry, wet;
		env = EnvGen.kr(Env.perc(0.0008, 0.22, curve: -8), doneAction: 2);
		pitchEnv = XLine.kr(190, 44, 0.045);
		body = SinOsc.ar(pitchEnv, 0, env);
		click = HPF.ar(WhiteNoise.ar(0.22), 2500) * EnvGen.kr(Env.perc(0.0005, 0.012, 1, -6));
		sig = (body + click).tanh;
		dry = Pan2.ar(sig * amp.clip(0, 1.0), pan.clip(-1, 1));
		wet = FreeVerb2.ar(dry[0], dry[1], mix: 0.25, room: 0.7, damp: 0.45);
		Out.ar(out, SelectX.ar(revMix.clip(0, 0.4), [dry, wet]));
	}).add;
	SynthDef(\vocalGranCloud, { |out=0, buf=0, gate=1, amp=0.14, rate=1.0, pos=0.5, posJitter=0.18, grainDur=0.16, density=10, panWidth=0.6, hpf=120, lpf=8500, revMix=0.2|
		var env, trig, centerPos, pan, sig, dry, wet;
		var rateSm, ampSm, posSm, jitterSm, durSm, densSm, panSm;
		rateSm = Lag.kr(rate.clip(0.25, 2.0), 0.08);
		ampSm = Lag.kr(amp.clip(0, 0.5), 0.08);
		posSm = Lag.kr(pos.clip(0, 1), 0.08);
		jitterSm = Lag.kr(posJitter.clip(0, 0.45), 0.1);
		durSm = Lag.kr(grainDur.clip(0.02, 0.5), 0.08);
		densSm = Lag.kr(density.clip(1, 80), 0.08);
		panSm = Lag.kr(panWidth.clip(0, 1), 0.1);
		env = EnvGen.kr(Env.asr(0.2, 1, 1.2), gate, doneAction: 2);
		trig = Dust.kr(densSm);
		centerPos = (posSm + LFNoise1.kr(6).range((0 - jitterSm), jitterSm)).clip(0.001, 0.999) * BufDur.kr(buf);
		pan = LFNoise1.kr(8).range((0 - panSm), panSm);
		sig = TGrains.ar(2, trig, buf, BufRateScale.kr(buf) * rateSm, centerPos, durSm, pan, 1.0, 4);
		dry = HPF.ar(LPF.ar(sig, lpf.clip(500, 14000)), hpf.clip(40, 1200));
		dry = LeakDC.ar(dry) * ampSm * env;
		wet = FreeVerb2.ar(dry[0], dry[1], mix: 0.28, room: 0.82, damp: 0.4);
		Out.ar(out, SelectX.ar(revMix.clip(0, 1), [dry, wet]));
	}).add;
	~setDnbParam = { |param, value|
		case
		{ param == \dnbVol } { ~dnb[\vol] = value.clip(0, 1) }
		{ param == \dnbChaos } { ~dnb[\chaos] = value.clip(0, 1) }
		{ param == \dnbRoll } { ~dnb[\roll] = value.clip(0, 1) }
		{ param == \dnbStutter } { ~dnb[\stutter] = value.clip(0, 0.35) }
		{ param == \dnbBreakHPF } { ~dnb[\breakHpf] = value.clip(30, 1200) }
		{ param == \dnbKickAmp } { ~dnb[\kickAmp] = value.clip(0, 1) }
		{ param == \dnbSidechainDepth } { ~dnb[\sidechainDepth] = value.clip(0, 0.6) }
		{ param == \dnbRateOffset } { ~dnb[\rateOffset] = value.clip(0.25, 2.0) }
		{ param == \dnbRev } { ~dnb[\rev] = value.clip(0, 1) }
		{ param == \dnbTargetBpm } {
			~dnb[\targetBpm] = value.clip(80, 220);
			if(~dnb[\clock].notNil) { ~dnb[\clock].tempo = (~dnb[\targetBpm] ? 170) / 60; };
		}
		{ param == \dnbSourceBpm } { ~dnb[\sourceBpm] = value.clip(60, 220) };
	};
	~setDnbParam.(\dnbVol, ~paramState[\dnbVol] ? 0.0);
	~setDnbParam.(\dnbChaos, ~paramState[\dnbChaos] ? 0.3);
	~setDnbParam.(\dnbRoll, ~paramState[\dnbRoll] ? 0.0);
	~setDnbParam.(\dnbStutter, ~paramState[\dnbStutter] ? 0.08);
	~setDnbParam.(\dnbBreakHPF, ~paramState[\dnbBreakHPF] ? 90);
	~setDnbParam.(\dnbKickAmp, ~paramState[\dnbKickAmp] ? 0.45);
	~setDnbParam.(\dnbSidechainDepth, ~paramState[\dnbSidechainDepth] ? 0.18);
	~setDnbParam.(\dnbRateOffset, ~paramState[\dnbRateOffset] ? 1.0);
	~setDnbParam.(\dnbRev, ~paramState[\dnbRev] ? 0.12);
	~setDnbParam.(\dnbTargetBpm, ~paramState[\dnbTargetBpm] ? 170);
	~setDnbParam.(\dnbSourceBpm, ~paramState[\dnbSourceBpm] ? 135);
	~loadDnbSample = { |path|
		if(path.notNil and: { path.size > 0 }) {
			if(~dnb[\buf].notNil) { ~dnb[\buf].free; };
			~dnb[\buf] = Buffer.read(s, path, action: { |b|
				("DnB sample loaded: " ++ path).postln;
			});
		};
	};
	~loadBreakByIndex = { |idx=0|
		var paths = ~breakPaths ? [];
		var path = paths.wrapAt(idx.asInteger);
		var bpm;
		if(path.notNil) {
			~loadDnbSample.(path);
			bpm = ~getSampleSourceBpm.(path, (~paramState[\dnbSourceBpm] ? 170));
			~setParam.(\dnbSourceBpm, bpm, true);
			("Break loaded [" ++ idx ++ "]: " ++ path ++ " | sourceBpm=" ++ bpm).postln;
		};
	};
	~makeDnbPattern = {
		Pbind(
			\instrument, \dnbSlicePlayer,
			\buf, Pfunc { ~dnb[\buf] ? 0 },
			\dur, Pfunc {
				var base = 0.25;
				var roll = (~dnb[\roll] ? 0).clip(0, 1);
				base * roll.linlin(0, 1, 1, 0.5)
			},
			\str, Pfunc {
				var chaos = (~dnb[\chaos] ? 0.2).clip(0, 1);
				var base = (~dnb[\stutter] ? 0.08).clip(0, 0.35);
				var stutterProb = (base + (chaos * 0.12)).clip(0, 0.35);
				if(1.0.rand < stutterProb) { [2, 3, 4].choose } { 1 }
			},
			\slice, Pdup(
				Pkey(\str),
				Pwrand(
					[
						Pfunc {
							var s = ~dnb[\step] ? 0;
							~dnb[\step] = (s + 1) % 16;
							s
						},
						Pfunc { 16.rand }
					],
					[0.8, 0.2],
					inf
				)
			),
			\rate, Pfunc {
				// Tempo-adaptive playback (not locked to 170):
				// rate = targetBpm / sourceBpm * rateOffset
				var target = (~dnb[\targetBpm] ? 170).clip(80, 220);
				var source = (~dnb[\sourceBpm] ? 135).clip(60, 220);
				var off = (~dnb[\rateOffset] ? 1.0).clip(0.25, 2.0);
				(target / source) * off
			},
			\hpf, Pfunc { (~dnb[\breakHpf] ? 90).clip(30, 1200) },
			\isGhost, Pwrand([0, 1], [0.8, 0.2], inf),
			\baseAmp, Pif(
				Pkey(\isGhost) > 0,
				Pfunc { (~dnb[\vol] ? 0.0).clip(0, 1) * 0.35 },
				Pfunc { (~dnb[\vol] ? 0.0).clip(0, 1) * 0.90 }
			),
			\sidechain, Pfunc { (~dnb[\sidechainDepth] ? 0.18).clip(0, 0.6) },
			\amp, Pkey(\baseAmp) * (1 - Pkey(\sidechain)),
			\cutoff, Pif(Pkey(\isGhost) > 0, 1200, 15000),
			\revMix, Pfunc { (~dnb[\rev] ? 0.12).clip(0, 1) },
			\pan, Pwhite(-0.12, 0.12, inf)
		)
	};
	~makeDnbKickPattern = {
		Pbind(
			\instrument, \dnbKick,
			\dur, 0.25,
			\isKick, Pseq([1, 0, 0, 0, 1, 0, 0, 0], inf),
			\amp, Pif(
				Pkey(\isKick) > 0,
				Pfunc { (~dnb[\kickAmp] ? 0.45).clip(0, 1) },
				0
			),
			\pan, 0,
			\revMix, 0.02
		)
	};
	~startDnb = {
		if(~dnb[\buf].isNil) {
			"DnB start aborted: load a sample first.".postln;
		} {
			~stopDnb.value;
			~dnb[\step] = 0;
			~dnb[\clock].tempo = (~dnb[\targetBpm] ? 170) / 60;
			~dnb[\player] = Ppar([~makeDnbPattern.value, ~makeDnbKickPattern.value], inf).play(~dnb[\clock], quant: 4);
			"DnB player started.".postln;
		};
	};
	~stopDnb = {
		if(~dnb[\player].notNil) { ~dnb[\player].stop; ~dnb[\player] = nil; };
		"DnB player stopped.".postln;
	};
	~toggleDnb = {
		if(~dnb[\player].notNil) {
			~stopDnb.value;
		} {
			if(~dnb[\buf].isNil and: { (~breakPaths ? []).notEmpty }) {
				~loadBreakByIndex.((~breakPaths ? []).size.rand);
			};
			~startDnb.value;
		};
	};
	// -------------------------
	// Vocal Granular Subsystem
	// -------------------------
	~vocal = (
		buf: nil, synth: nil, idx: 0,
		amp: 0.14, rate: 1.0, pos: 0.5, posJitter: 0.18, grainDur: 0.16, density: 10,
		panWidth: 0.6, hpf: 120, lpf: 8500, rev: 0.2
	);
	~setVocalParam = { |param, value|
		case
		{ param == \vocalAmp } { ~vocal[\amp] = value.clip(0, 0.5) }
		{ param == \vocalRate } { ~vocal[\rate] = value.clip(0.25, 2.0) }
		{ param == \vocalPos } { ~vocal[\pos] = value.clip(0, 1) }
		{ param == \vocalJitter } { ~vocal[\posJitter] = value.clip(0, 0.45) }
		{ param == \vocalGrainDur } { ~vocal[\grainDur] = value.clip(0.02, 0.5) }
		{ param == \vocalDensity } { ~vocal[\density] = value.clip(1, 80) }
		{ param == \vocalPanWidth } { ~vocal[\panWidth] = value.clip(0, 1) }
		{ param == \vocalHpf } { ~vocal[\hpf] = value.clip(40, 1200) }
		{ param == \vocalLpf } { ~vocal[\lpf] = value.clip(500, 14000) }
		{ param == \vocalRev } { ~vocal[\rev] = value.clip(0, 1) };
		if(~vocal[\synth].notNil) {
			~vocal[\synth].set(
				\amp, ~vocal[\amp], \rate, ~vocal[\rate], \pos, ~vocal[\pos], \posJitter, ~vocal[\posJitter],
				\grainDur, ~vocal[\grainDur], \density, ~vocal[\density], \panWidth, ~vocal[\panWidth],
				\hpf, ~vocal[\hpf], \lpf, ~vocal[\lpf], \revMix, ~vocal[\rev]
			);
		};
	};
	~loadVocalSample = { |path|
		if(path.notNil and: { path.size > 0 }) {
			if(~vocal[\buf].notNil) { ~vocal[\buf].free; };
			~vocal[\buf] = Buffer.read(s, path, action: { ("Vocal loaded: " ++ path).postln; });
			~vocal[\path] = path;
		};
	};
	~loadVocalByIndex = { |idx=0|
		var paths = ~vocalPaths ? [];
		var path = paths.wrapAt(idx.asInteger);
		if(path.notNil) {
			~vocal[\idx] = idx.asInteger;
			~loadVocalSample.(path);
		};
	};
	~startVocalGranular = {
		if(~vocal[\buf].isNil) {
			"Vocal start aborted: load a vocal sample first.".postln;
		} {
			~stopVocalGranular.value;
			~vocal[\synth] = Synth(\vocalGranCloud, [
				\out, ~mainOutBus ? 0, \buf, ~vocal[\buf],
				\amp, ~vocal[\amp], \rate, ~vocal[\rate], \pos, ~vocal[\pos], \posJitter, ~vocal[\posJitter],
				\grainDur, ~vocal[\grainDur], \density, ~vocal[\density], \panWidth, ~vocal[\panWidth],
				\hpf, ~vocal[\hpf], \lpf, ~vocal[\lpf], \revMix, ~vocal[\rev]
			]);
			"Vocal granular started.".postln;
		};
	};
	~stopVocalGranular = {
		if(~vocal[\synth].notNil) { ~vocal[\synth].set(\gate, 0); ~vocal[\synth] = nil; };
		"Vocal granular stopped.".postln;
	};
	~toggleVocalGranular = {
		if(~vocal[\synth].notNil) {
			~stopVocalGranular.value;
		} {
			if(~vocal[\buf].isNil and: { (~vocalPaths ? []).notEmpty }) {
				~loadVocalByIndex.((~vocalPaths ? []).size.rand);
			};
			~startVocalGranular.value;
		};
	};
	~sendStatusFeedback = { |name, value|
		var cc, v;
		if(~midiFeedback.not or: { ~midiOut.isNil }) { nil } {
			cc = ~statusFeedbackMap[name];
			if(cc.notNil) {
				v = value.clip(0, 127).asInteger;
				~midiOut.control(0, cc.asInteger, v);
				if(~midiDebug) { ("[MIDI OUT STATUS] " ++ name ++ " cc:" ++ cc ++ " val:" ++ v).postln; };
			};
		};
	};
	~oledStatusFlags = {
		var v = 0;
		if((~paramState[\safeMode] ? 1) > 0.5) { v = v + 1 };      // bit 0
		if(~autoSceneEnabled) { v = v + 2 };                        // bit 1
		if(~midiFeedback) { v = v + 4 };                            // bit 2
		if(~dnb.notNil and: { ~dnb[\player].notNil }) { v = v + 8 };// bit 3
		v.clip(0, 127).asInteger;
	};
	~sendOledFrame = {
		var send = { |cc, val|
			if(~midiFeedback and: { ~midiOut.notNil }) {
				~midiOut.control(0, cc.asInteger, val.clip(0, 127).asInteger);
			};
		};
		send.(~oledFeedbackMap[\masterVol], ~toMidiVal.(\masterVol, ~paramState[\masterVol] ? 0.4));
		send.(~oledFeedbackMap[\filterCutoffBase], ~toMidiVal.(\filterCutoffBase, ~paramState[\filterCutoffBase] ? 1800));
		send.(~oledFeedbackMap[\dnbChaos], ~toMidiVal.(\dnbChaos, ~paramState[\dnbChaos] ? 0.3));
		send.(~oledFeedbackMap[\reverbRoomBase], ~toMidiVal.(\reverbRoomBase, ~paramState[\reverbRoomBase] ? 0.4));
		send.(~oledFeedbackMap[\bpm], ((~paramState[\bpm] ? 60).linlin(30, 100, 0, 127)).clip(0, 127));
		send.(~oledFeedbackMap[\statusFlags], ~oledStatusFlags.value);
		if(~midiDebug) { "[OLED FRAME] sent".postln; };
	};
	~stopOledTask = {
		if(~oledTask.notNil) { ~oledTask.stop; ~oledTask = nil; };
		~oledAutoEnabled = false;
	};
	~startOledTask = {
		~stopOledTask.value;
		~oledAutoEnabled = true;
		~oledTask = Task({
			inf.do {
				~sendOledFrame.value;
				(1.0 / (~oledAutoRateHz ? 10).clip(1, 30)).wait;
			}
		}).play(AppClock);
	};
	~sendMidiFeedback = { |param, value, force=false|
		var cc, midiVal, q, last, now, lastT, minInterval;
		if(~midiFeedback.not or: { ~midiOut.isNil }) { nil } {
		if((~feedbackPageContains.(param).not) and: { force.not }) { nil } {
		cc = ~feedbackMap[param];
		if(cc.isNil) { nil } {
		midiVal = ~toMidiVal.(param, value);
		q = ~feedbackQuantMidi[param] ? 1;
		midiVal = ((midiVal / q).round * q).clip(0, 127).asInteger;
		last = ~midiFeedbackLast[param] ? -999;
		now = Main.elapsedTime;
		lastT = ~midiFeedbackLastTime[cc] ? 0.0;
		minInterval = 1.0 / ((~feedbackRateHz ? 20).clip(1, 120));
		if(force or: { ((midiVal - last).abs >= ~midiFeedbackDeadband) and: { (now - lastT) >= minInterval } }) {
			~midiFeedbackLast[param] = midiVal;
			~midiFeedbackLastTime[cc] = now;
			~midiOut.control(0, cc.asInteger, midiVal);
			if(~midiDebug) { ("[MIDI OUT] cc:" ++ cc ++ " param:" ++ param ++ " val:" ++ midiVal ++ " page:" ++ ~feedbackPage).postln; };
		};
		};
		};
		};
	};
	~sendFeedbackPageSnapshot = {
		var active = ~feedbackPages[~feedbackPage] ? ~feedbackPages[\full];
		active.do { |p|
			var v = ~paramState[p];
			if(v.notNil) { ~sendMidiFeedback.(p, v, true); };
		};
		~sendStatusFeedback.(\scene, (~sceneIndex.(~currentScene) + 1));
		~sendStatusFeedback.(\safeMode, (~paramState[\safeMode] ? 1).asInteger);
		~sendStatusFeedback.(\mixMode, (~paramState[\mixMode] ? 0).asInteger);
		~sendStatusFeedback.(\autoScene, if(~autoSceneEnabled) { 1 } { 0 });
		~sendStatusFeedback.(\feedbackPage, ~feedbackPageIndex.(~feedbackPage));
		~sendStatusFeedback.(\midiFeedback, if(~midiFeedback) { 1 } { 0 });
	};
	~setupMidi = {
		~stopMidi.value;
		MIDIClient.init; MIDIIn.connectAll;
		~ccDefs = List.new;
		~ccDefs.add(
			MIDIdef.cc(\shiftko_learn_capture, { |val, ccNum|
				if(~learnMode) {
					var cc = ccNum.asInteger;
					~removeCcFromMaps.(cc);
					if(~learnTargetType == \absolute) {
						~midiMap[cc] = ~learnTargetParam;
						("[MIDI LEARN] ABS cc:" ++ cc ++ " -> " ++ ~learnTargetParam).postln;
					} {
						~encoderMap[cc] = [~learnTargetParam, 0.03];
						("[MIDI LEARN] ENC cc:" ++ cc ++ " -> " ++ ~learnTargetParam).postln;
					};
					~learnMode = false;
					AppClock.sched(0.0, { ~setupMidi.value; nil });
				};
			})
		);
		~midiMap.keysValuesDo { |cc, param|
			var spec = ~paramSpecs[param];
			var min = spec[0], max = spec[1], curve = spec[2];
			~ccDefs.add(
				MIDIdef.cc(("shiftko_cc_" ++ cc).asSymbol, { |val|
					var mapped, cur, picked, tol, strictLocked;
					var last, deadband;
					mapped = if(curve == \exp) { val.linexp(0, 127, min, max) } { val.linlin(0, 127, min, max) };
					cur = ~paramState[param] ? mapped;
					picked = ~midiPickup[param] ? false;
					strictLocked = (~strictPickupMode and: { (~pickupOverride.not) and: { (~pickupLocked[param] ? false) } });
					tol = (max - min) * 0.06;
					last = ~midiLastSent[param] ? cur;
					deadband = (max - min) * 0.012;
					if(strictLocked) {
						if((cur - mapped).abs <= tol) {
							~pickupLocked[param] = false;
							~midiPickup[param] = true;
							if(~midiDebug) { ("[MIDI PICKUP] unlocked param:" ++ param).postln; };
						};
					} {
						if(picked or: { (cur - mapped).abs <= tol }) {
							~midiPickup[param] = true;
							if((mapped - last).abs >= deadband) {
								~midiLastSent[param] = mapped;
								~setParam.(param, mapped, true);
								if(~midiDebug) {
									("[MIDI ABS] cc:" ++ cc ++ " param:" ++ param ++ " raw:" ++ val ++ " mapped:" ++ mapped.round(0.0001)).postln;
								};
							};
						};
					};
				}, cc.asInteger)
			);
		};
		~encoderMap.keysValuesDo { |cc, specArr|
			var param = specArr[0], step = specArr[1];
			var spec = ~paramSpecs[param];
			var min = spec[0], max = spec[1];
			~ccDefs.add(
				MIDIdef.cc(("shiftko_enc_" ++ cc).asSymbol, { |val|
					var dir, cur, next;
					dir = ~decodeRelative.(val);
					if(dir != 0) {
						cur = ~paramState[param] ? min;
						next = (cur + (dir * (max - min) * step)).clip(min, max);
						~encoderState[param] = next;
						~setParam.(param, next, true);
						if(~midiDebug) {
							("[MIDI ENC] cc:" ++ cc ++ " param:" ++ param ++ " raw:" ++ val ++ " dir:" ++ dir ++ " next:" ++ next.round(0.0001)).postln;
						};
					};
				}, cc.asInteger)
			);
		};
		"MIDI mapped with pickup mode.".postln;
	};
	~runSelfTest = {
		("SC ready: " ++ s.serverRunning).postln;
		("JPverb available: " ++ hasJPverb).postln;
		if(~shiftko.notNil) {
			~setParam.(\masterVol, (~paramState[\masterVol] ? 0.4).clip(0.001, 0.55), true);
			~setParam.(\textureLevel, (~paramState[\textureLevel] ? 0.035).clip(0, 0.16), true);
			~setParam.(\notesLevel, (~paramState[\notesLevel] ? 0.55).clip(0.001, 0.8), true);
		};
		"Selftest done.".postln;
	};
	~panicSilence = {
		// Sofortige Notbremse fuer Live-Situationen (ohne harten Prozessabbruch)
		~applyParams.([
			\transport, 0,
			\droneGate, 0, \notesGate, 0, \noiseGate, 0, \textureGate, 0,
			\masterVol, 0.001,
			\auxInEnable, 0, \auxInLevel, 0.0, \auxInBlend, 0.0
		], true);
		~stopAutoScenes.value;
		"PANIC: output silenced.".postln;
	};
	~restoreFromSceneState = {
		~applyParams.(~defaultState, true);
		~lockPickupForParams.(~defaultState.clump(2).collect { |p| p[0] });
		~applyScene.(~currentScene ? \safe);
		"Restored from scene/default state.".postln;
	};
	~openVisualDashboard = {
		if(~visualWin.notNil) { ~visualWin.close; };
		~visualWin = Window("SHIFTKO Visual Dashboard", Rect(1180, 80, 420, 340)).front.alwaysOnTop_(true);
		~visualWin.view.background = Color.black;
		StaticText(~visualWin, Rect(10, 8, 400, 18))
			.string_("Low-CPU Visuals (AppClock-safe)")
			.stringColor_(Color.white);
		~visualView = UserView(~visualWin, Rect(10, 30, 400, 280))
			.background_(Color.black)
			.animate_(true)
			.frameRate_(12)
			.drawFunc_({
				var vol = (~paramState[\masterVol] ? 0.4).linlin(0.001, 0.55, 0, 1).clip(0, 1);
				var cut = (~paramState[\filterCutoffBase] ? 1800).linlog(120, 12000, 0, 1).clip(0, 1);
				var dnb = (~paramState[\dnbVol] ? 0).clip(0, 1);
				var rev = (~paramState[\reverbRoomBase] ? 0.4).linlin(0.001, 0.8, 0, 1).clip(0, 1);
				var cpu = (s.avgCPU ? 0).linlin(0, 100, 0, 1).clip(0, 1);
				var scene = (~currentScene ? \safe).asString;
				var auto = (~autoSceneEnabled ? false);
				var midiFb = (~midiFeedback ? false);
				var cpuG = (~autoCpuGuard ? true);
				var t = Main.elapsedTime;
				var drawWave = { |x, y, w, h|
					var steps = 48;
					Pen.color = Color.gray(0.25);
					Pen.addRect(Rect(x, y, w, h));
					Pen.stroke;
					Pen.color = Color.cyan(0.9);
					steps.do { |i|
						var px = x + (i / (steps - 1)) * w;
						var ph = (sin((i * 0.35) + (t * 2.2)) * 0.35
							+ sin((i * 0.9) + (t * 1.1)) * 0.2
							+ (dnb * 0.25)) * (h * 0.45);
						var py = y + (h * 0.5) + ph;
						if(i == 0) { Pen.moveTo(Point(px, py)); } { Pen.lineTo(Point(px, py)); };
					};
					Pen.stroke;
				};
				var drawLamp = { |x, y, label, on, onColor|
					Pen.color = on.if(onColor, Color.gray(0.25));
					Pen.fillOval(Rect(x, y, 10, 10));
					Pen.color = Color.white;
					Pen.stringAtPoint(label, Point(x + 14, y + 9));
				};
				var drawBar = { |y, value, label, col|
					Pen.color = Color.gray(0.2);
					Pen.addRect(Rect(10, y, 380, 24));
					Pen.fill;
					Pen.color = col;
					Pen.addRect(Rect(10, y, 380 * value, 24));
					Pen.fill;
					Pen.color = Color.white;
					Pen.stringAtPoint(label ++ "  " ++ (value * 100).round(1) ++ "%", Point(14, y + 16));
				};
				Pen.fillColor = Color.black;
				Pen.fillRect(Rect(0, 0, 400, 280));
				drawBar.(12, vol, "Master", Color.green(0.8));
				drawBar.(48, cut, "Cutoff", Color.cyan(0.8));
				drawBar.(84, dnb, "DnB", Color.magenta(0.8));
				drawBar.(120, rev, "Reverb", Color.blue(0.8));
				drawBar.(156, cpu, "CPU", Color.red(0.8));
				drawWave.(10, 194, 260, 44);
				Pen.color = Color.white;
				Pen.stringAtPoint("Scene: " ++ scene, Point(280, 206));
				drawLamp.(280, 218, "AUTO", auto, Color.green(0.8));
				drawLamp.(280, 234, "MIDI FB", midiFb, Color.cyan(0.8));
				drawLamp.(280, 250, "CPU GUARD", cpuG, Color.yellow(0.85));
			});
		~visualWin.onClose_({
			if(~visualView.notNil) { ~visualView.animate_(false); };
		});
	};
	~closeVisualDashboard = {
		if(~visualWin.notNil) { ~visualWin.close; ~visualWin = nil; };
	};
	~snapshotA = nil;
	~snapshotB = nil;
	~undoSnapshot = nil;
	~mutateAmount = 0.22;
	~captureSnapshot = { |slot=\A|
		var arr = List.new;
		~paramState.keysValuesDo { |k, v| arr.add(k); arr.add(v); };
		if(slot == \A) { ~snapshotA = arr.asArray } { ~snapshotB = arr.asArray };
		("Snapshot " ++ slot ++ " captured.").postln;
	};
	~loadSnapshot = { |slot=\A|
		var arr = if(slot == \A) { ~snapshotA } { ~snapshotB };
		if(arr.notNil) {
			~applyParams.(arr, true);
			~lockPickupForParams.(arr.clump(2).collect { |p| p[0] });
			("Snapshot " ++ slot ++ " loaded.").postln;
		} {
			("Snapshot " ++ slot ++ " is empty.").postln;
		};
	};
	~captureUndo = {
		var arr = List.new;
		~paramState.keysValuesDo { |k, v| arr.add(k); arr.add(v); };
		~undoSnapshot = arr.asArray;
	};
	~undoLastMutation = {
		if(~undoSnapshot.notNil) {
			~applyParams.(~undoSnapshot, true);
			"Undo mutation restored.".postln;
		} {
			"Undo empty.".postln;
		};
	};
	~mutateState = {
		var amount = (~mutateAmount ? 0.22).clip(0.02, 0.8);
		var keys = [\chaosDepth, \weightEvolve, \noteDensity, \calmness, \textureDuck, \textureLevel, \noiseLevel, \notesLevel, \droneLevel, \reverbRoomBase, \filterCutoffBase, \moodRaw];
		var out = List.new;
		~captureUndo.value;
		keys.do { |k|
			var spec = ~paramSpecs[k];
			var min = spec[0], max = spec[1], curve = spec[2];
			var cur = ~paramState[k] ? ((min + max) * 0.5);
			var span = (max - min);
			var jitter = if(curve == \exp) {
				var f = (1 + rrand((0 - amount), amount)).clip(0.2, 5.0);
				(cur * f).clip(min, max);
			} {
				(cur + (span * amount * rrand(-1.0, 1.0))).clip(min, max);
			};
			out.add(k); out.add(jitter);
		};
		// Weights separat leicht mutieren und normalisiert in 0..100 halten
		{
			var wk = [\cosmicW, \wonderW, \hopefulW, \kotoW, \ragaW, \pelogW, \safir16W];
			var vals = wk.collect { |k| ((~paramState[k] ? 0) + rrand(-30.0, 30.0) * amount).clip(0, 100) };
			var sum = vals.sum.max(1);
			vals = vals.collect { |v| ((v / sum) * 100).clip(0, 100) };
			wk.do { |k, i| out.add(k); out.add(vals[i]); };
		}.value;
		~applyParams.(out.asArray, true);
		"Mutate applied (controlled).".postln;
	};
	~autoCpuGuard = true;
	~cpuGuardState = \normal;
	~cpuGuardHigh = 62.0;
	~cpuGuardRecover = 45.0;
	~applyCpuGuard = { |avgCpu|
		if(~autoCpuGuard.not) { nil } {
		if((avgCpu >= ~cpuGuardHigh) and: { ~cpuGuardState != \throttled }) {
			~cpuGuardState = \throttled;
			~applyParams.([
				\textureLevel, ((~paramState[\textureLevel] ? 0.03) * 0.55).clip(0, 0.16),
				\noiseLevel, ((~paramState[\noiseLevel] ? 0.03) * 0.6).clip(0, 0.2),
				\noteDensity, ((~paramState[\noteDensity] ? 0.9) * 0.82).clip(0.2, 1.0),
				\weightEvolve, ((~paramState[\weightEvolve] ? 0.18) * 0.7).clip(0, 1),
				\auxInBlend, ((~paramState[\auxInBlend] ? 0.0) * 0.7).clip(0, 1)
			], true);
			"[CPU GUARD] throttled mode enabled.".postln;
		};
		if((avgCpu <= ~cpuGuardRecover) and: { ~cpuGuardState != \normal }) {
			~cpuGuardState = \normal;
			"[CPU GUARD] normal mode restored.".postln;
		};
		};
	};
	~scenePeriod = 55.0;
	~autoSceneOrder = [\safe, \focus, \wild];
	~autoSceneEnabled = false;
	~stopAutoScenes = {
		if(~autoSceneTask.notNil) { ~autoSceneTask.stop; ~autoSceneTask = nil; };
		~autoSceneEnabled = false;
		~sendStatusFeedback.(\autoScene, 0);
	};
	~startAutoScenes = {
		~stopAutoScenes.value;
		~autoSceneEnabled = true;
		~sendStatusFeedback.(\autoScene, 1);
		~autoSceneTask = Task({
			var idx = 0;
			inf.do {
				~applyScene.(~autoSceneOrder.wrapAt(idx));
				idx = idx + 1;
				(~scenePeriod ? 55.0).wait;
			}
		}).play(AppClock);
	};
	// Arrangement-Autopilot: kontrollierter Ablauf statt Dauer-Vollgas.
	~arrangementEnabled = false;
	~arrangementTask = nil;
	~arrangementPhase = \idle;
	~arrangementDurations = (intro: 48, drop: 64, breakdown: 32);
	~arrangementPhaseSets = (
		intro: [\dnbVol, 0.22, \dnbKickAmp, 0.25, \dnbSidechainDepth, 0.12, \dnbStutter, 0.06, \dnbRev, 0.2, \dnbRoll, 0.05],
		drop: [\dnbVol, 0.46, \dnbKickAmp, 0.58, \dnbSidechainDepth, 0.22, \dnbStutter, 0.12, \dnbRev, 0.12, \dnbRoll, 0.2],
		breakdown: [\dnbVol, 0.12, \dnbKickAmp, 0.08, \dnbSidechainDepth, 0.08, \dnbStutter, 0.04, \dnbRev, 0.26, \dnbRoll, 0.0]
	);
	~arrangementEditableParams = [\dnbVol, \dnbKickAmp, \dnbSidechainDepth, \dnbStutter, \dnbRev, \dnbRoll, \dnbBreakHPF, \dnbRateOffset, \dnbChaos];
	~getArrangementParam = { |phase=\intro, param=\dnbVol|
		var arr = ~arrangementPhaseSets[phase] ? [];
		var d = ~pairsToDict.(arr);
		if(d[param].isNil) { ~paramState[param] ? (~defaultState.clump(2).detect { |p| p[0] == param } ? [param, 0])[1] } { d[param] };
	};
	~setArrangementParam = { |phase=\intro, param=\dnbVol, value=0.0, applyNow=false|
		var arr = ~arrangementPhaseSets[phase] ? [];
		var d = ~pairsToDict.(arr);
		var spec = ~paramSpecs[param];
		var min = spec[0], max = spec[1];
		var v = value.clip(min, max);
		var out = List.new;
		d[param] = v;
		d.keysValuesDo { |k, vv| out.add(k); out.add(vv); };
		~arrangementPhaseSets[phase] = out.asArray;
		if(applyNow and: { ~arrangementPhase == phase }) {
			~setParam.(param, v, true);
			~lockPickupForParams.([param]);
		};
	};
	~arrangementMacros = IdentityDictionary.new;
	~saveArrangementMacrosFile = {
		var d = IdentityDictionary.new;
		~arrangementMacros.keysValuesDo { |k, v| d[k] = v; };
		d.writeArchive(~arrangementMacroPath);
		"Arrangement macro file saved.".postln;
	};
	~loadArrangementMacrosFile = {
		if(PathName(~arrangementMacroPath).isFile) {
			var d = Object.readArchive(~arrangementMacroPath);
			if(d.notNil) {
				~arrangementMacros = IdentityDictionary.new;
				d.keysValuesDo { |k, v| ~arrangementMacros[k] = v; };
				"Arrangement macro file loaded.".postln;
			};
		};
	};
	~saveArrangementMacro = { |slot=\A|
		~arrangementMacros[slot] = (
			durations: ~arrangementDurations.copy,
			phases: ~arrangementPhaseSets.copy
		);
		~saveArrangementMacrosFile.value;
		("Arrangement macro saved to slot " ++ slot).postln;
	};
	~loadArrangementMacro = { |slot=\A|
		var macro = ~arrangementMacros[slot];
		if(macro.notNil) {
			~arrangementDurations = (macro[\durations] ? ~arrangementDurations).copy;
			~arrangementPhaseSets = (macro[\phases] ? ~arrangementPhaseSets).copy;
			~lockPickupForParams.(~arrangementPhaseSets[\intro].clump(2).collect { |p| p[0] });
			~lockPickupForParams.(~arrangementPhaseSets[\drop].clump(2).collect { |p| p[0] });
			~lockPickupForParams.(~arrangementPhaseSets[\breakdown].clump(2).collect { |p| p[0] });
			if(~arrIntroDurBox.notNil) { { ~arrIntroDurBox.value = (~arrangementDurations[\intro] ? 48); }.defer; };
			if(~arrDropDurBox.notNil) { { ~arrDropDurBox.value = (~arrangementDurations[\drop] ? 64); }.defer; };
			if(~arrBreakDurBox.notNil) { { ~arrBreakDurBox.value = (~arrangementDurations[\breakdown] ? 32); }.defer; };
			("Arrangement macro loaded from slot " ++ slot).postln;
		} {
			("Arrangement macro slot empty: " ++ slot).postln;
		};
	};
	~arrangementStatusText = nil;
	~setArrangementPhase = { |name|
		~arrangementPhase = name;
		if(~arrangementPhaseSets[name].notNil) { ~applyParams.(~arrangementPhaseSets[name], true); };
		if(~arrangementPhaseSets[name].notNil) { ~lockPickupForParams.(~arrangementPhaseSets[name].clump(2).collect { |p| p[0] }); };
		if(name == \intro) { ~applyScene.(\safe); };
		if(name == \drop) { ~applyScene.(\focus); };
		if(name == \breakdown) { ~applyScene.(\safe); };
		if(~arrangementStatusText.notNil) {
			{ ~arrangementStatusText.string = "Arrangement: " ++ name.asString; }.defer;
		};
	};
	~applyArrangementPhaseNow = { |phase=\intro|
		if(~arrangementPhaseSets[phase].notNil) {
			~arrangementPhase = phase;
			~applyParams.(~arrangementPhaseSets[phase], true);
			~lockPickupForParams.(~arrangementPhaseSets[phase].clump(2).collect { |p| p[0] });
			if(~arrangementStatusText.notNil) {
				{ ~arrangementStatusText.string = "Arrangement: " ++ phase.asString ++ " (manual)"; }.defer;
			};
		};
	};
	~stopArrangement = {
		if(~arrangementTask.notNil) { ~arrangementTask.stop; ~arrangementTask = nil; };
		~arrangementEnabled = false;
		~arrangementPhase = \idle;
		if(~arrangementStatusText.notNil) {
			{ ~arrangementStatusText.string = "Arrangement: idle"; }.defer;
		};
	};
	~startArrangement = {
		~stopArrangement.value;
		~arrangementEnabled = true;
		~arrangementTask = Task({
			if(~dnb[\player].isNil) { ~startDnb.value; };
			inf.do {
				~setArrangementPhase.(\intro);
				(~arrangementDurations[\intro] ? 48).wait;
				~setArrangementPhase.(\drop);
				(~arrangementDurations[\drop] ? 64).wait;
				~setArrangementPhase.(\breakdown);
				(~arrangementDurations[\breakdown] ? 32).wait;
			}
		}).play(AppClock);
	};

	// Live-Performance-UI: Slider, Buttons und Encoder-Knoepfe
	{
		var win, mkSlider, mkKnob, mkToggle, mkStateToggle, mkWeightSlider, autoSceneBtn, arrangementBtn, mkVocalKnob;
		var midiOutBtn, fbPageMenu, fbRateKnob, sceneMorphKnob;
		var learnParamMenu, learnTypeMenu, learnBtn;
		var learnParams, monitorText, cpuGuardBtn;
		var dnbPageMenu, vocalPathText;
		var arrPhaseMenu, arrParamMenu, arrEditNum, arrApplyBtn, arrApplyPhaseBtn, arrEditPhase, arrEditParam, updateArrEditor;
		var uiModeBtn, applyUiMode, basicUiMode;
		var x = 10, y = 10, w = 190, h = 58, gapY = 62;

		// Alte Instanz vermeiden, falls Script erneut ausgefuehrt wird.
		if(~shiftkoWin.notNil) { ~shiftkoWin.close; };

		win = Window("SHIFTKO Live Control", Rect(100, 80, 1320, 920)).front.alwaysOnTop_(true);
		~shiftkoWin = win;
		basicUiMode = true;
		applyUiMode = { |isBasic|
			win.view.children.do { |v|
				var b = v.bounds;
				var keepInBasic = (
					((b.top < 170) and: { b.left < 760 }) // core engine controls only
					or: { (b.left >= 360) and: { (b.top >= 450) and: { b.top < 590 } } } // save/load/reset essentials
					or: { (b.left >= 340) and: { b.top >= 590 } } // DnB + Vocal blocks
				);
				v.visible = if(isBasic) { keepInBasic } { true };
			};
			if(uiModeBtn.notNil) { uiModeBtn.visible = true; };
		};

		mkSlider = { |label, param, min, max, init, posX, posY|
			var txt, sl, num;
			txt = StaticText(win, Rect(posX, posY, 90, 20)).string_(label);
			sl = Slider(win, Rect(posX + 95, posY, 180, 20)).value_((init - min) / (max - min));
			num = NumberBox(win, Rect(posX + 280, posY, 70, 20)).value_(init.clip(min, max));
			sl.action_({
				var v = sl.value.linlin(0, 1, min, max);
				num.value = v;
				~setParam.(param, v, false);
			});
			num.action_({
				var v = num.value.clip(min, max);
				num.value = v;
				sl.value = v.linlin(min, max, 0, 1);
				~setParam.(param, v, false);
			});
			~uiControls[param] = (set: { |v|
				var vv = v.clip(min, max);
				num.value = vv;
				sl.value = vv.linlin(min, max, 0, 1);
			});
		};

		mkWeightSlider = { |label, param, init, posX, posY|
			mkSlider.(label, param, 0, 100, init, posX, posY);
		};

		mkKnob = { |label, param, min, max, init, posX, posY|
			var txt, kb, num;
			txt = StaticText(win, Rect(posX, posY, 90, 20)).string_(label);
			kb = Knob(win, Rect(posX + 95, posY - 8, 46, 46)).value_((init - min) / (max - min));
			num = NumberBox(win, Rect(posX + 150, posY, 70, 20)).value_(init.clip(min, max));
			kb.action_({
				var v = kb.value.linlin(0, 1, min, max);
				num.value = v;
				~setParam.(param, v, false);
			});
			num.action_({
				var v = num.value.clip(min, max);
				num.value = v;
				kb.value = v.linlin(min, max, 0, 1);
				~setParam.(param, v, false);
			});
			~uiControls[param] = (set: { |v|
				var vv = v.clip(min, max);
				num.value = vv;
				kb.value = vv.linlin(min, max, 0, 1);
			});
		};
		mkVocalKnob = { |label, param, min, max, init, posX, posY|
			var txt, kb, num;
			txt = StaticText(win, Rect(posX, posY, 90, 20)).string_(label);
			kb = Knob(win, Rect(posX + 95, posY - 8, 46, 46)).value_((init - min) / (max - min));
			num = NumberBox(win, Rect(posX + 150, posY, 70, 20)).value_(init.clip(min, max));
			kb.action_({
				var v = kb.value.linlin(0, 1, min, max);
				num.value = v;
				~setVocalParam.(param, v);
			});
			num.action_({
				var v = num.value.clip(min, max);
				num.value = v;
				kb.value = v.linlin(min, max, 0, 1);
				~setVocalParam.(param, v);
			});
		};

		mkToggle = { |label, param, init, posX, posY|
			var bt = Button(win, Rect(posX, posY, 120, 24))
				.states_([
					[label ++ " OFF", Color.white, Color.red],
					[label ++ " ON", Color.black, Color.green]
				])
				.value_(init.asInteger);
			bt.action_({
				~setParam.(param, bt.value, false);
			});
			~uiControls[param] = (set: { |v| bt.value = v.asInteger.clip(0, 1); });
		};

		mkStateToggle = { |labelA, labelB, param, init, posX, posY|
			var bt = Button(win, Rect(posX, posY, 190, 24))
				.states_([
					[labelA, Color.black, Color.gray(0.8)],
					[labelB, Color.black, Color.cyan(0.7)]
				])
				.value_(init.asInteger);
			bt.action_({
				~setParam.(param, bt.value, false);
			});
			~uiControls[param] = (set: { |v| bt.value = v.asInteger.clip(0, 1); });
		};

		// Hauptsektion
		mkSlider.("BPM", \bpm, 30, 100, 60, x, y); y = y + gapY;
		mkSlider.("Mood", \moodRaw, 0, 1, 0.3, x, y); y = y + gapY;
		mkSlider.("Root Hz", \rootHz, 64, 768, 256, x, y); y = y + gapY;
		mkKnob.("Filter Base", \filterCutoffBase, 120, 12000, 1800, x, y); y = y + gapY;
		mkKnob.("Reverb Base", \reverbRoomBase, 0.001, 0.8, 0.4, x, y); y = y + gapY;
		mkKnob.("Master Vol", \masterVol, 0.001, 0.55, 0.4, x, y);

		// Level-Sektion
		x = 380; y = 10;
		mkSlider.("Drone Level", \droneLevel, 0.001, 0.8, 0.6, x, y); y = y + gapY;
		mkSlider.("Notes Level", \notesLevel, 0.001, 0.8, 0.5, x, y); y = y + gapY;
		mkSlider.("Noise Level", \noiseLevel, 0, 0.2, 0.04, x, y); y = y + gapY;
		mkSlider.("Texture Level", \textureLevel, 0, 0.16, 0.04, x, y); y = y + gapY;
		mkSlider.("Chord Level", \chordLevel, 0, 0.8, 0.6, x, y); y = y + gapY;
		mkSlider.("Pedal Level", \pedalLevel, 0, 0.3, 0.08, x, y);
		mkKnob.("Chaos Depth", \chaosDepth, 0, 0.4, 0.12, x, y + gapY);
		mkKnob.("Texture Duck", \textureDuck, 0, 1, 0.6, x + 230, y + gapY);
		mkKnob.("Weight Evolve", \weightEvolve, 0, 1, 0.0, x + 460, y + gapY);
		mkKnob.("Note Density", \noteDensity, 0.2, 1.0, 0.9, x + 690, y + gapY);
		mkKnob.("Calmness", \calmness, 0, 1, 0.5, x + 690, y + gapY - 62);
		mkToggle.("AUX In", \auxInEnable, 0, x + 420, y + gapY + 10);
		mkKnob.("AUX Level", \auxInLevel, 0, 0.9, 0.0, x + 420, y + gapY);
		mkKnob.("AUX Blend", \auxInBlend, 0, 1, 0.0, x + 200, y + gapY - 62);
		mkToggle.("Auto Guard", \autoGainProtect, 1, x + 550, y + gapY + 10);
		mkKnob.("Loud Target", \loudnessTarget, 0.12, 0.45, 0.26, x + 550, y + gapY);

		// Weights
		x = 10; y = 390;
		mkWeightSlider.("Cosmic", \cosmicW, 100, x, y); y = y + 40;
		mkWeightSlider.("Wonder", \wonderW, 0, x, y); y = y + 40;
		mkWeightSlider.("Hopeful", \hopefulW, 0, x, y); y = y + 40;
		mkWeightSlider.("Koto", \kotoW, 0, x + 360, 390);
		mkWeightSlider.("Raga", \ragaW, 0, x + 360, 430);
		mkWeightSlider.("Pelog", \pelogW, 0, x + 360, 470);
		mkWeightSlider.("Safir16", \safir16W, 0, x + 360, 510);

		// Buttons / Toggles
		x = 760; y = 20;
		mkToggle.("Transport", \transport, 1, x, y); y = y + 34;
		mkToggle.("Drone Gate", \droneGate, 1, x, y); y = y + 34;
		mkToggle.("Notes Gate", \notesGate, 1, x, y); y = y + 34;
		mkToggle.("Noise Gate", \noiseGate, 1, x, y); y = y + 34;
		mkToggle.("Texture Gate", \textureGate, 1, x, y); y = y + 34;
		mkToggle.("Macro Gate", \macroGate, 1, x, y);
		mkToggle.("SAFE Mode", \safeMode, 1, x + 130, 20);
		uiModeBtn = Button(win, Rect(1160, 20, 150, 24))
			.states_([
				["BASIC UI ON", Color.black, Color.green(0.7)],
				["BASIC UI OFF", Color.white, Color.red]
			])
			.value_(0)
			.action_({ |bt|
				basicUiMode = (bt.value == 0);
				applyUiMode.(basicUiMode);
			});
		mkStateToggle.("FULL MIX", "NOTES SOLO", \mixMode, 0, x + 130, 54);
		StaticText(win, Rect(x + 130, 86, 110, 20)).string_("Scene Speed");
		Knob(win, Rect(x + 235, 78, 46, 46))
			.value_(0.5)
			.action_({ |kb|
				~scenePeriod = kb.value.linexp(0, 1, 20, 140);
			});
		StaticText(win, Rect(x + 458, 86, 80, 20)).string_("Morph");
		sceneMorphKnob = Knob(win, Rect(x + 518, 78, 46, 46))
			.value_(~sceneMorph ? 0.0)
			.action_({ |kb| ~applySceneMorph.(kb.value); });
		autoSceneBtn = Button(win, Rect(x + 290, 86, 160, 24))
			.states_([
				["AUTO SCENE OFF", Color.white, Color.red],
				["AUTO SCENE ON", Color.black, Color.green]
			])
			.value_(0);
		autoSceneBtn.action_({
			if(autoSceneBtn.value == 1) { ~startAutoScenes.value; } { ~stopAutoScenes.value; };
		});
		arrangementBtn = Button(win, Rect(x + 290, 114, 160, 24))
			.states_([
				["ARRANGE OFF", Color.white, Color.red],
				["ARRANGE ON", Color.black, Color.green]
			])
			.value_(0);
		arrangementBtn.action_({
			if(arrangementBtn.value == 1) { ~startArrangement.value; } { ~stopArrangement.value; };
		});
		~arrangementStatusText = StaticText(win, Rect(x + 458, 114, 170, 20))
			.string_("Arrangement: idle");
		arrEditPhase = \intro;
		arrEditParam = \dnbVol;
		updateArrEditor = {
			var v = ~getArrangementParam.(arrEditPhase, arrEditParam);
			var spec = ~paramSpecs[arrEditParam];
			if(arrEditNum.notNil and: { spec.notNil }) {
				arrEditNum.clipLo = spec[0];
				arrEditNum.clipHi = spec[1];
				arrEditNum.value = v.clip(spec[0], spec[1]);
			};
		};
		StaticText(win, Rect(1040, 146, 60, 20)).string_("Phase");
		arrPhaseMenu = PopUpMenu(win, Rect(1088, 144, 130, 22))
			.items_(["intro", "drop", "breakdown"])
			.value_(0)
			.action_({ |pm|
				var names = [\intro, \drop, \breakdown];
				arrEditPhase = names[pm.value];
				updateArrEditor.value;
			});
		StaticText(win, Rect(1040, 172, 60, 20)).string_("Param");
		arrParamMenu = PopUpMenu(win, Rect(1088, 170, 130, 22))
			.items_(~arrangementEditableParams.collect(_.asString))
			.value_(0)
			.action_({ |pm|
				arrEditParam = ~arrangementEditableParams[pm.value];
				updateArrEditor.value;
			});
		arrEditNum = NumberBox(win, Rect(1040, 198, 88, 22))
			.value_(~getArrangementParam.(arrEditPhase, arrEditParam));
		arrApplyBtn = Button(win, Rect(1132, 198, 86, 22))
			.states_([["APPLY ARR", Color.black, Color.green(0.72)]])
			.action_({
				~setArrangementParam.(arrEditPhase, arrEditParam, arrEditNum.value, true);
				updateArrEditor.value;
			});
		arrApplyPhaseBtn = Button(win, Rect(1040, 224, 178, 22))
			.states_([["APPLY PHASE NOW", Color.black, Color.cyan(0.75)]])
			.action_({ ~applyArrangementPhaseNow.(arrEditPhase); });
		updateArrEditor.value;
		StaticText(win, Rect(760, 146, 44, 20)).string_("I sec");
		~arrIntroDurBox = NumberBox(win, Rect(798, 144, 48, 22))
			.value_(~arrangementDurations[\intro] ? 48)
			.action_({ |nb| ~arrangementDurations[\intro] = nb.value.clip(8, 480).round(1); nb.value = ~arrangementDurations[\intro]; });
		StaticText(win, Rect(852, 146, 44, 20)).string_("D sec");
		~arrDropDurBox = NumberBox(win, Rect(890, 144, 48, 22))
			.value_(~arrangementDurations[\drop] ? 64)
			.action_({ |nb| ~arrangementDurations[\drop] = nb.value.clip(8, 480).round(1); nb.value = ~arrangementDurations[\drop]; });
		StaticText(win, Rect(944, 146, 44, 20)).string_("B sec");
		~arrBreakDurBox = NumberBox(win, Rect(982, 144, 48, 22))
			.value_(~arrangementDurations[\breakdown] ? 32)
			.action_({ |nb| ~arrangementDurations[\breakdown] = nb.value.clip(8, 480).round(1); nb.value = ~arrangementDurations[\breakdown]; });
		Button(win, Rect(760, 172, 88, 22))
			.states_([["SAVE ARR A", Color.black, Color.cyan(0.75)]])
			.action_({ ~saveArrangementMacro.(\A); });
		Button(win, Rect(852, 172, 88, 22))
			.states_([["LOAD ARR A", Color.black, Color.cyan(0.6)]])
			.action_({ ~loadArrangementMacro.(\A); updateArrEditor.value; });
		Button(win, Rect(944, 172, 88, 22))
			.states_([["SAVE ARR B", Color.black, Color.magenta(0.72)]])
			.action_({ ~saveArrangementMacro.(\B); });
		Button(win, Rect(760, 198, 88, 22))
			.states_([["LOAD ARR B", Color.black, Color.magenta(0.58)]])
			.action_({ ~loadArrangementMacro.(\B); updateArrEditor.value; });
		Button(win, Rect(852, 198, 88, 22))
			.states_([["SAVE ARR C", Color.black, Color.yellow(0.8)]])
			.action_({ ~saveArrangementMacro.(\C); });
		Button(win, Rect(944, 198, 88, 22))
			.states_([["LOAD ARR C", Color.black, Color.yellow(0.64)]])
			.action_({ ~loadArrangementMacro.(\C); updateArrEditor.value; });

		Button(win, Rect(760, 260, 190, 28))
			.states_([["Reset Weights: Cosmic", Color.black, Color.yellow]])
			.action_({
				~applyParams.([\cosmicW, 100, \wonderW, 0, \hopefulW, 0, \kotoW, 0, \ragaW, 0, \pelogW, 0, \safir16W, 0], true);
			});

		Button(win, Rect(760, 298, 190, 28))
			.states_([["FREE SYNTH", Color.white, Color.red]])
			.action_({
				if(~shiftko.notNil) { ~shiftko.free; ~shiftko = nil; };
			});

		Button(win, Rect(760, 336, 190, 28))
			.states_([["RESTART SYNTH", Color.black, Color.green]])
			.action_({
				if(~shiftko.notNil) { ~shiftko.free; };
				~shiftko = Synth(\shiftkoAmbientMath);
				~applyParams.(~defaultState, true);
			});

		Button(win, Rect(760, 374, 190, 28))
			.states_([["PRESET SAFE", Color.black, Color.gray(0.75)]])
			.action_({
				~applyScene.(\safe);
				sceneMorphKnob.value = ~sceneMorph;
			});

		Button(win, Rect(760, 412, 190, 28))
			.states_([["PRESET WILD", Color.white, Color.magenta(0.8)]])
			.action_({
				~applyScene.(\wild);
				sceneMorphKnob.value = ~sceneMorph;
			});

		Button(win, Rect(760, 450, 190, 28))
			.states_([["PRESET FOCUS WEIGHTS", Color.black, Color.cyan(0.8)]])
			.action_({
				~applyScene.(\focus);
				sceneMorphKnob.value = ~sceneMorph;
			});
		Button(win, Rect(760, 488, 190, 28))
			.states_([["RUN SELFTEST", Color.black, Color.yellow]])
			.action_({ ~runSelfTest.value; });
		Button(win, Rect(760, 526, 190, 28))
			.states_([["PANIC SILENCE", Color.white, Color.red]])
			.action_({ ~panicSilence.value; });
		Button(win, Rect(760, 558, 190, 28))
			.states_([["RESTORE STATE", Color.black, Color.green]])
			.action_({ ~restoreFromSceneState.value; });
		Button(win, Rect(760, 590, 92, 28))
			.states_([["SCOPE", Color.black, Color.cyan(0.8)]])
			.action_({ s.scope(2); });
		Button(win, Rect(858, 590, 92, 28))
			.states_([["VIS", Color.black, Color.cyan(0.7)]])
			.action_({ ~openVisualDashboard.value; });
		cpuGuardBtn = Button(win, Rect(560, 558, 190, 28))
			.states_([
				["CPU GUARD OFF", Color.white, Color.red],
				["CPU GUARD ON", Color.black, Color.green]
			])
			.value_(1)
			.action_({ |bt|
				~autoCpuGuard = (bt.value == 1);
				("CPU guard: " ++ ~autoCpuGuard).postln;
			});
		Button(win, Rect(560, 450, 190, 28))
			.states_([
				["MIDI DEBUG OFF", Color.white, Color.red],
				["MIDI DEBUG ON", Color.black, Color.green]
			])
			.value_(0)
			.action_({ |bt|
				~midiDebug = (bt.value == 1);
				("MIDI debug: " ++ ~midiDebug).postln;
			});
		Button(win, Rect(560, 412, 190, 28))
			.states_([
				["STRICT PICKUP OFF", Color.white, Color.red],
				["STRICT PICKUP ON", Color.black, Color.green]
			])
			.value_(if(~strictPickupMode) { 1 } { 0 })
			.action_({ |bt|
				~strictPickupMode = (bt.value == 1);
				if(~strictPickupMode) { ~lockAllMappedPickups.value; };
				("Strict pickup: " ++ ~strictPickupMode).postln;
			});
		Button(win, Rect(560, 336, 190, 28))
			.states_([
				["PERF SAFE LOCK OFF", Color.white, Color.red],
				["PERF SAFE LOCK ON", Color.black, Color.green]
			])
			.value_(if(~performanceSafeLock) { 1 } { 0 })
			.action_({ |bt|
				~performanceSafeLock = (bt.value == 1);
				if(~performanceSafeLock) {
					~performanceSafeCaps.keysValuesDo { |k, cap|
						var v = ~paramState[k];
						if(v.notNil and: { v > cap }) { ~setParam.(k, cap, true); };
					};
				};
				("Performance safe lock: " ++ ~performanceSafeLock).postln;
			});
		Button(win, Rect(560, 374, 190, 28))
			.states_([
				["PICKUP OVERRIDE OFF", Color.white, Color.gray(0.5)],
				["PICKUP OVERRIDE ON", Color.black, Color.yellow]
			])
			.value_(if(~pickupOverride) { 1 } { 0 })
			.action_({ |bt|
				~pickupOverride = (bt.value == 1);
				("Pickup override: " ++ ~pickupOverride).postln;
			});
		midiOutBtn = Button(win, Rect(360, 450, 190, 28))
			.states_([
				["MIDI FEEDBACK OFF", Color.white, Color.red],
				["MIDI FEEDBACK ON", Color.black, Color.green]
			])
			.value_(0)
			.action_({ |bt|
				~midiFeedback = (bt.value == 1);
				("MIDI feedback: " ++ ~midiFeedback).postln;
				~sendStatusFeedback.(\midiFeedback, if(~midiFeedback) { 1 } { 0 });
				if(~midiFeedback) { ~sendFeedbackPageSnapshot.value; };
			});
		StaticText(win, Rect(360, 526, 70, 20)).string_("FB Page");
		fbPageMenu = PopUpMenu(win, Rect(430, 526, 120, 24))
			.items_(["performance", "timbre", "rhythm", "breakbeat", "full"])
			.value_(0)
			.action_({ |pm|
				var names = [\performance, \timbre, \rhythm, \breakbeat, \full];
				~feedbackPage = names[pm.value];
				~sendStatusFeedback.(\feedbackPage, ~feedbackPageIndex.(~feedbackPage));
				if(~midiFeedback) { ~sendFeedbackPageSnapshot.value; };
			});
		StaticText(win, Rect(360, 552, 70, 20)).string_("FB Rate");
		fbRateKnob = Knob(win, Rect(430, 546, 36, 36))
			.value_(0.34)
			.action_({ |kb|
				~feedbackRateHz = kb.value.linexp(0, 1, 2, 50);
			});
		Button(win, Rect(482, 548, 68, 24))
			.states_([["FB NOW", Color.black, Color.cyan(0.75)]])
			.action_({ ~sendFeedbackPageSnapshot.value; });
		Button(win, Rect(482, 578, 68, 24))
			.states_([["OLED", Color.black, Color.cyan(0.7)]])
			.action_({ ~sendOledFrame.value; });
		Button(win, Rect(560, 558, 120, 24))
			.states_([["OLED AUTO OFF", Color.black, Color.gray(0.75)], ["OLED AUTO ON", Color.white, Color.green(0.65)]])
			.value_(if(~oledAutoEnabled) { 1 } { 0 })
			.action_({ |bt|
				if(bt.value == 1) { ~startOledTask.value; } { ~stopOledTask.value; };
			});
		StaticText(win, Rect(684, 558, 62, 20)).string_("OLED Hz");
		Knob(win, Rect(744, 552, 36, 36))
			.value_(((~oledAutoRateHz ? 10).linlin(1, 30, 0, 1)).clip(0, 1))
			.action_({ |kb|
				~oledAutoRateHz = kb.value.linlin(0, 1, 1, 30).round(1);
				if(~oledAutoEnabled) { ~startOledTask.value; };
			});
		Button(win, Rect(560, 526, 190, 28))
			.states_([["RESCAN MIDI OUT", Color.black, Color.cyan(0.75)]])
			.action_({ ~setupMidiOut.value; });
		Button(win, Rect(560, 488, 190, 28))
			.states_([["SAVE SESSION", Color.black, Color.gray(0.82)]])
			.action_({ ~saveState.value; });
		Button(win, Rect(360, 488, 190, 28))
			.states_([["LOAD SESSION", Color.black, Color.gray(0.78)]])
			.action_({ ~loadState.value; });
		Button(win, Rect(560, 526, 190, 28))
			.states_([["RESET SESSION", Color.white, Color.red]])
			.action_({ ~applyParams.(~defaultState, true); });
		Button(win, Rect(160, 488, 190, 28))
			.states_([["SAVE MIDI PROFILE", Color.black, Color.gray(0.75)]])
			.action_({ ~saveMidiProfile.value; });
		Button(win, Rect(160, 450, 190, 28))
			.states_([["LOAD MIDI PROFILE", Color.black, Color.gray(0.72)]])
			.action_({ ~loadMidiProfile.value; });
		Button(win, Rect(160, 526, 92, 28))
			.states_([["CAP A", Color.black, Color.cyan(0.7)]])
			.action_({ ~captureSnapshot.(\A); });
		Button(win, Rect(258, 526, 92, 28))
			.states_([["LOAD A", Color.black, Color.cyan(0.55)]])
			.action_({ ~loadSnapshot.(\A); });
		Button(win, Rect(160, 558, 92, 28))
			.states_([["CAP B", Color.black, Color.magenta(0.7)]])
			.action_({ ~captureSnapshot.(\B); });
		Button(win, Rect(258, 558, 92, 28))
			.states_([["LOAD B", Color.black, Color.magenta(0.55)]])
			.action_({ ~loadSnapshot.(\B); });
		Button(win, Rect(10, 558, 92, 28))
			.states_([["MUTATE", Color.black, Color.yellow]])
			.action_({ ~mutateState.value; });
		Button(win, Rect(108, 558, 46, 28))
			.states_([["UNDO", Color.black, Color.gray(0.78)]])
			.action_({ ~undoLastMutation.value; });
		StaticText(win, Rect(10, 590, 82, 20)).string_("Mut Amt");
		Knob(win, Rect(84, 582, 36, 36))
			.value_(0.25)
			.action_({ |kb| ~mutateAmount = kb.value.linlin(0, 1, 0.02, 0.8); });

		learnParams = ~paramSpecs.keys.asArray.sort;
		StaticText(win, Rect(10, 450, 72, 20)).string_("Learn Param");
		learnParamMenu = PopUpMenu(win, Rect(82, 450, 160, 24))
			.items_(learnParams.collect(_.asString))
			.value_((learnParams.indexOf(\textureLevel) ? 0))
			.action_({ |pm| ~learnTargetParam = learnParams[pm.value]; });
		~learnTargetParam = learnParams[learnParamMenu.value];
		learnTypeMenu = PopUpMenu(win, Rect(10, 480, 110, 24))
			.items_(["absolute", "encoder"])
			.value_(0)
			.action_({ |pm| ~learnTargetType = if(pm.value == 0) { \absolute } { \encoder }; });
		learnBtn = Button(win, Rect(126, 480, 116, 24))
			.states_([["ARM MIDI LEARN", Color.black, Color.yellow]])
			.action_({
				~learnMode = true;
				("[MIDI LEARN] armed for " ++ ~learnTargetType ++ " -> " ++ ~learnTargetParam).postln;
			});
		monitorText = StaticText(win, Rect(10, 526, 330, 58))
			.string_("CPU monitor init...");
		~monitorTask = Task({
			inf.do {
				var avg = s.avgCPU.round(0.1);
				var peak = s.peakCPU.round(0.1);
				var nodes = (s.statusWatcher.notNil).if({ s.statusWatcher.numSynths }, { -1 });
				var locked = (~countLockedPickups.value ? 0);
				{
					monitorText.string = "CPU avg/peak: " ++ avg ++ "% / " ++ peak ++ "%\nSynth nodes: " ++ nodes ++ " | CPU guard: " ++ ~cpuGuardState ++ "\nScene: " ++ (~currentScene ? \safe) ++ " | Pickup lock: " ++ locked;
				}.defer;
				~applyCpuGuard.(avg);
				0.6.wait;
			}
		}).play(AppClock);

		// DnB/Jungle Control Block (simplified)
		StaticText(win, Rect(360, 590, 170, 20)).string_("DnB / Jungle Slicer");
		Button(win, Rect(360, 616, 140, 24))
			.states_([["DNB OFF", Color.white, Color.red], ["DNB ON", Color.black, Color.green]])
			.value_(0)
			.action_({ |bt| ~toggleDnb.value; bt.value = if(~dnb[\player].notNil) { 1 } { 0 }; });
		Button(win, Rect(506, 616, 120, 24))
			.states_([["NEXT BREAK", Color.black, Color.yellow]])
			.action_({
				~loadBreakByIndex.((~breakPaths ? []).size.rand);
				if(~dnb[\player].notNil) { ~startDnb.value; };
			});
		mkKnob.("DnB Vol", \dnbVol, 0, 1, ~paramState[\dnbVol] ? 0.0, 360, 648);
		mkKnob.("Chaos", \dnbChaos, 0, 1, ~paramState[\dnbChaos] ? 0.3, 530, 648);
		mkKnob.("Roll", \dnbRoll, 0, 1, ~paramState[\dnbRoll] ? 0.0, 700, 648);
		mkKnob.("Stutter", \dnbStutter, 0, 0.35, ~paramState[\dnbStutter] ? 0.08, 870, 648);
		mkKnob.("Rate Off", \dnbRateOffset, 0.25, 2.0, ~paramState[\dnbRateOffset] ? 1.0, 1030, 648);
		mkKnob.("DnB Rev", \dnbRev, 0, 1, ~paramState[\dnbRev] ? 0.12, 360, 704);
		mkKnob.("Tgt BPM", \dnbTargetBpm, 80, 220, ~paramState[\dnbTargetBpm] ? 170, 530, 704);
		mkKnob.("Src BPM", \dnbSourceBpm, 60, 220, ~paramState[\dnbSourceBpm] ? 135, 700, 704);
		mkKnob.("Break HPF", \dnbBreakHPF, 30, 1200, ~paramState[\dnbBreakHPF] ? 90, 870, 704);
		mkKnob.("Kick Amp", \dnbKickAmp, 0, 1, ~paramState[\dnbKickAmp] ? 0.45, 1030, 704);
		mkKnob.("Sidechain", \dnbSidechainDepth, 0, 0.6, ~paramState[\dnbSidechainDepth] ? 0.18, 1190, 704);
		StaticText(win, Rect(870, 760, 70, 20)).string_("FB Page");
		dnbPageMenu = PopUpMenu(win, Rect(940, 756, 140, 24))
			.items_(["performance", "timbre", "rhythm", "breakbeat", "full"])
			.value_(0)
			.action_({ |pm|
				var names = [\performance, \timbre, \rhythm, \breakbeat, \full];
				~feedbackPage = names[pm.value];
				~sendStatusFeedback.(\feedbackPage, ~feedbackPageIndex.(~feedbackPage));
				if(~midiFeedback) { ~sendFeedbackPageSnapshot.value; };
			});
		// Vocal Granular Block (simplified)
		StaticText(win, Rect(360, 790, 190, 20)).string_("Vocal Granular");
		Button(win, Rect(360, 816, 140, 24))
			.states_([["VOC OFF", Color.white, Color.red], ["VOC ON", Color.black, Color.green]])
			.value_(0)
			.action_({
				|bt|
				~toggleVocalGranular.value;
				bt.value = if(~vocal[\synth].notNil) { 1 } { 0 };
				if(vocalPathText.notNil and: { ~vocal[\path].notNil }) { vocalPathText.string = ("Vocal: " ++ PathName(~vocal[\path]).fileName); };
			});
		Button(win, Rect(506, 816, 120, 24))
			.states_([["NEXT VOCAL", Color.black, Color.cyan(0.75)]])
			.action_({
				var idx = (~vocalPaths ? []).size.rand;
				~loadVocalByIndex.(idx);
				if(vocalPathText.notNil) { vocalPathText.string = ("Vocal: " ++ PathName((~vocalPaths ? [])[idx]).fileName); };
				if(~vocal[\synth].notNil) { ~startVocalGranular.value; };
			});
		vocalPathText = StaticText(win, Rect(808, 818, 420, 20)).string_("Vocal: (none)");
		mkVocalKnob.("V Amp", \vocalAmp, 0, 0.5, ~vocal[\amp] ? 0.14, 360, 850);
		mkVocalKnob.("V Rate", \vocalRate, 0.25, 2.0, ~vocal[\rate] ? 1.0, 530, 850);
		mkVocalKnob.("V Pos", \vocalPos, 0, 1, ~vocal[\pos] ? 0.5, 700, 850);
		mkVocalKnob.("V Jitter", \vocalJitter, 0, 0.45, ~vocal[\posJitter] ? 0.18, 870, 850);
		mkVocalKnob.("V Dur", \vocalGrainDur, 0.02, 0.5, ~vocal[\grainDur] ? 0.16, 1040, 850);
		mkVocalKnob.("V Dens", \vocalDensity, 1, 80, ~vocal[\density] ? 10, 1210, 850);
		mkVocalKnob.("V HPF", \vocalHpf, 40, 1200, ~vocal[\hpf] ? 120, 360, 882);
		mkVocalKnob.("V LPF", \vocalLpf, 500, 14000, ~vocal[\lpf] ? 8500, 530, 882);
		mkVocalKnob.("V Rev", \vocalRev, 0, 1, ~vocal[\rev] ? 0.2, 700, 882);
		mkVocalKnob.("V Pan", \vocalPanWidth, 0, 1, ~vocal[\panWidth] ? 0.6, 870, 882);

		~loadArrangementMacrosFile.value;
		~loadState.value;
		if(PathName(~defaultDnbBreakPath).isFile) {
			~loadDnbSample.(~defaultDnbBreakPath);
			~setParam.(\dnbSourceBpm, ~getSampleSourceBpm.(~defaultDnbBreakPath, 170), true);
		};
		~setupMidi.value;
		if(~strictPickupMode) { ~lockAllMappedPickups.value; };
		~setupMidiOut.value;
		applyUiMode.(basicUiMode);
		win.onClose_({
			if(~monitorTask.notNil) { ~monitorTask.stop; ~monitorTask = nil; };
			~stopOledTask.value;
			~closeVisualDashboard.value;
			~stopDnb.value;
			~stopVocalGranular.value;
			~stopArrangement.value;
			~saveArrangementMacrosFile.value;
			~saveState.value;
			~stopMidi.value;
			~stopAutoScenes.value;
			"SHIFTKO UI geschlossen.".postln;
		});
	}.defer;
};
)

/*
Beispiele:
~shiftko.set(\bpm, 54, \moodRaw, 0.72, \reverbRoomBase, 0.52);
~shiftko.set(\cosmicW, 0, \wonderW, 100, \hopefulW, 25);
~shiftko.set(\notesLevel, 0.55, \droneLevel, 0.62, \textureLevel, 0.14);
~shiftko.free;
*/
