unit p3d_audio;

{ Pseudo 3D Road - shared sound unit: engine with gearbox, wheels on grass
  and kerbs, crash, a note preview and the chiptune music player.
  All settings come from p3d_common (audio.ini / music.ini). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, SDL3, p3d_common;

var
  AudioStream: PSDL_AudioStream = nil;
  EngineOn: Boolean = True;       // the music editor switches the engine off
  Gear: Integer = 1;
  EngineRPM: Double = 900;
  EngineLoad: Double = 0;
  MusicStepSamples: Integer = 5512;
  MusicPos: Int64 = 0;
  Scope: array[0..1023] of Single; // last output samples (for editors)
  ScopePos: Integer = 0;

procedure InitAudio;
procedure CloseAudio;
procedure RecalcMusic;            // after tempo changes
procedure ResetMusic;
procedure UpdateEngine(dt, speedPct: Double; throttle, wheelspin: Boolean);
procedure TriggerImpact(strength: Double);
procedure PreviewNote(note: Integer);
procedure FeedAudio(speedPct: Double; offroad, kerb: Boolean);
function MusicCurrentStep: Int64;
function NoteFreq(n: Integer): Double;

implementation

const
  dtS = 1.0 / AudioRate;

var
  SynthPhase, SynthLP: Double;
  OffGain, KerbGain, GravLP, PopEnv, RumblePh, KerbPh: Double;
  ImpactT: Double = 10;
  ImpactAmp, ImpactPh, ImpactLP: Double;
  BassPh, ArpPh, LeadPh, KickPh: Double;
  BassF, ArpF, LeadF: Double;
  BassEnv, ArpEnv, LeadEnv: Double;
  LeadGate: Boolean;
  KickT: Double = 10;
  SnareT: Double = 10;
  HatT: Double = 10;
  HatPrev: Double;
  PrevF, PrevEnv, PrevPh: Double;
  AudioBuf: array[0..8191] of Single;

function NoteFreq(n: Integer): Double;
begin
  Result := 440 * Power(2, (n - 69) / 12);
end;

function SoftClip(x: Double): Double;
begin
  if x > 3 then Result := 1
  else if x < -3 then Result := -1
  else Result := x * (27 + x * x) / (27 + 9 * x * x);
end;

procedure InitAudio;
var
  spec: TSDL_AudioSpec;
begin
  if AudioStream <> nil then Exit;
  if not SDL_InitSubSystem(SDL_INIT_AUDIO) then Exit;
  FillChar(spec, SizeOf(spec), 0);
  spec.format := SDL_AUDIO_F32;
  spec.channels := 1;
  spec.freq := AudioRate;
  AudioStream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, nil, nil);
  if AudioStream <> nil then
    SDL_ResumeAudioStreamDevice(AudioStream);
  RecalcMusic;
end;

procedure CloseAudio;
begin
  if AudioStream <> nil then SDL_DestroyAudioStream(AudioStream);
  AudioStream := nil;
end;

procedure RecalcMusic;
begin
  MusicStepSamples := Max(1000, Round(AudioRate * 60 / (MaxD(MusicTempo, 20) * 4)));
end;

procedure ResetMusic;
begin
  MusicPos := 0;
  LeadGate := False;
  LeadEnv := 0;
  BassEnv := 0;
  ArpEnv := 0;
  KickT := 10; SnareT := 10; HatT := 10;
  RecalcMusic;
end;

function MusicCurrentStep: Int64;
var
  latency: Int64;
begin
  latency := 0;
  if AudioStream <> nil then
    latency := SDL_GetAudioStreamQueued(AudioStream) div SizeOf(Single);
  Result := (MusicPos - latency) div MusicStepSamples;
  if Result < 0 then Result := 0;
end;

procedure UpdateEngine(dt, speedPct: Double; throttle, wheelspin: Boolean);
var
  lo, ratio, target, loadTarget: Double;
  n: Integer;
begin
  n := Length(GearTops);
  if n = 0 then Exit;
  Gear := 1;
  while (Gear < n) and (speedPct > GearTops[Gear - 1]) do Inc(Gear);
  if Gear = 1 then lo := 0 else lo := GearTops[Gear - 2];
  ratio := ClampD((speedPct - lo) / MaxD(GearTops[Gear - 1] - lo, 0.01), 0, 1);
  if Gear = 1 then
    target := IdleRPM + ratio * (MaxRPM - IdleRPM)
  else
    target := MaxRPM * 0.42 + ratio * (MaxRPM * 0.58);
  if throttle and wheelspin then
    target := MinD(target + 1200, MaxRPM);
  EngineRPM := EngineRPM + (target - EngineRPM) * MinD(1, dt * 10);
  if throttle then loadTarget := 1 else loadTarget := 0;
  EngineLoad := EngineLoad + (loadTarget - EngineLoad) * MinD(1, dt * 6);
end;

procedure TriggerImpact(strength: Double);
begin
  ImpactT := 0;
  ImpactAmp := ClampD(0.4 + 0.6 * strength, 0, 1);
end;

procedure PreviewNote(note: Integer);
begin
  if note <= 0 then Exit;
  PrevF := NoteFreq(note);
  PrevEnv := 1;
end;

procedure MusicTick(step: Int64);
var
  s, bar, b, nb: Integer;
  ch: TIntArray;
begin
  b := step mod 16;

  if Length(Melody) > 0 then
  begin
    s := step mod Length(Melody);
    if Melody[s] > 0 then
    begin
      LeadF := NoteFreq(Melody[s]);
      LeadGate := True;
    end
    else if Melody[s] < 0 then
      LeadGate := False;
  end;

  nb := Max(1, Max(Length(BassRoots), Length(Chords)));
  bar := (step div 16) mod nb;

  if Length(Chords) > 0 then
  begin
    ch := Chords[bar mod Length(Chords)];
    if Length(ch) > 0 then
    begin
      if b >= 8 then ArpF := NoteFreq(ch[b mod Length(ch)] + 24)
      else ArpF := NoteFreq(ch[b mod Length(ch)] + 12);
      ArpEnv := 1;
    end;
  end;

  if (Length(BassRoots) > 0) and (b mod 2 = 0) then
  begin
    BassF := NoteFreq(BassRoots[bar mod Length(BassRoots)] + 12 * ((b div 2) mod 2));
    BassEnv := 1;
  end;

  if b mod 4 = 0 then KickT := 0;
  if (b = 4) or (b = 12) then SnareT := 0;
  if b mod 2 = 1 then HatT := 0;
end;

function MusicSample: Double;
var
  sq, tri, n, mb, ma, ml, mk, ms, mh, vib: Double;
begin
  if MusicPos mod MusicStepSamples = 0 then MusicTick(MusicPos div MusicStepSamples);

  BassPh := Frac(BassPh + BassF * dtS);
  if BassPh < 0.5 then sq := 1 else sq := -1;
  tri := 4 * Abs(BassPh - 0.5) - 1;
  BassEnv := BassEnv * 0.99993;
  mb := (0.6 * sq + 0.4 * tri) * (0.35 + 0.65 * BassEnv) * 0.16;

  ArpPh := Frac(ArpPh + ArpF * dtS);
  if ArpPh < 0.25 then sq := 1 else sq := -1;
  ArpEnv := ArpEnv * 0.99975;
  ma := sq * ArpEnv * 0.05;

  vib := 1 + 0.005 * Sin(2 * Pi * 5.5 * MusicPos * dtS);
  LeadPh := Frac(LeadPh + LeadF * vib * dtS);
  if LeadGate then LeadEnv := LeadEnv + (1 - LeadEnv) * 0.003
  else LeadEnv := LeadEnv * 0.9993;
  if LeadPh < 0.5 then sq := 1 else sq := -1;
  ml := (sq * 0.5 + (4 * Abs(LeadPh - 0.5) - 1) * 0.5) * LeadEnv * 0.09;

  mk := 0; ms := 0; mh := 0;
  if KickT < 0.3 then
  begin
    KickPh := Frac(KickPh + (45 + 120 * Exp(-KickT * 35)) * dtS);
    mk := Sin(2 * Pi * KickPh) * Exp(-KickT * 12) * 0.30;
    KickT := KickT + dtS;
  end;
  if SnareT < 0.25 then
  begin
    ms := (Random * 2 - 1) * Exp(-SnareT * 22) * 0.10 +
          Sin(2 * Pi * 190 * SnareT) * Exp(-SnareT * 30) * 0.06;
    SnareT := SnareT + dtS;
  end;
  if HatT < 0.08 then
  begin
    n := Random * 2 - 1;
    mh := (n - HatPrev) * Exp(-HatT * 70) * 0.035;
    HatPrev := n;
    HatT := HatT + dtS;
  end;

  Inc(MusicPos);
  Result := (mb + ma + ml + mk + ms + mh) * MusicVolume;
end;

{ keeps ~70 ms of sound queued }
procedure FeedAudio(speedPct: Double; offroad, kerb: Boolean);
var
  queued, need, i: Integer;
  freq, p, v, fire, alpha, engVol, rpmPct: Double;
  offT, kerbT, n, x, eng, off, sfx, music, f, prev: Double;
begin
  if AudioStream = nil then Exit;
  queued := SDL_GetAudioStreamQueued(AudioStream) div SizeOf(Single);
  need := Round(AudioRate * 0.07) - queued;
  if need <= 0 then Exit;
  if need > Length(AudioBuf) then need := Length(AudioBuf);

  rpmPct := ClampD((EngineRPM - IdleRPM) / MaxD(MaxRPM - IdleRPM, 1), 0, 1);
  freq := EngineRPM / 60 * 2;
  alpha := ClampD(0.08 + 0.3 * rpmPct + 0.2 * EngineLoad, 0.05, 0.9);
  engVol := (0.2 + 0.15 * EngineLoad + 0.1 * rpmPct) * EngineVolume;

  offT := 0; kerbT := 0;
  if speedPct > 0.005 then
  begin
    if offroad then offT := (0.08 + 0.42 * speedPct) * GroundVolume
    else if kerb then kerbT := (0.12 + 0.3 * speedPct) * GroundVolume;
  end;

  for i := 0 to need - 1 do
  begin
    // engine
    eng := 0;
    SynthPhase := SynthPhase + freq * dtS;
    if SynthPhase >= 2 then SynthPhase := SynthPhase - 2;
    if EngineOn then
    begin
      p := Frac(SynthPhase);
      fire := Exp(-p * 6);
      v := 0.5 * (1 - 2 * p) + 0.6 * (fire - 0.28) + 0.35 * Sin(Pi * SynthPhase)
           + (Random * 2 - 1) * (0.06 + 0.18 * EngineLoad);
      SynthLP := SynthLP + alpha * (v - SynthLP);
      eng := SynthLP * engVol;
    end;

    // wheels on grass / kerb
    OffGain := OffGain + (offT - OffGain) * 0.0008;
    KerbGain := KerbGain + (kerbT - KerbGain) * 0.0008;
    n := Random * 2 - 1;
    GravLP := GravLP + 0.18 * (n - GravLP);
    off := 0;
    if OffGain > 0.0005 then
    begin
      if Random < 0.002 * (0.3 + speedPct) then PopEnv := 1;
      PopEnv := PopEnv * 0.993;
      RumblePh := Frac(RumblePh + (18 + 45 * speedPct) * dtS);
      off := (GravLP * 1.5 + (Random * 2 - 1) * PopEnv * 0.6 +
              Sin(2 * Pi * RumblePh) * 0.4) * OffGain;
    end;
    if KerbGain > 0.0005 then
    begin
      KerbPh := Frac(KerbPh + (22 + 60 * speedPct) * dtS);
      if KerbPh < 0.5 then x := 1 else x := -1;
      off := off + (x * 0.45 + GravLP * 0.6) * KerbGain;
    end;

    // crash
    sfx := 0;
    if ImpactT < 0.8 then
    begin
      f := 40 + 110 * Exp(-ImpactT * 18);
      ImpactPh := Frac(ImpactPh + f * dtS);
      ImpactLP := ImpactLP + 0.35 * (n - ImpactLP);
      sfx := (Sin(2 * Pi * ImpactPh) * Exp(-ImpactT * 9) * 0.7 +
              ImpactLP * Exp(-ImpactT * 14) * 1.6 +
              Sin(2 * Pi * ImpactT * 1730) * Sin(2 * Pi * ImpactT * 2390) *
                Exp(-ImpactT * 16) * 0.12) * ImpactAmp * CrashVolume;
      ImpactT := ImpactT + dtS;
    end;

    // note preview (music editor)
    prev := 0;
    if PrevEnv > 0.001 then
    begin
      PrevPh := Frac(PrevPh + PrevF * dtS);
      if PrevPh < 0.5 then prev := 0.5 else prev := -0.5;
      prev := (prev + (4 * Abs(PrevPh - 0.5) - 1) * 0.5) * PrevEnv * 0.12 * MusicVolume;
      PrevEnv := PrevEnv * 0.99985;
    end;

    music := 0;
    if MusicOn then music := MusicSample;

    x := SoftClip((eng + off + sfx + music + prev) * MasterVolume);
    if Muted then x := 0;
    AudioBuf[i] := x;
    Scope[ScopePos] := x;
    ScopePos := (ScopePos + 1) mod Length(Scope);
  end;
  SDL_PutAudioStreamData(AudioStream, @AudioBuf[0], need * SizeOf(Single));
end;

end.
