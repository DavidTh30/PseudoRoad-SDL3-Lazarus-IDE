unit p3d_common;

{ Pseudo 3D Road - shared data unit (no SDL).
  Settings, data files in the "data" folder, track sections, and the
  generators that write the default model, shape and bitmap files. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, IniFiles;

const
  ScreenW      = 1024;           // size of the 3D view
  ScreenH      = 768;
  StepTime     = 1.0 / 60.0;
  SegLen       = 200.0;
  RumbleLen    = 3;
  RoadWidth    = 2000.0;         // HALF width of the road
  Lanes        = 3;
  DefCamHeight = 1000.0;
  DefFOV       = 100.0;
  AudioRate    = 44100;

  LenShort  = 25;  LenMedium  = 50;  LenLong  = 100;
  HillLow   = 20;  HillMedium = 40;  HillHigh = 60;
  CurveEasy = 2;   CurveMedium = 4;  CurveHard = 6;

type
  TRGB = record
    r, g, b: Byte;
  end;

  TRGBArray   = array of TRGB;
  TIntArray   = array of Integer;
  TNumArray   = array of Double;
  TChordArray = array of TIntArray;

  TCamera = record
    height: Double;              // above the road
    distance: Double;            // behind the car
    side: Double;                // sideways offset (+ = right)
    pitch: Double;               // degrees, + = look down
    yaw: Double;                 // degrees, + = look right
    fov: Double;                 // degrees
  end;

  TSectionKind = (tkStraight, tkCurve, tkHill, tkRoad, tkRolling, tkSCurves,
                  tkBumps, tkDownhill);

  TTrackSection = record
    kind: TSectionKind;
    p: array[0..4] of Double;
  end;
  TTrackSections = array of TTrackSection;

  TTrafficType = record
    name: string;
    weight: Double;
  end;

  TWeather = (wxNone, wxPetals, wxLeaves, wxSnow, wxRain);

  TLook = record                 // one season
    skyTop, skyBottom, fog, mountain, hills: TRGB;
    grassL, grassD, roadL, roadD: TRGB;
    leaves, needles: TRGB;       // tint for leaf trees/bushes and for pines
    leavesMix, needlesMix: Double;
    flowers: Boolean;
    weather: TWeather;
    weatherAmount: Integer;
  end;

  TNightLook = record
    skyTop, skyBottom, fog: TRGB;
    darkness: Double;            // 0 = as bright as day, 1 = black
    stars: Integer;
    headlights: Boolean;
  end;

const
  SectionNames: array[TSectionKind] of string = (
    'straight', 'curve', 'hill', 'road', 'rollinghills', 'scurves', 'bumps', 'downhill');
  SectionParamCount: array[TSectionKind] of Integer = (1, 3, 2, 5, 2, 0, 0, 1);
  SectionParamNames: array[TSectionKind, 0..4] of string = (
    ('length', '', '', '', ''),
    ('length', 'curve', 'height', '', ''),
    ('length', 'height', '', '', ''),
    ('enter', 'hold', 'leave', 'curve', 'height'),
    ('length', 'height', '', '', ''),
    ('', '', '', '', ''),
    ('', '', '', '', ''),
    ('length', '', '', '', ''));
  SectionDefaults: array[TSectionKind, 0..4] of Double = (
    (25, 0, 0, 0, 0),
    (50, 4, 0, 0, 0),
    (50, 40, 0, 0, 0),
    (25, 25, 25, 2, 0),
    (25, 20, 0, 0, 0),
    (0, 0, 0, 0, 0),
    (0, 0, 0, 0, 0),
    (200, 0, 0, 0, 0));

  DefaultTrack: array[0..17] of string = (
    'straight 25',
    'rollinghills 25 20',
    'scurves',
    'curve 50 4 20',
    'bumps',
    'rollinghills 25 20',
    'curve 200 4 40',
    'straight 50',
    'hill 50 60',
    'scurves',
    'curve 100 -4 0',
    'hill 100 60',
    'curve 100 6 -20',
    'bumps',
    'hill 100 -40',
    'straight 50',
    'scurves',
    'downhill 200');

  DefaultModelNames: array[0..5] of string = (
    'sedan', 'sports', 'van', 'pickup', 'truck', 'bus');
  DefaultShapeNames: array[0..7] of string = (
    'pine', 'tree', 'bush', 'flowerbush', 'billboard', 'lamp', 'chevron', 'warning');
  PosterCount = 4;

  SeasonNames: array[0..3] of string = ('spring', 'summer', 'autumn', 'winter');
  SeasonTitles: array[0..3] of string = ('Spring', 'Summer', 'Autumn', 'Winter');
  WeatherNames: array[TWeather] of string = ('none', 'petals', 'leaves', 'snow', 'rain');

var
  FS: TFormatSettings;           // '.' as decimal separator for the data files
  DataDir: string;               // ...\data\
  Cam: TCamera;

  // vehicles
  PlayerColor: TRGB;
  PlayerModelName: string;
  TrafficCount: Integer;
  TrafficMinSpeed, TrafficMaxSpeed, TrafficDistracted: Double;
  CarPalette: TRGBArray;
  TrafficTypes: array of TTrafficType;

  // trees
  TreeChance, TreeOffMin, TreeOffMax, PineRatio: Double;
  TreeSpacingMin, TreeSpacingMax: Integer;
  PineTrunk, PineShadow, PineTier, PineLit, PineTop: TRGB;
  TreeTrunk, TreeBark, TreeDark, TreeMid, TreeLight: TRGB;

  // bushes
  BushChance, BushOffMin, BushOffMax, FlowerRatio: Double;
  BushSpacingMin, BushSpacingMax: Integer;
  BushDark, BushMid, BushLight, FlowerCenter: TRGB;
  FlowerPalette: TRGBArray;

  // signs
  BillboardFirst, BillboardSpacingMin, BillboardSpacingMax: Integer;
  BillboardOffset: Double;
  LampUntil, LampSpacing: Integer;
  LampOffset: Double;
  WarningEnabled: Boolean;
  WarningDistance: Integer;
  WarningOffset: Double;
  ChevronEnabled: Boolean;
  ChevronSpacing: Integer;
  ChevronMinCurve, ChevronOffset: Double;

  // audio
  MasterVolume, EngineVolume, GroundVolume, CrashVolume: Double;
  IdleRPM, MaxRPM: Double;
  GearTops: TNumArray;
  Muted: Boolean;

  // music
  MusicOn: Boolean;
  MusicTempo, MusicVolume: Double;
  Melody, BassRoots: TIntArray;
  Chords: TChordArray;

  NamedColors: TStringList = nil;  // name=r,g,b for $name colours in shape files

  // seasons and day / night (seasons.ini)
  Seasons: array[0..3] of TLook;
  Night: TNightLook;
  SeasonIdx: Integer = 1;
  NightMode: Boolean = False;

{ --- maths and colours }
function MinD(a, b: Double): Double; inline;
function MaxD(a, b: Double): Double; inline;
function ClampD(v, lo, hi: Double): Double; inline;
function Interp(a, b, p: Double): Double; inline;
function EaseIn(a, b, p: Double): Double;
function EaseInOut(a, b, p: Double): Double;
function WrapUnit(x: Double): Double;
function RandomSign: Double;
function SignD(x: Double): Double;
function RandomRange2(lo, hi: Integer): Integer;
function MakeRGB(r, g, b: Byte): TRGB;
function Mix(const a, b: TRGB; t: Double): TRGB;
function Shade(const c: TRGB; k: Double): TRGB;
function NoteName(n: Integer): string;

{ --- text helpers }
function SplitBy(const s: string; sep: Char): TStringArray;
function NumStr(v: Double): string;
function ColStr(const c: TRGB): string;
function ParseColor(const s: string; const def: TRGB): TRGB;
function ColsToStr(const a: array of TRGB): string;
function IntsToStr(const a: array of Integer; const sep: string = ' '): string;
function NumsToStr(const a: array of Double): string;
function ChordsToStr(const a: TChordArray): string;
function ParseCols(const s: string): TRGBArray;
function ParseInts(const s: string; sep: Char = ' '): TIntArray;
function ParseNums(const s: string): TNumArray;
function ParseChords(const s: string): TChordArray;
function FindNamedColor(const name: string; out c: TRGB): Boolean;

{ --- ini helpers }
procedure WSec(L: TStringList; const name: string);
procedure WCom(L: TStringList; const text: string);
procedure WStr(L: TStringList; const key, value: string);
procedure WNum(L: TStringList; const key: string; v: Double);
procedure WCol(L: TStringList; const key: string; const c: TRGB);
function RNum(ini: TMemIniFile; const sec, key: string; def: Double): Double;
function RInt(ini: TMemIniFile; const sec, key: string; def: Integer): Integer;
function RCol(ini: TMemIniFile; const sec, key: string; const def: TRGB): TRGB;

{ --- camera }
function BuiltInCamera: TCamera;
procedure ClampCamera(var c: TCamera);
procedure SaveCameraFile(const path: string; const c: TCamera);
function LoadCameraFile(const path: string; var c: TCamera): Boolean;
procedure LoadDefaultCamera;

{ --- data files }
procedure InitCommon;            // decimal format + data folder (call first)
procedure SetDefaultData;
procedure SetDefaultAudio;
procedure SetDefaultMusic;
procedure SaveVehicles(const path: string);
procedure LoadVehicles(const path: string);
procedure SaveTrees(const path: string);
procedure LoadTrees(const path: string);
procedure SaveBushes(const path: string);
procedure LoadBushes(const path: string);
procedure SaveSigns(const path: string);
procedure LoadSigns(const path: string);
procedure SaveAudio(const path: string);
procedure LoadAudio(const path: string);
procedure SaveMusic(const path: string);
procedure LoadMusic(const path: string);
procedure RebuildNamedColors;
procedure SetDefaultSeasons;
procedure SaveSeasons(const path: string);
procedure LoadSeasons(const path: string);
procedure SaveSeasonChoice;
function CurLook: TLook;
procedure UpgradeShapeFiles;
procedure FixupData;             // keeps loaded values usable
procedure LoadAllData(withCamera: Boolean);
function ModelPath(const name: string): string;
function ShapePath(const name: string): string;
function BitmapPath(const name: string): string;

{ --- track }
function DefaultSection(kind: TSectionKind): TTrackSection;
function ParseTrackLine(const line: string; out sec: TTrackSection): Boolean;
function SectionToLine(const sec: TTrackSection): string;
function DefaultTrackSections: TTrackSections;
function LoadTrackSections(const path: string): TTrackSections;
procedure SaveTrackSections(const path: string; const secs: TTrackSections);

{ --- default geometry and bitmap files }
procedure WriteModelText(const key: string; L: TStringList);
procedure WriteShapeText(const key: string; L: TStringList);
procedure WriteDefaultModels(force: Boolean);
procedure WriteDefaultShapes(force: Boolean);
procedure WriteDefaultBitmaps(force: Boolean);

implementation

{ ---------------------------------------------------------------- maths }

function MinD(a, b: Double): Double; inline;
begin
  if a < b then Result := a else Result := b;
end;

function MaxD(a, b: Double): Double; inline;
begin
  if a > b then Result := a else Result := b;
end;

function ClampD(v, lo, hi: Double): Double; inline;
begin
  Result := MaxD(lo, MinD(v, hi));
end;

function Interp(a, b, p: Double): Double; inline;
begin
  Result := a + (b - a) * p;
end;

function EaseIn(a, b, p: Double): Double;
begin
  Result := a + (b - a) * p * p;
end;

function EaseInOut(a, b, p: Double): Double;
begin
  Result := a + (b - a) * ((-Cos(p * Pi) / 2) + 0.5);
end;

function WrapUnit(x: Double): Double;
begin
  Result := x - Floor(x);
end;

function RandomSign: Double;
begin
  if Random(2) = 0 then Result := -1 else Result := 1;
end;

function SignD(x: Double): Double;
begin
  if x < 0 then Result := -1 else Result := 1;
end;

function RandomRange2(lo, hi: Integer): Integer;
begin
  if hi < lo then hi := lo;
  Result := lo + Random(hi - lo + 1);
end;

function MakeRGB(r, g, b: Byte): TRGB;
begin
  Result.r := r; Result.g := g; Result.b := b;
end;

function Mix(const a, b: TRGB; t: Double): TRGB;
begin
  Result.r := Round(Integer(a.r) + (Integer(b.r) - Integer(a.r)) * t);
  Result.g := Round(Integer(a.g) + (Integer(b.g) - Integer(a.g)) * t);
  Result.b := Round(Integer(a.b) + (Integer(b.b) - Integer(a.b)) * t);
end;

function Shade(const c: TRGB; k: Double): TRGB;
begin
  Result.r := Round(ClampD(c.r * k, 0, 255));
  Result.g := Round(ClampD(c.g * k, 0, 255));
  Result.b := Round(ClampD(c.b * k, 0, 255));
end;

function NoteName(n: Integer): string;
const
  Names: array[0..11] of string = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B');
begin
  if n < 0 then Exit('-');
  Result := Names[n mod 12] + IntToStr(n div 12 - 1);
end;

{ --------------------------------------------------------------- text }

function SplitBy(const s: string; sep: Char): TStringArray;
var
  i, n: Integer;
  cur: string;
begin
  Result := nil;
  cur := '';
  for i := 1 to Length(s) + 1 do
    if (i > Length(s)) or (s[i] = sep) or ((sep = ' ') and (s[i] = #9)) then
    begin
      cur := Trim(cur);
      if cur <> '' then
      begin
        n := Length(Result);
        SetLength(Result, n + 1);
        Result[n] := cur;
      end;
      cur := '';
    end
    else
      cur := cur + s[i];
end;

function NumStr(v: Double): string;
begin
  Result := FormatFloat('0.###', v, FS);
end;

function ColStr(const c: TRGB): string;
begin
  Result := Format('%d,%d,%d', [c.r, c.g, c.b]);
end;

function ParseColor(const s: string; const def: TRGB): TRGB;
var
  p: TStringArray;
begin
  p := SplitBy(s, ',');
  if Length(p) < 3 then Exit(def);
  Result.r := EnsureRange(StrToIntDef(p[0], def.r), 0, 255);
  Result.g := EnsureRange(StrToIntDef(p[1], def.g), 0, 255);
  Result.b := EnsureRange(StrToIntDef(p[2], def.b), 0, 255);
end;

function ColsToStr(const a: array of TRGB): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + ColStr(a[i]);
  end;
end;

function IntsToStr(const a: array of Integer; const sep: string = ' '): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then Result := Result + sep;
    Result := Result + IntToStr(a[i]);
  end;
end;

function NumsToStr(const a: array of Double): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + NumStr(a[i]);
  end;
end;

function ChordsToStr(const a: TChordArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + IntsToStr(a[i], ',');
  end;
end;

function ParseCols(const s: string): TRGBArray;
var
  t: TStringArray;
  i: Integer;
begin
  Result := nil;
  t := SplitBy(s, ' ');
  SetLength(Result, Length(t));
  for i := 0 to High(t) do
    Result[i] := ParseColor(t[i], MakeRGB(128, 128, 128));
end;

function ParseInts(const s: string; sep: Char = ' '): TIntArray;
var
  t: TStringArray;
  i: Integer;
begin
  Result := nil;
  t := SplitBy(s, sep);
  SetLength(Result, Length(t));
  for i := 0 to High(t) do
    Result[i] := StrToIntDef(t[i], 0);
end;

function ParseNums(const s: string): TNumArray;
var
  t: TStringArray;
  i: Integer;
begin
  Result := nil;
  t := SplitBy(s, ' ');
  SetLength(Result, Length(t));
  for i := 0 to High(t) do
    Result[i] := StrToFloatDef(t[i], 0, FS);
end;

function ParseChords(const s: string): TChordArray;
var
  t: TStringArray;
  i: Integer;
begin
  Result := nil;
  t := SplitBy(s, ' ');
  SetLength(Result, Length(t));
  for i := 0 to High(t) do
    Result[i] := ParseInts(t[i], ',');
end;

function FindNamedColor(const name: string; out c: TRGB): Boolean;
var
  i: Integer;
begin
  c := MakeRGB(128, 128, 128);
  Result := False;
  if NamedColors = nil then Exit;
  i := NamedColors.IndexOfName(LowerCase(name));
  if i < 0 then Exit;
  c := ParseColor(NamedColors.ValueFromIndex[i], c);
  Result := True;
end;

{ ---------------------------------------------------------- ini helpers }

procedure WSec(L: TStringList; const name: string);
begin
  L.Add('');
  L.Add('[' + name + ']');
end;

procedure WCom(L: TStringList; const text: string);
begin
  L.Add('; ' + text);
end;

procedure WStr(L: TStringList; const key, value: string);
begin
  L.Add(key + '=' + value);
end;

procedure WNum(L: TStringList; const key: string; v: Double);
begin
  WStr(L, key, NumStr(v));
end;

procedure WCol(L: TStringList; const key: string; const c: TRGB);
begin
  WStr(L, key, ColStr(c));
end;

function RNum(ini: TMemIniFile; const sec, key: string; def: Double): Double;
begin
  Result := StrToFloatDef(Trim(ini.ReadString(sec, key, '')), def, FS);
end;

function RInt(ini: TMemIniFile; const sec, key: string; def: Integer): Integer;
begin
  Result := Round(RNum(ini, sec, key, def));
end;

function RCol(ini: TMemIniFile; const sec, key: string; const def: TRGB): TRGB;
begin
  Result := ParseColor(ini.ReadString(sec, key, ''), def);
end;

{ ---------------------------------------------------------------- camera }

function BuiltInCamera: TCamera;
begin
  Result.height := DefCamHeight;
  Result.distance := 900;
  Result.side := 0;
  Result.pitch := 0;
  Result.yaw := 0;
  Result.fov := DefFOV;
end;

procedure ClampCamera(var c: TCamera);
begin
  c.height := ClampD(c.height, 200, 4000);
  c.distance := ClampD(c.distance, 300, 4000);
  c.side := ClampD(c.side, -2500, 2500);
  c.pitch := ClampD(c.pitch, -20, 20);
  c.yaw := ClampD(c.yaw, -35, 35);
  c.fov := ClampD(c.fov, 50, 150);
end;

procedure SaveCameraFile(const path: string; const c: TCamera);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - camera');
    WCom(L, 'height   : camera height above the road (200..4000)');
    WCom(L, 'distance : distance behind the car (300..4000)');
    WCom(L, 'side     : sideways offset, + = right (-2500..2500)');
    WCom(L, 'pitch    : tilt in degrees, + = look down (-20..20)');
    WCom(L, 'yaw      : turn in degrees, + = look right (-35..35)');
    WCom(L, 'fov      : field of view in degrees (50..150)');
    WSec(L, 'camera');
    WNum(L, 'height', c.height);
    WNum(L, 'distance', c.distance);
    WNum(L, 'side', c.side);
    WNum(L, 'pitch', c.pitch);
    WNum(L, 'yaw', c.yaw);
    WNum(L, 'fov', c.fov);
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

function LoadCameraFile(const path: string; var c: TCamera): Boolean;
var
  ini: TMemIniFile;
begin
  Result := False;
  if not FileExists(path) then Exit;
  try
    ini := TMemIniFile.Create(path);
    try
      c.height := RNum(ini, 'camera', 'height', c.height);
      c.distance := RNum(ini, 'camera', 'distance', c.distance);
      c.side := RNum(ini, 'camera', 'side', c.side);
      c.pitch := RNum(ini, 'camera', 'pitch', c.pitch);
      c.yaw := RNum(ini, 'camera', 'yaw', c.yaw);
      c.fov := RNum(ini, 'camera', 'fov', c.fov);
      ClampCamera(c);
      Result := True;
    finally
      ini.Free;
    end;
  except
    Result := False;
  end;
end;

procedure LoadDefaultCamera;
begin
  Cam := BuiltInCamera;
  LoadCameraFile(DataDir + 'camera_default.ini', Cam);
end;

{ ------------------------------------------------------------ defaults }

const
  DefCarPalette: array[0..7] of TRGB = (
    (r: 230; g: 200; b: 40),  (r: 40;  g: 110; b: 220),
    (r: 240; g: 240; b: 240), (r: 40;  g: 170; b: 90),
    (r: 250; g: 130; b: 30),  (r: 150; g: 60;  b: 200),
    (r: 35;  g: 35;  b: 35),  (r: 190; g: 195; b: 205));

  DefFlowers: array[0..3] of TRGB = (
    (r: 240; g: 120; b: 170), (r: 245; g: 215; b: 60),
    (r: 245; g: 245; b: 245), (r: 170; g: 110; b: 220));

  DefGears: array[0..4] of Double = (0.18, 0.36, 0.56, 0.77, 1.0);

  DefMelody: array[0..63] of Integer = (
    76, 0, 74, 0,  72, 0, 0, 0,  69, 0, 72, 0,  74, 0, 0, 0,
    72, 0, 0, 0,   69, 0, 0, 0,  65, 0, 69, 0,  72, 0, 74, 0,
    76, 0, 0, 0,   79, 0, 76, 0, 74, 0, 72, 0,  74, 0, 0, 0,
    71, 0, 74, 0,  79, 0, 0, 0,  77, 0, 76, 0,  74, 0, -1, 0);
  DefBass: array[0..3] of Integer = (45, 41, 48, 43);
  DefChords: array[0..3, 0..2] of Integer = (
    (57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62));

  DefTypeNames: array[0..5] of string = ('sedan', 'sports', 'van', 'pickup', 'truck', 'bus');
  DefTypeWeights: array[0..5] of Double = (5, 2, 2, 2, 1, 1);

procedure InitCommon;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := ',';
  DataDir := ExtractFilePath(ParamStr(0)) + 'data' + DirectorySeparator;
  if NamedColors = nil then NamedColors := TStringList.Create;
  Cam := BuiltInCamera;
end;

procedure SetDefaultAudio;
var
  i: Integer;
begin
  MasterVolume := 0.85; EngineVolume := 1; GroundVolume := 1; CrashVolume := 1;
  IdleRPM := 900; MaxRPM := 7200;
  Muted := False;
  SetLength(GearTops, Length(DefGears));
  for i := 0 to High(DefGears) do GearTops[i] := DefGears[i];
end;

procedure SetDefaultMusic;
var
  i, j: Integer;
begin
  MusicOn := True;
  MusicTempo := 120; MusicVolume := 0.7;
  SetLength(Melody, Length(DefMelody));
  for i := 0 to High(DefMelody) do Melody[i] := DefMelody[i];
  SetLength(BassRoots, Length(DefBass));
  for i := 0 to High(DefBass) do BassRoots[i] := DefBass[i];
  SetLength(Chords, 4);
  for i := 0 to 3 do
  begin
    SetLength(Chords[i], 3);
    for j := 0 to 2 do Chords[i][j] := DefChords[i, j];
  end;
end;

procedure SetDefaultData;
var
  i: Integer;
begin
  PlayerColor := MakeRGB(220, 30, 40);
  PlayerModelName := 'sedan';
  TrafficCount := 60;
  TrafficMinSpeed := 0.25;
  TrafficMaxSpeed := 0.58;
  TrafficDistracted := 0.25;
  SetLength(CarPalette, Length(DefCarPalette));
  for i := 0 to High(DefCarPalette) do CarPalette[i] := DefCarPalette[i];
  SetLength(TrafficTypes, Length(DefTypeNames));
  for i := 0 to High(DefTypeNames) do
  begin
    TrafficTypes[i].name := DefTypeNames[i];
    TrafficTypes[i].weight := DefTypeWeights[i];
  end;

  TreeChance := 0.75; TreeSpacingMin := 3; TreeSpacingMax := 5;
  TreeOffMin := 2.2;  TreeOffMax := 6.2;   PineRatio := 0.5;
  PineTrunk := MakeRGB(85, 55, 32);   PineShadow := MakeRGB(12, 62, 30);
  PineTier := MakeRGB(20, 88, 42);    PineLit := MakeRGB(38, 120, 58);
  PineTop := MakeRGB(50, 135, 65);
  TreeTrunk := MakeRGB(92, 62, 38);   TreeBark := MakeRGB(125, 90, 58);
  TreeDark := MakeRGB(28, 98, 38);    TreeMid := MakeRGB(44, 132, 50);
  TreeLight := MakeRGB(86, 172, 72);

  BushChance := 0.55; BushSpacingMin := 2; BushSpacingMax := 3;
  BushOffMin := 1.35; BushOffMax := 2.45;  FlowerRatio := 0.25;
  BushDark := MakeRGB(24, 92, 30);    BushMid := MakeRGB(44, 128, 44);
  BushLight := MakeRGB(90, 170, 74);  FlowerCenter := MakeRGB(250, 235, 120);
  SetLength(FlowerPalette, Length(DefFlowers));
  for i := 0 to High(DefFlowers) do FlowerPalette[i] := DefFlowers[i];

  BillboardFirst := 20; BillboardSpacingMin := 120; BillboardSpacingMax := 199;
  BillboardOffset := 1.55;
  LampUntil := 250; LampSpacing := 12; LampOffset := 1.15;
  WarningEnabled := True; WarningDistance := 25; WarningOffset := 1.3;
  ChevronEnabled := True; ChevronSpacing := 8; ChevronMinCurve := 3; ChevronOffset := 1.3;

  SetDefaultAudio;
  SetDefaultMusic;
  SetDefaultSeasons;
end;

{ ---------------------------------------------------------- data files }

function TypesToStr: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(TrafficTypes) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + TrafficTypes[i].name + ':' + NumStr(TrafficTypes[i].weight);
  end;
end;

procedure ParseTypes(const s: string);
var
  t, p: TStringArray;
  i, n: Integer;
begin
  t := SplitBy(s, ' ');
  if Length(t) = 0 then Exit;
  SetLength(TrafficTypes, 0);
  for i := 0 to High(t) do
  begin
    p := SplitBy(t[i], ':');
    if Length(p) = 0 then Continue;
    n := Length(TrafficTypes);
    SetLength(TrafficTypes, n + 1);
    TrafficTypes[n].name := LowerCase(p[0]);
    if Length(p) > 1 then TrafficTypes[n].weight := MaxD(0, StrToFloatDef(p[1], 1, FS))
    else TrafficTypes[n].weight := 1;
  end;
end;

procedure SaveVehicles(const path: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - vehicles');
    WCom(L, 'Colours are R,G,B (0-255). Lists are separated by spaces.');
    WCom(L, 'Vehicle shapes are in data\models\<name>.car');
    WSec(L, 'player');
    WStr(L, 'model', PlayerModelName);
    WCol(L, 'color', PlayerColor);
    WSec(L, 'traffic');
    WCom(L, 'count: number of traffic vehicles (0-400)');
    WCom(L, 'speeds are fractions of the top speed (0-1), scaled by each model''s speed');
    WCom(L, 'distracted: share of drivers who react late and may hit you (0-1)');
    WCom(L, 'types: model:weight - how often each vehicle type appears');
    WCom(L, 'colors: used for models that have no "colors" line of their own');
    WNum(L, 'count', TrafficCount);
    WNum(L, 'min_speed', TrafficMinSpeed);
    WNum(L, 'max_speed', TrafficMaxSpeed);
    WNum(L, 'distracted', TrafficDistracted);
    WStr(L, 'types', TypesToStr);
    WStr(L, 'colors', ColsToStr(CarPalette));
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadVehicles(const path: string);
var
  ini: TMemIniFile;
  cl: TRGBArray;
  s: string;
  upgrade: Boolean;
begin
  upgrade := False;
  ini := TMemIniFile.Create(path);
  try
    s := Trim(ini.ReadString('player', 'model', ''));
    if s <> '' then PlayerModelName := LowerCase(s);
    PlayerColor := RCol(ini, 'player', 'color', PlayerColor);
    TrafficCount := EnsureRange(RInt(ini, 'traffic', 'count', TrafficCount), 0, 400);
    TrafficMinSpeed := ClampD(RNum(ini, 'traffic', 'min_speed', TrafficMinSpeed), 0, 1);
    TrafficMaxSpeed := ClampD(RNum(ini, 'traffic', 'max_speed', TrafficMaxSpeed), TrafficMinSpeed, 1);
    TrafficDistracted := ClampD(RNum(ini, 'traffic', 'distracted', TrafficDistracted), 0, 1);
    ParseTypes(ini.ReadString('traffic', 'types', ''));
    cl := ParseCols(ini.ReadString('traffic', 'colors', ''));
    if Length(cl) > 0 then CarPalette := cl;
    // files from older versions lack the vehicle-type keys: add them
    upgrade := not ini.ValueExists('traffic', 'types') or not ini.ValueExists('player', 'model');
  finally
    ini.Free;
  end;
  if upgrade then
    try
      SaveVehicles(path);
    except
    end;
end;

procedure SaveTrees(const path: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - trees');
    WCom(L, 'offsets: distance from the road centre, 1 = road edge');
    WCom(L, 'spacing: segments between rows of trees');
    WCom(L, 'colours are used by data\shapes\pine.shape and tree.shape as $pine.xxx / $tree.xxx');
    WSec(L, 'placement');
    WNum(L, 'chance', TreeChance);
    WNum(L, 'spacing_min', TreeSpacingMin);
    WNum(L, 'spacing_max', TreeSpacingMax);
    WNum(L, 'offset_min', TreeOffMin);
    WNum(L, 'offset_max', TreeOffMax);
    WNum(L, 'pine_ratio', PineRatio);
    WSec(L, 'pine');
    WCol(L, 'trunk', PineTrunk);
    WCol(L, 'shadow', PineShadow);
    WCol(L, 'tier', PineTier);
    WCol(L, 'lit', PineLit);
    WCol(L, 'top', PineTop);
    WSec(L, 'tree');
    WCol(L, 'trunk', TreeTrunk);
    WCol(L, 'bark', TreeBark);
    WCol(L, 'dark', TreeDark);
    WCol(L, 'mid', TreeMid);
    WCol(L, 'light', TreeLight);
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadTrees(const path: string);
var
  ini: TMemIniFile;
begin
  ini := TMemIniFile.Create(path);
  try
    TreeChance := ClampD(RNum(ini, 'placement', 'chance', TreeChance), 0, 1);
    TreeSpacingMin := Max(1, RInt(ini, 'placement', 'spacing_min', TreeSpacingMin));
    TreeSpacingMax := Max(TreeSpacingMin, RInt(ini, 'placement', 'spacing_max', TreeSpacingMax));
    TreeOffMin := RNum(ini, 'placement', 'offset_min', TreeOffMin);
    TreeOffMax := MaxD(TreeOffMin, RNum(ini, 'placement', 'offset_max', TreeOffMax));
    PineRatio := ClampD(RNum(ini, 'placement', 'pine_ratio', PineRatio), 0, 1);
    PineTrunk := RCol(ini, 'pine', 'trunk', PineTrunk);
    PineShadow := RCol(ini, 'pine', 'shadow', PineShadow);
    PineTier := RCol(ini, 'pine', 'tier', PineTier);
    PineLit := RCol(ini, 'pine', 'lit', PineLit);
    PineTop := RCol(ini, 'pine', 'top', PineTop);
    TreeTrunk := RCol(ini, 'tree', 'trunk', TreeTrunk);
    TreeBark := RCol(ini, 'tree', 'bark', TreeBark);
    TreeDark := RCol(ini, 'tree', 'dark', TreeDark);
    TreeMid := RCol(ini, 'tree', 'mid', TreeMid);
    TreeLight := RCol(ini, 'tree', 'light', TreeLight);
  finally
    ini.Free;
  end;
end;

procedure SaveBushes(const path: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - bushes');
    WCom(L, 'offsets: distance from the road centre, 1 = road edge');
    WCom(L, 'flower_ratio: share of bushes that have flowers (0-1)');
    WCom(L, 'colours are used by data\shapes\bush.shape as $bush.xxx; flowers = $flower');
    WSec(L, 'placement');
    WNum(L, 'chance', BushChance);
    WNum(L, 'spacing_min', BushSpacingMin);
    WNum(L, 'spacing_max', BushSpacingMax);
    WNum(L, 'offset_min', BushOffMin);
    WNum(L, 'offset_max', BushOffMax);
    WNum(L, 'flower_ratio', FlowerRatio);
    WSec(L, 'colors');
    WCol(L, 'dark', BushDark);
    WCol(L, 'mid', BushMid);
    WCol(L, 'light', BushLight);
    WCol(L, 'flower_center', FlowerCenter);
    WStr(L, 'flowers', ColsToStr(FlowerPalette));
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadBushes(const path: string);
var
  ini: TMemIniFile;
  cl: TRGBArray;
begin
  ini := TMemIniFile.Create(path);
  try
    BushChance := ClampD(RNum(ini, 'placement', 'chance', BushChance), 0, 1);
    BushSpacingMin := Max(1, RInt(ini, 'placement', 'spacing_min', BushSpacingMin));
    BushSpacingMax := Max(BushSpacingMin, RInt(ini, 'placement', 'spacing_max', BushSpacingMax));
    BushOffMin := RNum(ini, 'placement', 'offset_min', BushOffMin);
    BushOffMax := MaxD(BushOffMin, RNum(ini, 'placement', 'offset_max', BushOffMax));
    FlowerRatio := ClampD(RNum(ini, 'placement', 'flower_ratio', FlowerRatio), 0, 1);
    BushDark := RCol(ini, 'colors', 'dark', BushDark);
    BushMid := RCol(ini, 'colors', 'mid', BushMid);
    BushLight := RCol(ini, 'colors', 'light', BushLight);
    FlowerCenter := RCol(ini, 'colors', 'flower_center', FlowerCenter);
    cl := ParseCols(ini.ReadString('colors', 'flowers', ''));
    if Length(cl) > 0 then FlowerPalette := cl;
  finally
    ini.Free;
  end;
end;

procedure SaveSigns(const path: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - signposts');
    WCom(L, 'positions and spacing are in road segments; offset 1 = road edge');
    WCom(L, 'their looks are in data\shapes\*.shape and data\bitmaps\poster*.bmp');
    WSec(L, 'billboards');
    WNum(L, 'first', BillboardFirst);
    WNum(L, 'spacing_min', BillboardSpacingMin);
    WNum(L, 'spacing_max', BillboardSpacingMax);
    WNum(L, 'offset', BillboardOffset);
    WSec(L, 'lamps');
    WCom(L, 'street lamps from the start up to segment "until"');
    WNum(L, 'until', LampUntil);
    WNum(L, 'spacing', LampSpacing);
    WNum(L, 'offset', LampOffset);
    WSec(L, 'warning');
    WCom(L, 'yellow bend warning, "distance" segments before each bend');
    WNum(L, 'enabled', Ord(WarningEnabled));
    WNum(L, 'distance', WarningDistance);
    WNum(L, 'offset', WarningOffset);
    WSec(L, 'chevrons');
    WCom(L, 'red/white chevrons on the outside of bends sharper than min_curve');
    WNum(L, 'enabled', Ord(ChevronEnabled));
    WNum(L, 'spacing', ChevronSpacing);
    WNum(L, 'min_curve', ChevronMinCurve);
    WNum(L, 'offset', ChevronOffset);
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadSigns(const path: string);
var
  ini: TMemIniFile;
begin
  ini := TMemIniFile.Create(path);
  try
    BillboardFirst := Max(0, RInt(ini, 'billboards', 'first', BillboardFirst));
    BillboardSpacingMin := Max(10, RInt(ini, 'billboards', 'spacing_min', BillboardSpacingMin));
    BillboardSpacingMax := Max(BillboardSpacingMin, RInt(ini, 'billboards', 'spacing_max', BillboardSpacingMax));
    BillboardOffset := RNum(ini, 'billboards', 'offset', BillboardOffset);
    LampUntil := Max(0, RInt(ini, 'lamps', 'until', LampUntil));
    LampSpacing := Max(1, RInt(ini, 'lamps', 'spacing', LampSpacing));
    LampOffset := RNum(ini, 'lamps', 'offset', LampOffset);
    WarningEnabled := RInt(ini, 'warning', 'enabled', Ord(WarningEnabled)) <> 0;
    WarningDistance := Max(0, RInt(ini, 'warning', 'distance', WarningDistance));
    WarningOffset := RNum(ini, 'warning', 'offset', WarningOffset);
    ChevronEnabled := RInt(ini, 'chevrons', 'enabled', Ord(ChevronEnabled)) <> 0;
    ChevronSpacing := Max(1, RInt(ini, 'chevrons', 'spacing', ChevronSpacing));
    ChevronMinCurve := RNum(ini, 'chevrons', 'min_curve', ChevronMinCurve);
    ChevronOffset := RNum(ini, 'chevrons', 'offset', ChevronOffset);
  finally
    ini.Free;
  end;
end;

procedure SaveAudio(const path: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - audio');
    WCom(L, 'volumes 0..2 (1 = normal); muted 0/1');
    WSec(L, 'mix');
    WNum(L, 'master', MasterVolume);
    WNum(L, 'engine', EngineVolume);
    WNum(L, 'ground', GroundVolume);
    WNum(L, 'crash', CrashVolume);
    WNum(L, 'muted', Ord(Muted));
    WSec(L, 'engine');
    WCom(L, 'gears: top of each gear as a fraction of top speed, last one = 1');
    WNum(L, 'idle_rpm', IdleRPM);
    WNum(L, 'max_rpm', MaxRPM);
    WStr(L, 'gears', NumsToStr(GearTops));
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadAudio(const path: string);
var
  ini: TMemIniFile;
  g: TNumArray;
begin
  ini := TMemIniFile.Create(path);
  try
    MasterVolume := ClampD(RNum(ini, 'mix', 'master', MasterVolume), 0, 2);
    EngineVolume := ClampD(RNum(ini, 'mix', 'engine', EngineVolume), 0, 2);
    GroundVolume := ClampD(RNum(ini, 'mix', 'ground', GroundVolume), 0, 2);
    CrashVolume := ClampD(RNum(ini, 'mix', 'crash', CrashVolume), 0, 2);
    Muted := RInt(ini, 'mix', 'muted', Ord(Muted)) <> 0;
    IdleRPM := ClampD(RNum(ini, 'engine', 'idle_rpm', IdleRPM), 300, 3000);
    MaxRPM := ClampD(RNum(ini, 'engine', 'max_rpm', MaxRPM), IdleRPM + 1000, 15000);
    g := ParseNums(ini.ReadString('engine', 'gears', ''));
    if Length(g) > 0 then GearTops := g;
  finally
    ini.Free;
  end;
end;

procedure SaveMusic(const path: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - music');
    WCom(L, 'tempo in BPM; one melody step = a 16th note (16 steps per bar)');
    WCom(L, 'melody: MIDI note numbers (69 = A4), 0 = hold previous note, -1 = rest');
    WCom(L, 'bass: one root note per bar; chords: one chord per bar, notes joined by commas');
    WSec(L, 'music');
    WNum(L, 'enabled', Ord(MusicOn));
    WNum(L, 'tempo', MusicTempo);
    WNum(L, 'volume', MusicVolume);
    WSec(L, 'song');
    WStr(L, 'melody', IntsToStr(Melody));
    WStr(L, 'bass', IntsToStr(BassRoots));
    WStr(L, 'chords', ChordsToStr(Chords));
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadMusic(const path: string);
var
  ini: TMemIniFile;
  m: TIntArray;
  c: TChordArray;
begin
  ini := TMemIniFile.Create(path);
  try
    MusicOn := RInt(ini, 'music', 'enabled', Ord(MusicOn)) <> 0;
    MusicTempo := ClampD(RNum(ini, 'music', 'tempo', MusicTempo), 40, 240);
    MusicVolume := ClampD(RNum(ini, 'music', 'volume', MusicVolume), 0, 2);
    m := ParseInts(ini.ReadString('song', 'melody', ''));
    if Length(m) > 0 then Melody := m;
    m := ParseInts(ini.ReadString('song', 'bass', ''));
    if Length(m) > 0 then BassRoots := m;
    c := ParseChords(ini.ReadString('song', 'chords', ''));
    if Length(c) > 0 then Chords := c;
  finally
    ini.Free;
  end;
end;

{ ------------------------------------------------------------ seasons }

procedure SetLookColours(var lk: TLook; const skyT, skyB, fog, mount, hills, gL, gD, rL, rD: TRGB);
begin
  lk.skyTop := skyT; lk.skyBottom := skyB; lk.fog := fog;
  lk.mountain := mount; lk.hills := hills;
  lk.grassL := gL; lk.grassD := gD; lk.roadL := rL; lk.roadD := rD;
end;

procedure SetDefaultSeasons;
begin
  // spring: fresh green, falling blossom
  SetLookColours(Seasons[0], MakeRGB(70, 130, 210), MakeRGB(190, 220, 245), MakeRGB(180, 205, 225),
    MakeRGB(120, 140, 185), MakeRGB(90, 170, 90), MakeRGB(70, 200, 70), MakeRGB(55, 185, 55),
    MakeRGB(107, 107, 107), MakeRGB(100, 100, 100));
  Seasons[0].leaves := MakeRGB(120, 200, 90);  Seasons[0].leavesMix := 0.35;
  Seasons[0].needles := MakeRGB(60, 140, 70);  Seasons[0].needlesMix := 0.1;
  Seasons[0].flowers := True;
  Seasons[0].weather := wxPetals;              Seasons[0].weatherAmount := 60;

  // summer: the classic look
  SetLookColours(Seasons[1], MakeRGB(30, 80, 180), MakeRGB(165, 205, 240), MakeRGB(150, 188, 215),
    MakeRGB(115, 135, 180), MakeRGB(65, 135, 80), MakeRGB(16, 170, 16), MakeRGB(0, 150, 0),
    MakeRGB(107, 107, 107), MakeRGB(100, 100, 100));
  Seasons[1].leaves := MakeRGB(44, 132, 50);   Seasons[1].leavesMix := 0;
  Seasons[1].needles := MakeRGB(20, 88, 42);   Seasons[1].needlesMix := 0;
  Seasons[1].flowers := True;
  Seasons[1].weather := wxNone;                Seasons[1].weatherAmount := 0;

  // autumn: orange leaves, brown grass, falling leaves
  SetLookColours(Seasons[2], MakeRGB(90, 110, 160), MakeRGB(220, 190, 150), MakeRGB(200, 180, 160),
    MakeRGB(130, 120, 140), MakeRGB(150, 110, 60), MakeRGB(150, 145, 55), MakeRGB(135, 125, 45),
    MakeRGB(107, 107, 107), MakeRGB(100, 100, 100));
  Seasons[2].leaves := MakeRGB(210, 110, 30);  Seasons[2].leavesMix := 0.65;
  Seasons[2].needles := MakeRGB(40, 90, 45);   Seasons[2].needlesMix := 0.15;
  Seasons[2].flowers := False;
  Seasons[2].weather := wxLeaves;              Seasons[2].weatherAmount := 70;

  // winter: snow everywhere, snowfall
  SetLookColours(Seasons[3], MakeRGB(120, 140, 170), MakeRGB(210, 220, 235), MakeRGB(215, 222, 232),
    MakeRGB(200, 210, 225), MakeRGB(225, 230, 238), MakeRGB(235, 238, 242), MakeRGB(220, 226, 234),
    MakeRGB(95, 98, 104), MakeRGB(88, 92, 98));
  Seasons[3].leaves := MakeRGB(225, 230, 236); Seasons[3].leavesMix := 0.75;
  Seasons[3].needles := MakeRGB(220, 228, 236); Seasons[3].needlesMix := 0.35;
  Seasons[3].flowers := False;
  Seasons[3].weather := wxSnow;                Seasons[3].weatherAmount := 200;

  Night.skyTop := MakeRGB(6, 10, 30);
  Night.skyBottom := MakeRGB(25, 35, 75);
  Night.fog := MakeRGB(25, 32, 60);
  Night.darkness := 0.62;
  Night.stars := 140;
  Night.headlights := True;
end;

function CurLook: TLook;
begin
  Result := Seasons[EnsureRange(SeasonIdx, 0, 3)];
end;

procedure SaveSeasons(const path: string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    WCom(L, 'Pseudo 3D Road - seasons and day / night');
    WCom(L, '[game] holds the player''s choice (the game changes it with F6 / F7)');
    WCom(L, 'leaves / needles: colour mixed into leaf trees and bushes / pines (mix 0..1)');
    WCom(L, 'weather: none, petals, leaves, snow or rain;  weather_amount: number of particles');
    WCom(L, 'night: darkness 0..1, stars = number of stars, headlights 0/1');
    WSec(L, 'game');
    WStr(L, 'season', SeasonNames[EnsureRange(SeasonIdx, 0, 3)]);
    if NightMode then WStr(L, 'time', 'night') else WStr(L, 'time', 'day');
    for i := 0 to 3 do
    begin
      WSec(L, SeasonNames[i]);
      WCol(L, 'sky_top', Seasons[i].skyTop);
      WCol(L, 'sky_bottom', Seasons[i].skyBottom);
      WCol(L, 'fog', Seasons[i].fog);
      WCol(L, 'mountains', Seasons[i].mountain);
      WCol(L, 'hills', Seasons[i].hills);
      WCol(L, 'grass_light', Seasons[i].grassL);
      WCol(L, 'grass_dark', Seasons[i].grassD);
      WCol(L, 'road_light', Seasons[i].roadL);
      WCol(L, 'road_dark', Seasons[i].roadD);
      WCol(L, 'leaves', Seasons[i].leaves);
      WNum(L, 'leaves_mix', Seasons[i].leavesMix);
      WCol(L, 'needles', Seasons[i].needles);
      WNum(L, 'needles_mix', Seasons[i].needlesMix);
      WNum(L, 'flowers', Ord(Seasons[i].flowers));
      WStr(L, 'weather', WeatherNames[Seasons[i].weather]);
      WNum(L, 'weather_amount', Seasons[i].weatherAmount);
    end;
    WSec(L, 'night');
    WCol(L, 'sky_top', Night.skyTop);
    WCol(L, 'sky_bottom', Night.skyBottom);
    WCol(L, 'fog', Night.fog);
    WNum(L, 'darkness', Night.darkness);
    WNum(L, 'stars', Night.stars);
    WNum(L, 'headlights', Ord(Night.headlights));
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

procedure LoadSeasons(const path: string);
var
  ini: TMemIniFile;
  i: Integer;
  w: TWeather;
  sec, s: string;
begin
  ini := TMemIniFile.Create(path);
  try
    s := LowerCase(Trim(ini.ReadString('game', 'season', SeasonNames[SeasonIdx])));
    for i := 0 to 3 do
      if s = SeasonNames[i] then SeasonIdx := i;
    NightMode := SameText(Trim(ini.ReadString('game', 'time', 'day')), 'night');
    for i := 0 to 3 do
    begin
      sec := SeasonNames[i];
      Seasons[i].skyTop := RCol(ini, sec, 'sky_top', Seasons[i].skyTop);
      Seasons[i].skyBottom := RCol(ini, sec, 'sky_bottom', Seasons[i].skyBottom);
      Seasons[i].fog := RCol(ini, sec, 'fog', Seasons[i].fog);
      Seasons[i].mountain := RCol(ini, sec, 'mountains', Seasons[i].mountain);
      Seasons[i].hills := RCol(ini, sec, 'hills', Seasons[i].hills);
      Seasons[i].grassL := RCol(ini, sec, 'grass_light', Seasons[i].grassL);
      Seasons[i].grassD := RCol(ini, sec, 'grass_dark', Seasons[i].grassD);
      Seasons[i].roadL := RCol(ini, sec, 'road_light', Seasons[i].roadL);
      Seasons[i].roadD := RCol(ini, sec, 'road_dark', Seasons[i].roadD);
      Seasons[i].leaves := RCol(ini, sec, 'leaves', Seasons[i].leaves);
      Seasons[i].leavesMix := ClampD(RNum(ini, sec, 'leaves_mix', Seasons[i].leavesMix), 0, 1);
      Seasons[i].needles := RCol(ini, sec, 'needles', Seasons[i].needles);
      Seasons[i].needlesMix := ClampD(RNum(ini, sec, 'needles_mix', Seasons[i].needlesMix), 0, 1);
      Seasons[i].flowers := RInt(ini, sec, 'flowers', Ord(Seasons[i].flowers)) <> 0;
      s := LowerCase(Trim(ini.ReadString(sec, 'weather', WeatherNames[Seasons[i].weather])));
      for w := Low(TWeather) to High(TWeather) do
        if s = WeatherNames[w] then Seasons[i].weather := w;
      Seasons[i].weatherAmount := EnsureRange(RInt(ini, sec, 'weather_amount', Seasons[i].weatherAmount), 0, 1000);
    end;
    Night.skyTop := RCol(ini, 'night', 'sky_top', Night.skyTop);
    Night.skyBottom := RCol(ini, 'night', 'sky_bottom', Night.skyBottom);
    Night.fog := RCol(ini, 'night', 'fog', Night.fog);
    Night.darkness := ClampD(RNum(ini, 'night', 'darkness', Night.darkness), 0, 0.95);
    Night.stars := EnsureRange(RInt(ini, 'night', 'stars', Night.stars), 0, 1000);
    Night.headlights := RInt(ini, 'night', 'headlights', Ord(Night.headlights)) <> 0;
  finally
    ini.Free;
  end;
end;

procedure SaveSeasonChoice;
begin
  try
    SaveSeasons(DataDir + 'seasons.ini');
  except
  end;
end;

procedure RebuildNamedColors;
var
  lk: TLook;

  function Leaf(const c: TRGB): TRGB;
  begin
    Result := Mix(c, lk.leaves, lk.leavesMix);
  end;

  function Needle(const c: TRGB): TRGB;
  begin
    Result := Mix(c, lk.needles, lk.needlesMix);
  end;

begin
  if NamedColors = nil then NamedColors := TStringList.Create;
  lk := CurLook;
  NamedColors.Clear;
  NamedColors.Add('pine.trunk=' + ColStr(PineTrunk));
  NamedColors.Add('pine.shadow=' + ColStr(Needle(PineShadow)));
  NamedColors.Add('pine.tier=' + ColStr(Needle(PineTier)));
  NamedColors.Add('pine.lit=' + ColStr(Needle(PineLit)));
  NamedColors.Add('pine.top=' + ColStr(Needle(PineTop)));
  NamedColors.Add('tree.trunk=' + ColStr(TreeTrunk));
  NamedColors.Add('tree.bark=' + ColStr(TreeBark));
  NamedColors.Add('tree.dark=' + ColStr(Leaf(TreeDark)));
  NamedColors.Add('tree.mid=' + ColStr(Leaf(TreeMid)));
  NamedColors.Add('tree.light=' + ColStr(Leaf(TreeLight)));
  NamedColors.Add('bush.dark=' + ColStr(Leaf(BushDark)));
  NamedColors.Add('bush.mid=' + ColStr(Leaf(BushMid)));
  NamedColors.Add('bush.light=' + ColStr(Leaf(BushLight)));
  NamedColors.Add('bush.flower_center=' + ColStr(FlowerCenter));
end;

{ older lamp / billboard shape files have no night lights: add them }
procedure UpgradeShapeFiles;
const
  Keys: array[0..1] of string = ('lamp', 'billboard');
var
  L, D: TStringList;
  i, k: Integer;
  f: string;
  hasGlow, added: Boolean;
begin
  for k := 0 to High(Keys) do
  begin
    f := ShapePath(Keys[k]);
    if not FileExists(f) then Continue;
    L := TStringList.Create;
    D := TStringList.Create;
    try
      L.LoadFromFile(f);
      hasGlow := False;
      for i := 0 to L.Count - 1 do
        if Copy(LowerCase(Trim(L[i])), 1, 5) = 'glow ' then hasGlow := True;
      if not hasGlow then
      begin
        WriteShapeText(Keys[k], D);
        added := False;
        for i := 0 to D.Count - 1 do
          if Copy(D[i], 1, 5) = 'glow ' then
          begin
            L.Add(D[i]);
            added := True;
          end;
        if added then L.SaveToFile(f);
      end;
    finally
      L.Free;
      D.Free;
    end;
  end;
end;

procedure FixupData;
var
  i: Integer;
begin
  if Length(GearTops) = 0 then
  begin
    SetLength(GearTops, 1);
    GearTops[0] := 1;
  end;
  for i := 0 to High(GearTops) do GearTops[i] := ClampD(GearTops[i], 0.01, 1);
  GearTops[High(GearTops)] := 1;
  if Length(CarPalette) = 0 then
  begin
    SetLength(CarPalette, 1);
    CarPalette[0] := MakeRGB(200, 200, 200);
  end;
  if Length(FlowerPalette) = 0 then
  begin
    SetLength(FlowerPalette, 1);
    FlowerPalette[0] := MakeRGB(240, 120, 170);
  end;
  if Length(TrafficTypes) = 0 then
  begin
    SetLength(TrafficTypes, 1);
    TrafficTypes[0].name := 'sedan';
    TrafficTypes[0].weight := 1;
  end;
  RebuildNamedColors;
end;

function ModelPath(const name: string): string;
begin
  Result := DataDir + 'models' + DirectorySeparator + name + '.car';
end;

function ShapePath(const name: string): string;
begin
  Result := DataDir + 'shapes' + DirectorySeparator + name + '.shape';
end;

function BitmapPath(const name: string): string;
begin
  Result := DataDir + 'bitmaps' + DirectorySeparator + name + '.bmp';
end;

procedure LoadAllData(withCamera: Boolean);
var
  f: string;
begin
  ForceDirectories(DataDir);
  ForceDirectories(DataDir + 'models');
  ForceDirectories(DataDir + 'shapes');
  ForceDirectories(DataDir + 'bitmaps');
  SetDefaultData;

  f := DataDir + 'vehicles.ini';
  try if not FileExists(f) then SaveVehicles(f); LoadVehicles(f); except end;
  f := DataDir + 'trees.ini';
  try if not FileExists(f) then SaveTrees(f); LoadTrees(f); except end;
  f := DataDir + 'bushes.ini';
  try if not FileExists(f) then SaveBushes(f); LoadBushes(f); except end;
  f := DataDir + 'signs.ini';
  try if not FileExists(f) then SaveSigns(f); LoadSigns(f); except end;
  f := DataDir + 'audio.ini';
  try if not FileExists(f) then SaveAudio(f); LoadAudio(f); except end;
  f := DataDir + 'music.ini';
  try if not FileExists(f) then SaveMusic(f); LoadMusic(f); except end;
  f := DataDir + 'track.txt';
  try if not FileExists(f) then SaveTrackSections(f, DefaultTrackSections); except end;
  f := DataDir + 'seasons.ini';
  try if not FileExists(f) then SaveSeasons(f); LoadSeasons(f); except end;

  if withCamera then
  begin
    f := DataDir + 'camera_default.ini';
    try if not FileExists(f) then SaveCameraFile(f, BuiltInCamera); except end;
    if not LoadCameraFile(DataDir + 'camera.ini', Cam) then LoadDefaultCamera;
  end;

  try WriteDefaultModels(False); except end;
  try WriteDefaultShapes(False); except end;
  try UpgradeShapeFiles; except end;
  try WriteDefaultBitmaps(False); except end;

  FixupData;
end;

{ --------------------------------------------------------------- track }

function DefaultSection(kind: TSectionKind): TTrackSection;
var
  i: Integer;
begin
  Result.kind := kind;
  for i := 0 to 4 do Result.p[i] := SectionDefaults[kind, i];
end;

function ParseTrackLine(const line: string; out sec: TTrackSection): Boolean;
var
  t: TStringArray;
  k: TSectionKind;
  i: Integer;
  cmd: string;
begin
  Result := False;
  sec := DefaultSection(tkStraight);
  t := SplitBy(line, ' ');
  if Length(t) = 0 then Exit;
  cmd := LowerCase(t[0]);
  if (cmd[1] = '#') or (cmd[1] = ';') then Exit;
  for k := Low(TSectionKind) to High(TSectionKind) do
    if cmd = SectionNames[k] then
    begin
      sec := DefaultSection(k);
      for i := 0 to SectionParamCount[k] - 1 do
        if i + 1 < Length(t) then
          sec.p[i] := StrToFloatDef(t[i + 1], sec.p[i], FS);
      Exit(True);
    end;
end;

function SectionToLine(const sec: TTrackSection): string;
var
  i: Integer;
begin
  Result := SectionNames[sec.kind];
  for i := 0 to SectionParamCount[sec.kind] - 1 do
    Result := Result + ' ' + NumStr(sec.p[i]);
end;

function DefaultTrackSections: TTrackSections;
var
  i, n: Integer;
  s: TTrackSection;
begin
  Result := nil;
  for i := 0 to High(DefaultTrack) do
    if ParseTrackLine(DefaultTrack[i], s) then
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := s;
    end;
end;

function LoadTrackSections(const path: string): TTrackSections;
var
  L: TStringList;
  i, n: Integer;
  s: TTrackSection;
begin
  Result := nil;
  if not FileExists(path) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(path);
    except
      L.Clear;
    end;
    for i := 0 to L.Count - 1 do
      if ParseTrackLine(L[i], s) then
      begin
        n := Length(Result);
        SetLength(Result, n + 1);
        Result[n] := s;
      end;
  finally
    L.Free;
  end;
end;

procedure SaveTrackSections(const path: string; const secs: TTrackSections);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('# Pseudo 3D Road - track (map)');
    L.Add('# One road section per line, built in order. Lines starting with # are ignored.');
    L.Add('# Lengths are in road segments (1 segment = 200 world units).');
    L.Add('# curve : + bends right, - bends left (easy 2, medium 4, hard 6)');
    L.Add('# height: hill height in segments, + up, - down (low 20, medium 40, high 60)');
    L.Add('#');
    L.Add('#   straight <length>');
    L.Add('#   curve <length> <curve> [height]');
    L.Add('#   hill <length> <height>');
    L.Add('#   road <enter> <hold> <leave> <curve> <height>');
    L.Add('#   rollinghills <length> <height>');
    L.Add('#   scurves');
    L.Add('#   bumps');
    L.Add('#   downhill <length>   (back to ground level - keep it last to close the loop)');
    L.Add('');
    for i := 0 to High(secs) do L.Add(SectionToLine(secs[i]));
    L.SaveToFile(path);
  finally
    L.Free;
  end;
end;

{ ------------------------------------------------ default bitmap files }

type
  TPixCanvas = record
    w, h: Integer;
    pix: array of TRGB;
  end;

procedure CvInit(var c: TPixCanvas; w, h: Integer; const col: TRGB);
var
  i: Integer;
begin
  c.w := w; c.h := h;
  SetLength(c.pix, w * h);
  for i := 0 to w * h - 1 do c.pix[i] := col;
end;

procedure CvRect(var c: TPixCanvas; x0, y0, x1, y1: Double; const col: TRGB);
var
  ix0, ix1, iy0, iy1, x, y: Integer;
begin
  ix0 := Max(0, Round(MinD(x0, x1)));
  ix1 := Min(c.w, Round(MaxD(x0, x1)));
  iy0 := Max(0, Round(MinD(y0, y1)));
  iy1 := Min(c.h, Round(MaxD(y0, y1)));
  for y := iy0 to iy1 - 1 do
    for x := ix0 to ix1 - 1 do
      c.pix[y * c.w + x] := col;
end;

procedure CvEllipse(var c: TPixCanvas; cx, cy, rx, ry: Double; const col: TRGB);
var
  x, y, xa, xb: Integer;
  dy, hw: Double;
begin
  if (rx <= 0) or (ry <= 0) then Exit;
  for y := Max(0, Floor(cy - ry)) to Min(c.h - 1, Ceil(cy + ry)) do
  begin
    dy := (y + 0.5 - cy) / ry;
    if Abs(dy) >= 1 then Continue;
    hw := rx * Sqrt(1 - dy * dy);
    xa := Max(0, Round(cx - hw));
    xb := Min(c.w, Round(cx + hw));
    for x := xa to xb - 1 do c.pix[y * c.w + x] := col;
  end;
end;

procedure CvPoly(var c: TPixCanvas; const xs, ys: array of Double; const col: TRGB);
var
  n, i, j, y, x, xa, xb: Integer;
  yc, fa, fb, t, xx, ymin, ymax: Double;
begin
  n := Length(xs);
  if n < 3 then Exit;
  ymin := ys[0]; ymax := ys[0];
  for i := 1 to n - 1 do
  begin
    ymin := MinD(ymin, ys[i]);
    ymax := MaxD(ymax, ys[i]);
  end;
  for y := Max(0, Floor(ymin)) to Min(c.h - 1, Ceil(ymax)) do
  begin
    yc := y + 0.5;
    fa := 1e30; fb := -1e30;
    for i := 0 to n - 1 do
    begin
      j := (i + 1) mod n;
      if ((ys[i] <= yc) and (ys[j] > yc)) or ((ys[j] <= yc) and (ys[i] > yc)) then
      begin
        t := (yc - ys[i]) / (ys[j] - ys[i]);
        xx := xs[i] + t * (xs[j] - xs[i]);
        fa := MinD(fa, xx);
        fb := MaxD(fb, xx);
      end;
    end;
    if fb <= fa then Continue;
    xa := Max(0, Round(fa));
    xb := Min(c.w, Round(fb));
    for x := xa to xb - 1 do c.pix[y * c.w + x] := col;
  end;
end;

procedure SaveBMP24(const path: string; const c: TPixCanvas);
var
  F: TFileStream;
  rowSize, dataSize, x, y: Integer;
  row: array of Byte;

  procedure W16(v: Word);
  begin
    F.WriteBuffer(v, 2);
  end;

  procedure W32(v: LongWord);
  begin
    F.WriteBuffer(v, 4);
  end;

begin
  rowSize := ((c.w * 3 + 3) div 4) * 4;
  dataSize := rowSize * c.h;
  SetLength(row, rowSize);
  F := TFileStream.Create(path, fmCreate);
  try
    W16($4D42);                  // 'BM'
    W32(54 + dataSize);
    W32(0);
    W32(54);
    W32(40);
    W32(c.w);
    W32(c.h);                    // positive = rows stored bottom-up
    W16(1);
    W16(24);
    W32(0);
    W32(dataSize);
    W32(2835);
    W32(2835);
    W32(0);
    W32(0);
    for y := c.h - 1 downto 0 do
    begin
      FillChar(row[0], rowSize, 0);
      for x := 0 to c.w - 1 do
      begin
        row[x * 3] := c.pix[y * c.w + x].b;
        row[x * 3 + 1] := c.pix[y * c.w + x].g;
        row[x * 3 + 2] := c.pix[y * c.w + x].r;
      end;
      F.WriteBuffer(row[0], rowSize);
    end;
  finally
    F.Free;
  end;
end;

{ poster coordinates: the billboard face spans x -880..880, y -1740..-860
  (y downwards); the bitmap is 352 x 176 pixels, 5 world units per pixel }
procedure DrawPoster(var c: TPixCanvas; index: Integer);

  function PX(x: Double): Double;
  begin
    Result := (x + 880) / 5;
  end;

  function PY(y: Double): Double;
  begin
    Result := (y + 1740) / 5;
  end;

  procedure R(x, y, w, h: Double; const col: TRGB);
  begin
    CvRect(c, PX(x), PY(y), PX(x + w), PY(y + h), col);
  end;

  procedure E(x, y, r: Double; const col: TRGB);
  begin
    CvEllipse(c, PX(x), PY(y), r / 5, r / 5, col);
  end;

  procedure P3(x0, y0, x1, y1, x2, y2: Double; const col: TRGB);
  begin
    CvPoly(c, [PX(x0), PX(x1), PX(x2)], [PY(y0), PY(y1), PY(y2)], col);
  end;

  procedure P4(x0, y0, x1, y1, x2, y2, x3, y3: Double; const col: TRGB);
  begin
    CvPoly(c, [PX(x0), PX(x1), PX(x2), PX(x3)], [PY(y0), PY(y1), PY(y2), PY(y3)], col);
  end;

var
  k: Integer;
  white: TRGB;
begin
  white := MakeRGB(255, 255, 255);
  case index of
    0: begin                                               // sunset
         for k := 0 to 5 do
           R(-880, -1740 + k * 100, 1760, 100,
             Mix(MakeRGB(250, 160, 60), MakeRGB(150, 60, 140), k / 5));
         E(0, -1150, 190, MakeRGB(255, 225, 130));
         R(-880, -1140, 1760, 280, MakeRGB(30, 70, 140));
         R(-600, -1080, 400, 18, MakeRGB(80, 130, 200));
         R(150, -1010, 500, 18, MakeRGB(80, 130, 200));
         R(-800, -1690, 640, 60, white);
         R(-800, -1600, 420, 40, white);
       end;
    1: begin                                               // car advert
         R(-880, -1740, 1760, 880, MakeRGB(200, 40, 40));
         R(-880, -960, 1760, 100, MakeRGB(60, 60, 60));
         R(-520, -1130, 1040, 140, white);
         P4(-320, -1130, 260, -1130, 160, -1270, -220, -1270, white);
         E(-300, -990, 95, MakeRGB(30, 30, 30));
         E(300, -990, 95, MakeRGB(30, 30, 30));
         R(-800, -1690, 900, 80, MakeRGB(255, 235, 200));
         R(-800, -1580, 600, 45, MakeRGB(255, 235, 200));
       end;
    2: begin                                               // tech logo
         R(-880, -1740, 1760, 880, MakeRGB(30, 70, 170));
         E(-560, -1300, 240, white);
         E(-560, -1300, 150, MakeRGB(30, 70, 170));
         E(-560, -1300, 70, MakeRGB(255, 200, 40));
         R(-230, -1460, 960, 90, white);
         R(-230, -1310, 760, 60, white);
         R(-230, -1200, 860, 60, white);
       end;
  else
       begin                                               // mountains
         R(-880, -1740, 1760, 880, MakeRGB(150, 205, 235));
         P3(-880, -860, -300, -1500, 280, -860, MakeRGB(60, 120, 70));
         P4(-120, -860, 450, -1360, 880, -1100, 880, -860, MakeRGB(60, 120, 70));
         P3(-430, -1360, -300, -1500, -170, -1360, MakeRGB(240, 240, 240));
         R(-880, -940, 1760, 80, MakeRGB(30, 90, 50));
         R(-800, -1700, 800, 70, white);
       end;
  end;
end;

procedure WriteDefaultBitmaps(force: Boolean);
var
  i: Integer;
  c: TPixCanvas;
  f: string;
begin
  for i := 0 to PosterCount - 1 do
  begin
    f := BitmapPath('poster' + IntToStr(i));
    if FileExists(f) and not force then Continue;
    CvInit(c, 352, 176, MakeRGB(255, 255, 255));
    DrawPoster(c, i);
    SaveBMP24(f, c);
  end;
end;

procedure WriteDefaultModels(force: Boolean);
var
  i: Integer;
  L: TStringList;
  f: string;
begin
  for i := 0 to High(DefaultModelNames) do
  begin
    f := ModelPath(DefaultModelNames[i]);
    if FileExists(f) and not force then Continue;
    L := TStringList.Create;
    try
      WriteModelText(DefaultModelNames[i], L);
      L.SaveToFile(f);
    finally
      L.Free;
    end;
  end;
end;

procedure WriteDefaultShapes(force: Boolean);
var
  i: Integer;
  L: TStringList;
  f: string;
begin
  for i := 0 to High(DefaultShapeNames) do
  begin
    f := ShapePath(DefaultShapeNames[i]);
    if FileExists(f) and not force then Continue;
    L := TStringList.Create;
    try
      WriteShapeText(DefaultShapeNames[i], L);
      L.SaveToFile(f);
    finally
      L.Free;
    end;
  end;
end;

{ ------------------------------------------- default model / shape text }

procedure WriteModelText(const key: string; L: TStringList);
begin
  if key = 'sedan' then
  begin
    L.Add('# Pseudo 3D Road - vehicle model');
    L.Add('# Axes: x = sideways (- left, + right), y = up from the road, z = forward (rear at 0).');
    L.Add('# Colours: body | body*0.6 | <name> | <name>*0.8 | r,g,b     (body = the car''s paint)');
    L.Add('#   name <text>            length <z>     width <x>     height is measured');
    L.Add('#   speed <factor>         traffic speed compared with a normal car');
    L.Add('#   hit <z>                collision length (default: 38% of length)');
    L.Add('#   colors <r,g,b ...>     paint colours for traffic of this type (optional)');
    L.Add('#   color <name> <r,g,b>   define a named colour');
    L.Add('#   box    <col> x0 x1 y0 y1 z0 z1');
    L.Add('#   hex    <col> 8 corners "x y z": bottom rear-left, rear-right, front-right,');
    L.Add('#          front-left, then the top corners in the same order');
    L.Add('#   face   <col> 4 corners "x y z"');
    L.Add('#   decal  <col> [glow] 4 corners "x y z"        (painted on the face it lies on)');
    L.Add('#   rdecal <col> [glow] <x|y|z> <pos> a0 b0 a1 b1');
    L.Add('#          rectangle on the plane x, y or z = pos;  plane z: a,b = x,y');
    L.Add('#          plane x: a,b = z,y   plane y: a,b = x,z');
    L.Add('#   Add "glow" to lights so they are not darkened by shading.');
    L.Add('');
    L.Add('name Sedan');
    L.Add('length 850');
    L.Add('width 640');
    L.Add('speed 1');
    L.Add('color glass 40,58,85');
    L.Add('color trim 45,45,48');
    L.Add('color tyre 22,22,22');
    L.Add('color hub 120,122,128');
    L.Add('color tail 225,30,30');
    L.Add('color tailhi 255,150,140');
    L.Add('color plate 235,235,235');
    L.Add('color head 255,250,205');
    L.Add('color grille 30,30,30');
    L.Add('color shine 120,150,190');
    L.Add('box tyre -335 -255 0 125 80 240');
    L.Add('box tyre 255 335 0 125 80 240');
    L.Add('box tyre -335 -255 0 125 610 770');
    L.Add('box tyre 255 335 0 125 610 770');
    L.Add('rdecal hub x -335 124.8 31.25 195.2 93.75');
    L.Add('rdecal hub x 335 124.8 31.25 195.2 93.75');
    L.Add('rdecal hub x -335 654.8 31.25 725.2 93.75');
    L.Add('rdecal hub x 335 654.8 31.25 725.2 93.75');
    L.Add('box body -320 320 60 230 0 850');
    L.Add('rdecal body*1.2 z 0 -314 216 314 230');
    L.Add('rdecal trim z 0 -315 60 315 96');
    L.Add('rdecal tail glow z 0 -300 165 -180 208');
    L.Add('rdecal tail glow z 0 180 165 300 208');
    L.Add('rdecal tailhi glow z 0 -292 190 -250 203');
    L.Add('rdecal tailhi glow z 0 250 190 292 203');
    L.Add('rdecal plate z 0 -62 118 62 158');
    L.Add('rdecal grille z 0 -250 66 -205 86');
    L.Add('rdecal trim z 850 -315 60 315 96');
    L.Add('rdecal head glow z 850 -300 160 -170 205');
    L.Add('rdecal head glow z 850 170 160 300 205');
    L.Add('rdecal grille z 850 -130 115 130 170');
    L.Add('rdecal body*0.6 x -320 0 60 850 82');
    L.Add('rdecal body*0.55 x -320 418 86 428 226');
    L.Add('rdecal body*0.6 x -320 470 186 540 198');
    L.Add('rdecal body*1.2 x -320 0 216 850 230');
    L.Add('rdecal body*0.6 x 320 0 60 850 82');
    L.Add('rdecal body*0.55 x 320 418 86 428 226');
    L.Add('rdecal body*0.6 x 320 470 186 540 198');
    L.Add('rdecal body*1.2 x 320 0 216 850 230');
    L.Add('hex glass -256 230 150  256 230 150  256 230 660  -256 230 660  -180 345 270  180 345 270  180 345 540  -180 345 540');
    L.Add('decal body -180 345 270  180 345 270  180 345 540  -180 345 540');
    L.Add('decal shine -130 245 165.7  -90 245 165.7  -40 330 254.3  -80 330 254.3');
    L.Add('decal tail glow -50 333 257.5  50 333 257.5  50 342 266.9  -50 342 266.9');
    L.Add('decal shine -130 245 644.3  -90 245 644.3  -40 330 555.7  -80 330 555.7');
    L.Add('decal body -256 230 150  -256 230 265  -180 345 365  -180 345 270');
    L.Add('decal body -256 230 400  -256 230 425  -180 345 425  -180 345 400');
    L.Add('decal body -256 230 630  -256 230 660  -180 345 540  -180 345 515');
    L.Add('decal body 256 230 150  256 230 265  180 345 365  180 345 270');
    L.Add('decal body 256 230 400  256 230 425  180 345 425  180 345 400');
    L.Add('decal body 256 230 630  256 230 660  180 345 540  180 345 515');
  end
  else if key = 'sports' then
  begin
    L.Add('# Pseudo 3D Road - vehicle model');
    L.Add('# Axes: x = sideways (- left, + right), y = up from the road, z = forward (rear at 0).');
    L.Add('# Colours: body | body*0.6 | <name> | <name>*0.8 | r,g,b     (body = the car''s paint)');
    L.Add('#   name <text>            length <z>     width <x>     height is measured');
    L.Add('#   speed <factor>         traffic speed compared with a normal car');
    L.Add('#   hit <z>                collision length (default: 38% of length)');
    L.Add('#   colors <r,g,b ...>     paint colours for traffic of this type (optional)');
    L.Add('#   color <name> <r,g,b>   define a named colour');
    L.Add('#   box    <col> x0 x1 y0 y1 z0 z1');
    L.Add('#   hex    <col> 8 corners "x y z": bottom rear-left, rear-right, front-right,');
    L.Add('#          front-left, then the top corners in the same order');
    L.Add('#   face   <col> 4 corners "x y z"');
    L.Add('#   decal  <col> [glow] 4 corners "x y z"        (painted on the face it lies on)');
    L.Add('#   rdecal <col> [glow] <x|y|z> <pos> a0 b0 a1 b1');
    L.Add('#          rectangle on the plane x, y or z = pos;  plane z: a,b = x,y');
    L.Add('#          plane x: a,b = z,y   plane y: a,b = x,z');
    L.Add('#   Add "glow" to lights so they are not darkened by shading.');
    L.Add('');
    L.Add('name Sports car');
    L.Add('length 900');
    L.Add('width 680');
    L.Add('speed 1.25');
    L.Add('colors 200,30,30 250,200,30 30,30,30 240,240,240 40,90,200');
    L.Add('color glass 40,58,85');
    L.Add('color trim 45,45,48');
    L.Add('color tyre 22,22,22');
    L.Add('color hub 120,122,128');
    L.Add('color tail 225,30,30');
    L.Add('color tailhi 255,150,140');
    L.Add('color plate 235,235,235');
    L.Add('color head 255,250,205');
    L.Add('color grille 30,30,30');
    L.Add('color shine 120,150,190');
    L.Add('box tyre -355 -265 0 130 90 260');
    L.Add('box tyre 265 355 0 130 90 260');
    L.Add('box tyre -355 -265 0 130 640 800');
    L.Add('box tyre 265 355 0 130 640 800');
    L.Add('rdecal hub x -355 137.6 32.5 212.4 97.5');
    L.Add('rdecal hub x 355 137.6 32.5 212.4 97.5');
    L.Add('rdecal hub x -355 684.8 32.5 755.2 97.5');
    L.Add('rdecal hub x 355 684.8 32.5 755.2 97.5');
    L.Add('box body -340 340 50 195 0 900');
    L.Add('rdecal trim z 0 -335 50 335 85');
    L.Add('rdecal tail glow z 0 -330 150 -150 175');
    L.Add('rdecal tail glow z 0 150 150 330 175');
    L.Add('rdecal plate z 0 -60 100 60 138');
    L.Add('rdecal grille z 0 -300 58 -250 78');
    L.Add('rdecal grille z 0 250 58 300 78');
    L.Add('rdecal trim z 900 -335 50 335 85');
    L.Add('rdecal head glow z 900 -320 145 -170 175');
    L.Add('rdecal head glow z 900 170 145 320 175');
    L.Add('rdecal grille z 900 -150 95 150 135');
    L.Add('rdecal body*0.55 x -340 0 50 900 70');
    L.Add('rdecal grille x -340 280 110 380 160');
    L.Add('rdecal body*0.55 x 340 0 50 900 70');
    L.Add('rdecal grille x 340 280 110 380 160');
    L.Add('rdecal body*1.3 y 195 -150 0 150 230');
    L.Add('rdecal body*1.3 y 195 -150 640 150 900');
    L.Add('hex glass -280 195 230  280 195 230  280 195 640  -280 195 640  -200 290 360  200 290 360  200 290 540  -200 290 540');
    L.Add('decal body -200 290 360  200 290 360  200 290 540  -200 290 540');
    L.Add('decal body*1.3 -150 290 360  150 290 360  150 290 540  -150 290 540');
    L.Add('decal shine -150 205 243.7  -110 205 243.7  -60 280 346.3  -100 280 346.3');
    L.Add('box trim -250 -225 195 255 30 70');
    L.Add('box trim 225 250 195 255 30 70');
    L.Add('box body*0.8 -335 335 255 275 0 90');
  end
  else if key = 'van' then
  begin
    L.Add('# Pseudo 3D Road - vehicle model');
    L.Add('# Axes: x = sideways (- left, + right), y = up from the road, z = forward (rear at 0).');
    L.Add('# Colours: body | body*0.6 | <name> | <name>*0.8 | r,g,b     (body = the car''s paint)');
    L.Add('#   name <text>            length <z>     width <x>     height is measured');
    L.Add('#   speed <factor>         traffic speed compared with a normal car');
    L.Add('#   hit <z>                collision length (default: 38% of length)');
    L.Add('#   colors <r,g,b ...>     paint colours for traffic of this type (optional)');
    L.Add('#   color <name> <r,g,b>   define a named colour');
    L.Add('#   box    <col> x0 x1 y0 y1 z0 z1');
    L.Add('#   hex    <col> 8 corners "x y z": bottom rear-left, rear-right, front-right,');
    L.Add('#          front-left, then the top corners in the same order');
    L.Add('#   face   <col> 4 corners "x y z"');
    L.Add('#   decal  <col> [glow] 4 corners "x y z"        (painted on the face it lies on)');
    L.Add('#   rdecal <col> [glow] <x|y|z> <pos> a0 b0 a1 b1');
    L.Add('#          rectangle on the plane x, y or z = pos;  plane z: a,b = x,y');
    L.Add('#          plane x: a,b = z,y   plane y: a,b = x,z');
    L.Add('#   Add "glow" to lights so they are not darkened by shading.');
    L.Add('');
    L.Add('name Van');
    L.Add('length 950');
    L.Add('width 660');
    L.Add('speed 0.85');
    L.Add('hit 380');
    L.Add('colors 240,240,240 200,200,205 60,110,190 230,200,40 40,140,80');
    L.Add('color glass 40,58,85');
    L.Add('color trim 45,45,48');
    L.Add('color tyre 22,22,22');
    L.Add('color hub 120,122,128');
    L.Add('color tail 225,30,30');
    L.Add('color tailhi 255,150,140');
    L.Add('color plate 235,235,235');
    L.Add('color head 255,250,205');
    L.Add('color grille 30,30,30');
    L.Add('color shine 120,150,190');
    L.Add('box tyre -345 -265 0 130 90 260');
    L.Add('box tyre 265 345 0 130 90 260');
    L.Add('box tyre -345 -265 0 130 690 860');
    L.Add('box tyre 265 345 0 130 690 860');
    L.Add('rdecal hub x -345 137.6 32.5 212.4 97.5');
    L.Add('rdecal hub x 345 137.6 32.5 212.4 97.5');
    L.Add('rdecal hub x -345 737.6 32.5 812.4 97.5');
    L.Add('rdecal hub x 345 737.6 32.5 812.4 97.5');
    L.Add('box body -330 330 60 270 0 950');
    L.Add('box body -330 330 270 520 0 770');
    L.Add('hex glass -330 270 770  330 270 770  330 270 900  -330 270 900  -310 520 770  310 520 770  310 520 800  -310 520 800');
    L.Add('decal body -310 520 770  310 520 770  310 520 800  -310 520 800');
    L.Add('rdecal trim z 0 -325 60 325 100');
    L.Add('rdecal plate z 0 -62 130 62 170');
    L.Add('rdecal trim z 0 -5 100 5 270');
    L.Add('rdecal trim z 0 -5 270 5 520');
    L.Add('rdecal tail glow z 0 -322 290 -292 450');
    L.Add('rdecal tail glow z 0 292 290 322 450');
    L.Add('rdecal glass z 0 -280 360 -20 490');
    L.Add('rdecal glass z 0 20 360 280 490');
    L.Add('rdecal grille z 0 -45 300 -15 315');
    L.Add('rdecal grille z 0 15 300 45 315');
    L.Add('rdecal trim z 950 -325 60 325 110');
    L.Add('rdecal head glow z 950 -310 180 -180 230');
    L.Add('rdecal head glow z 950 180 180 310 230');
    L.Add('rdecal grille z 950 -150 140 150 240');
    L.Add('rdecal body*0.6 x -330 0 60 950 85');
    L.Add('rdecal body*0.6 x 330 0 60 950 85');
    L.Add('rdecal body*0.6 x -330 480 90 490 270');
    L.Add('rdecal body*0.6 x -330 480 270 490 500');
    L.Add('rdecal body*0.6 x 330 480 90 490 270');
    L.Add('rdecal body*0.6 x 330 480 270 490 500');
    L.Add('rdecal glass x -330 560 340 760 480');
    L.Add('rdecal glass x 330 560 340 760 480');
  end
  else if key = 'pickup' then
  begin
    L.Add('# Pseudo 3D Road - vehicle model');
    L.Add('# Axes: x = sideways (- left, + right), y = up from the road, z = forward (rear at 0).');
    L.Add('# Colours: body | body*0.6 | <name> | <name>*0.8 | r,g,b     (body = the car''s paint)');
    L.Add('#   name <text>            length <z>     width <x>     height is measured');
    L.Add('#   speed <factor>         traffic speed compared with a normal car');
    L.Add('#   hit <z>                collision length (default: 38% of length)');
    L.Add('#   colors <r,g,b ...>     paint colours for traffic of this type (optional)');
    L.Add('#   color <name> <r,g,b>   define a named colour');
    L.Add('#   box    <col> x0 x1 y0 y1 z0 z1');
    L.Add('#   hex    <col> 8 corners "x y z": bottom rear-left, rear-right, front-right,');
    L.Add('#          front-left, then the top corners in the same order');
    L.Add('#   face   <col> 4 corners "x y z"');
    L.Add('#   decal  <col> [glow] 4 corners "x y z"        (painted on the face it lies on)');
    L.Add('#   rdecal <col> [glow] <x|y|z> <pos> a0 b0 a1 b1');
    L.Add('#          rectangle on the plane x, y or z = pos;  plane z: a,b = x,y');
    L.Add('#          plane x: a,b = z,y   plane y: a,b = x,z');
    L.Add('#   Add "glow" to lights so they are not darkened by shading.');
    L.Add('');
    L.Add('name Pickup');
    L.Add('length 980');
    L.Add('width 660');
    L.Add('speed 0.9');
    L.Add('hit 380');
    L.Add('colors 70,90,120 200,40,40 230,230,230 40,40,40 120,140,90');
    L.Add('color glass 40,58,85');
    L.Add('color trim 45,45,48');
    L.Add('color tyre 22,22,22');
    L.Add('color hub 120,122,128');
    L.Add('color tail 225,30,30');
    L.Add('color tailhi 255,150,140');
    L.Add('color plate 235,235,235');
    L.Add('color head 255,250,205');
    L.Add('color grille 30,30,30');
    L.Add('color shine 120,150,190');
    L.Add('box tyre -345 -265 0 130 90 260');
    L.Add('box tyre 265 345 0 130 90 260');
    L.Add('box tyre -345 -265 0 130 720 890');
    L.Add('box tyre 265 345 0 130 720 890');
    L.Add('rdecal hub x -345 137.6 32.5 212.4 97.5');
    L.Add('rdecal hub x 345 137.6 32.5 212.4 97.5');
    L.Add('rdecal hub x -345 767.6 32.5 842.4 97.5');
    L.Add('rdecal hub x 345 767.6 32.5 842.4 97.5');
    L.Add('box body -330 330 60 250 0 980');
    L.Add('box body -320 320 250 480 470 720');
    L.Add('hex glass -320 250 720  320 250 720  320 250 860  -320 250 860  -300 480 720  300 480 720  300 480 760  -300 480 760');
    L.Add('decal body -300 480 720  300 480 720  300 480 760  -300 480 760');
    L.Add('box body -330 -300 250 340 0 470');
    L.Add('box body 300 330 250 340 0 470');
    L.Add('box body -300 300 250 340 0 30');
    L.Add('rdecal trim y 250 -300 30 300 470');
    L.Add('rdecal glass z 470 -260 320 260 450');
    L.Add('rdecal glass x -320 500 300 700 450');
    L.Add('rdecal glass x 320 500 300 700 450');
    L.Add('rdecal trim z 0 -325 60 325 100');
    L.Add('rdecal tail glow z 0 -325 170 -270 240');
    L.Add('rdecal tail glow z 0 270 170 325 240');
    L.Add('rdecal plate z 0 -62 110 62 150');
    L.Add('rdecal body*0.75 z 0 -270 280 270 320');
    L.Add('rdecal trim z 980 -325 60 325 100');
    L.Add('rdecal head glow z 980 -310 170 -180 220');
    L.Add('rdecal head glow z 980 180 170 310 220');
    L.Add('rdecal grille z 980 -150 120 150 230');
    L.Add('rdecal body*0.6 x -330 0 60 980 85');
    L.Add('rdecal body*0.6 x 330 0 60 980 85');
  end
  else if key = 'truck' then
  begin
    L.Add('# Pseudo 3D Road - vehicle model');
    L.Add('# Axes: x = sideways (- left, + right), y = up from the road, z = forward (rear at 0).');
    L.Add('# Colours: body | body*0.6 | <name> | <name>*0.8 | r,g,b     (body = the car''s paint)');
    L.Add('#   name <text>            length <z>     width <x>     height is measured');
    L.Add('#   speed <factor>         traffic speed compared with a normal car');
    L.Add('#   hit <z>                collision length (default: 38% of length)');
    L.Add('#   colors <r,g,b ...>     paint colours for traffic of this type (optional)');
    L.Add('#   color <name> <r,g,b>   define a named colour');
    L.Add('#   box    <col> x0 x1 y0 y1 z0 z1');
    L.Add('#   hex    <col> 8 corners "x y z": bottom rear-left, rear-right, front-right,');
    L.Add('#          front-left, then the top corners in the same order');
    L.Add('#   face   <col> 4 corners "x y z"');
    L.Add('#   decal  <col> [glow] 4 corners "x y z"        (painted on the face it lies on)');
    L.Add('#   rdecal <col> [glow] <x|y|z> <pos> a0 b0 a1 b1');
    L.Add('#          rectangle on the plane x, y or z = pos;  plane z: a,b = x,y');
    L.Add('#          plane x: a,b = z,y   plane y: a,b = x,z');
    L.Add('#   Add "glow" to lights so they are not darkened by shading.');
    L.Add('');
    L.Add('name Truck');
    L.Add('length 1750');
    L.Add('width 740');
    L.Add('speed 0.65');
    L.Add('hit 700');
    L.Add('colors 200,40,40 40,90,180 230,200,40 240,240,240 60,140,80');
    L.Add('color cargo 236,236,240');
    L.Add('color cargo2 214,214,220');
    L.Add('color glass 40,58,85');
    L.Add('color trim 45,45,48');
    L.Add('color tyre 22,22,22');
    L.Add('color hub 120,122,128');
    L.Add('color tail 225,30,30');
    L.Add('color tailhi 255,150,140');
    L.Add('color plate 235,235,235');
    L.Add('color head 255,250,205');
    L.Add('color grille 30,30,30');
    L.Add('color shine 120,150,190');
    L.Add('box tyre -370 -240 0 160 80 300');
    L.Add('box tyre 240 370 0 160 80 300');
    L.Add('box tyre -370 -240 0 160 330 550');
    L.Add('box tyre 240 370 0 160 330 550');
    L.Add('box tyre -370 -240 0 160 1440 1640');
    L.Add('box tyre 240 370 0 160 1440 1640');
    L.Add('rdecal hub x -370 141.6 40 238.4 120');
    L.Add('rdecal hub x 370 141.6 40 238.4 120');
    L.Add('rdecal hub x -370 391.6 40 488.4 120');
    L.Add('rdecal hub x 370 391.6 40 488.4 120');
    L.Add('rdecal hub x -370 1496 40 1584 120');
    L.Add('rdecal hub x 370 1496 40 1584 120');
    L.Add('box trim -300 300 90 160 0 1750');
    L.Add('rdecal tail glow z 0 -290 100 -200 150');
    L.Add('rdecal tail glow z 0 200 100 290 150');
    L.Add('rdecal plate z 0 -60 100 60 150');
    L.Add('box cargo -360 360 160 760 0 1250');
    L.Add('rdecal cargo2 z 0 -350 170 -5 750');
    L.Add('rdecal cargo2 z 0 5 170 350 750');
    L.Add('rdecal trim z 0 -60 300 -40 600');
    L.Add('rdecal trim z 0 40 300 60 600');
    L.Add('rdecal body x -360 50 600 1200 680');
    L.Add('rdecal body x 360 50 600 1200 680');
    L.Add('box trim -200 200 160 400 1250 1300');
    L.Add('box body -350 350 160 650 1300 1750');
    L.Add('hex body -330 650 1300  330 650 1300  330 650 1500  -330 650 1500  -330 760 1300  330 760 1300  330 760 1330  -330 760 1330');
    L.Add('rdecal glass z 1750 -320 420 320 620');
    L.Add('rdecal glass x -350 1560 420 1730 620');
    L.Add('rdecal glass x 350 1560 420 1730 620');
    L.Add('rdecal head glow z 1750 -330 200 -230 260');
    L.Add('rdecal head glow z 1750 230 200 330 260');
    L.Add('rdecal grille z 1750 -200 190 200 380');
    L.Add('rdecal trim z 1750 -345 160 345 200');
  end
  else if key = 'bus' then
  begin
    L.Add('# Pseudo 3D Road - vehicle model');
    L.Add('# Axes: x = sideways (- left, + right), y = up from the road, z = forward (rear at 0).');
    L.Add('# Colours: body | body*0.6 | <name> | <name>*0.8 | r,g,b     (body = the car''s paint)');
    L.Add('#   name <text>            length <z>     width <x>     height is measured');
    L.Add('#   speed <factor>         traffic speed compared with a normal car');
    L.Add('#   hit <z>                collision length (default: 38% of length)');
    L.Add('#   colors <r,g,b ...>     paint colours for traffic of this type (optional)');
    L.Add('#   color <name> <r,g,b>   define a named colour');
    L.Add('#   box    <col> x0 x1 y0 y1 z0 z1');
    L.Add('#   hex    <col> 8 corners "x y z": bottom rear-left, rear-right, front-right,');
    L.Add('#          front-left, then the top corners in the same order');
    L.Add('#   face   <col> 4 corners "x y z"');
    L.Add('#   decal  <col> [glow] 4 corners "x y z"        (painted on the face it lies on)');
    L.Add('#   rdecal <col> [glow] <x|y|z> <pos> a0 b0 a1 b1');
    L.Add('#          rectangle on the plane x, y or z = pos;  plane z: a,b = x,y');
    L.Add('#          plane x: a,b = z,y   plane y: a,b = x,z');
    L.Add('#   Add "glow" to lights so they are not darkened by shading.');
    L.Add('');
    L.Add('name Bus');
    L.Add('length 2200');
    L.Add('width 760');
    L.Add('speed 0.6');
    L.Add('hit 880');
    L.Add('colors 240,200,40 230,230,230 60,120,200 200,60,50');
    L.Add('color roof 205,205,210');
    L.Add('color glass 40,58,85');
    L.Add('color trim 45,45,48');
    L.Add('color tyre 22,22,22');
    L.Add('color hub 120,122,128');
    L.Add('color tail 225,30,30');
    L.Add('color tailhi 255,150,140');
    L.Add('color plate 235,235,235');
    L.Add('color head 255,250,205');
    L.Add('color grille 30,30,30');
    L.Add('color shine 120,150,190');
    L.Add('box tyre -390 -290 0 150 250 480');
    L.Add('box tyre 290 390 0 150 250 480');
    L.Add('box tyre -390 -290 0 150 1680 1910');
    L.Add('box tyre 290 390 0 150 1680 1910');
    L.Add('rdecal hub x -390 314.4 37.5 415.6 112.5');
    L.Add('rdecal hub x 390 314.4 37.5 415.6 112.5');
    L.Add('rdecal hub x -390 1744.4 37.5 1845.6 112.5');
    L.Add('rdecal hub x 390 1744.4 37.5 1845.6 112.5');
    L.Add('box body -380 380 70 640 0 2200');
    L.Add('box roof -220 220 640 700 700 1300');
    L.Add('rdecal glass x -380 150 380 2050 560');
    L.Add('rdecal glass x 380 150 380 2050 560');
    L.Add('rdecal body*0.75 x -380 0 300 2200 330');
    L.Add('rdecal body*0.75 x 380 0 300 2200 330');
    L.Add('rdecal body x -380 520 380 545 560');
    L.Add('rdecal body x -380 900 380 925 560');
    L.Add('rdecal body x -380 1280 380 1305 560');
    L.Add('rdecal body x -380 1660 380 1685 560');
    L.Add('rdecal body x 380 520 380 545 560');
    L.Add('rdecal body x 380 900 380 925 560');
    L.Add('rdecal body x 380 1280 380 1305 560');
    L.Add('rdecal body x 380 1660 380 1685 560');
    L.Add('rdecal glass z 0 -330 420 330 600');
    L.Add('rdecal grille z 0 -250 180 250 300');
    L.Add('rdecal tail glow z 0 -360 150 -300 300');
    L.Add('rdecal tail glow z 0 300 150 360 300');
    L.Add('rdecal plate z 0 -70 120 70 165');
    L.Add('rdecal trim z 0 -375 70 375 110');
    L.Add('rdecal glass z 2200 -350 300 350 615');
    L.Add('rdecal grille z 2200 -250 595 250 632');
    L.Add('rdecal head glow z 2200 -360 120 -250 175');
    L.Add('rdecal head glow z 2200 250 120 360 175');
    L.Add('rdecal trim z 2200 -375 70 375 110');
  end;
end;

procedure WriteShapeText(const key: string; L: TStringList);
begin
  if key = 'pine' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 1440');
    L.Add('solid 1');
    L.Add('lod $pine.tier');
    L.Add('shadow 600');
    L.Add('mirror none');
    L.Add('variants 1');
    L.Add('poly $pine.trunk -55 0 55 0 30 520 -30 520');
    L.Add('poly $pine.shadow -720 330 720 330 612 390 -612 390');
    L.Add('poly $pine.tier -720 350 720 350 0 1010');
    L.Add('poly $pine.lit -720 350 -72 410 0 1010');
    L.Add('poly $pine.shadow -560 690 560 690 476 750 -476 750');
    L.Add('poly $pine.tier -560 710 560 710 0 1330');
    L.Add('poly $pine.lit -560 710 -56 770 0 1330');
    L.Add('poly $pine.shadow -400 1050 400 1050 340 1110 -340 1110');
    L.Add('poly $pine.tier -400 1070 400 1070 0 1650');
    L.Add('poly $pine.lit -400 1070 -40 1130 0 1650');
    L.Add('poly $pine.shadow -240 1410 240 1410 204 1470 -204 1470');
    L.Add('poly $pine.tier -240 1430 240 1430 0 1970');
    L.Add('poly $pine.lit -240 1430 -24 1490 0 1970');
    L.Add('poly $pine.top -60 1680 60 1680 0 1900');
  end
  else if key = 'tree' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 1700');
    L.Add('solid 1');
    L.Add('lod $tree.mid');
    L.Add('shadow 750');
    L.Add('mirror none');
    L.Add('variants 1');
    L.Add('poly $tree.trunk -95 0 95 0 50 900 -50 900');
    L.Add('poly $tree.trunk 10 680 55 660 -230 1040 -265 1070');
    L.Add('poly $tree.trunk -10 720 30 740 260 1080 230 1100');
    L.Add('poly $tree.bark -55 0 -25 0 -18 860 -36 860');
    L.Add('ellipse $tree.dark 0 1260 720 520');
    L.Add('ellipse $tree.dark -430 1060 420 320');
    L.Add('ellipse $tree.dark 430 1080 430 330');
    L.Add('ellipse $tree.mid -150 1390 490 400');
    L.Add('ellipse $tree.mid 260 1310 430 360');
    L.Add('ellipse $tree.mid -390 1180 330 270');
    L.Add('ellipse $tree.mid 30 1630 420 320');
    L.Add('ellipse $tree.light -260 1530 260 200');
    L.Add('ellipse $tree.light 80 1730 220 160');
    L.Add('ellipse $tree.light -440 1270 170 140');
    L.Add('ellipse $tree.light 300 1460 180 140');
  end
  else if key = 'bush' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 1200');
    L.Add('solid 0');
    L.Add('lod $bush.mid');
    L.Add('shadow 560');
    L.Add('mirror none');
    L.Add('variants 1');
    L.Add('ellipse $bush.dark 0 170 540 200');
    L.Add('ellipse $bush.dark -330 130 290 150');
    L.Add('ellipse $bush.dark 340 140 280 150');
    L.Add('ellipse $bush.mid -120 270 340 175');
    L.Add('ellipse $bush.mid 210 240 290 155');
    L.Add('ellipse $bush.light -210 330 150 90');
    L.Add('ellipse $bush.light 130 310 120 70');
  end
  else if key = 'flowerbush' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 1200');
    L.Add('solid 0');
    L.Add('lod $bush.mid');
    L.Add('shadow 560');
    L.Add('mirror none');
    L.Add('variants 1');
    L.Add('ellipse $bush.dark 0 170 540 200');
    L.Add('ellipse $bush.dark -330 130 290 150');
    L.Add('ellipse $bush.dark 340 140 280 150');
    L.Add('ellipse $bush.mid -120 270 340 175');
    L.Add('ellipse $bush.mid 210 240 290 155');
    L.Add('ellipse $bush.light -210 330 150 90');
    L.Add('ellipse $bush.light 130 310 120 70');
    L.Add('rect $flower -420 175 -365 230');
    L.Add('rect $flower -250 325 -195 380');
    L.Add('rect $flower -60 245 -5 300');
    L.Add('rect $flower 120 345 175 400');
    L.Add('rect $flower 300 205 355 260');
    L.Add('rect $flower -140 95 -85 150');
    L.Add('rect $flower 220 65 275 120');
    L.Add('rect $flower 450 115 505 170');
    L.Add('rect $flower -480 55 -425 110');
    L.Add('rect $flower 30 375 85 430');
    L.Add('rect $bush.flower_center -405 190 -380 215');
    L.Add('rect $bush.flower_center -45 260 -20 285');
    L.Add('rect $bush.flower_center 315 220 340 245');
  end
  else if key = 'billboard' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 1860');
    L.Add('solid 1');
    L.Add('lod 230,230,230');
    L.Add('shadow 900');
    L.Add('mirror none');
    L.Add('variants 4');
    L.Add('rect 70,72,78 -720 0 -630 900');
    L.Add('rect 70,72,78 630 0 720 900');
    L.Add('poly 70,72,78 -630 320 630 670 630 720 -630 370');
    L.Add('rect 225,225,228 -930 830 930 1790');
    L.Add('rect 150,150,155 -930 828 930 850');
    L.Add('image poster{v} -880 860 880 1740');
    L.Add('rect 60,60,65 -500 1780 -460 1850');
    L.Add('rect 60,60,65 460 1780 500 1850');
    L.Add('rect 60,60,65 -570 1835 -400 1880');
    L.Add('rect 60,60,65 400 1835 570 1880');
    L.Add('glow 255,240,200 -485 1835 220');
    L.Add('glow 255,240,200 485 1835 220');
  end
  else if key = 'lamp' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 140');
    L.Add('solid 1');
    L.Add('lod 110,110,115');
    L.Add('shadow 0');
    L.Add('mirror side');
    L.Add('variants 1');
    L.Add('rect 80,80,88 -75 0 75 130');
    L.Add('poly 112,114,122 -42 130 42 130 22 2000 -22 2000');
    L.Add('poly 155,157,165 -32 130 -12 130 -6 2000 -18 2000');
    L.Add('poly 100,102,110 0 1960 0 2000 210 2105 210 2065');
    L.Add('poly 100,102,110 210 2065 210 2105 460 2105 460 2065');
    L.Add('poly 55,55,60 330 2110 530 2110 510 2050 350 2050');
    L.Add('poly 255,240,170 350 2050 510 2050 490 2030 370 2030');
    L.Add('glow 255,225,150 430 2030 300');
  end
  else if key = 'chevron' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 660');
    L.Add('solid 1');
    L.Add('lod 200,30,30');
    L.Add('shadow 0');
    L.Add('mirror variant');
    L.Add('variants 1');
    L.Add('rect 110,110,115 -25 0 25 700');
    L.Add('rect 245,245,245 -330 690 330 1150');
    L.Add('rect 200,30,30 -300 720 300 1120');
    L.Add('poly 255,255,255 -190 1080 -120 1080 -20 920 -90 920');
    L.Add('poly 255,255,255 -90 920 -20 920 -120 760 -190 760');
    L.Add('poly 255,255,255 10 1080 80 1080 180 920 110 920');
    L.Add('poly 255,255,255 110 920 180 920 80 760 10 760');
  end
  else if key = 'warning' then
  begin
    L.Add('# Pseudo 3D Road - scenery shape (drawn flat, facing the camera)');
    L.Add('# Units are world units: x = sideways from the object''s base centre, y = up.');
    L.Add('# Colours: r,g,b | $name (named colour from trees.ini / bushes.ini, e.g. $pine.trunk)');
    L.Add('#          $flower (flower colour chosen per bush from bushes.ini)');
    L.Add('#   width <w>        collision / visibility width');
    L.Add('#   solid <0|1>      1 = the player crashes into it');
    L.Add('#   lod <col>        colour of the tiny block drawn far away');
    L.Add('#   shadow <rx>      ground shadow radius (0 = none)');
    L.Add('#   mirror none|variant|side   flip x by the sign of the variant or by the road side');
    L.Add('#   variants <n>     number of variants ({v} in image names is replaced by 0..n-1)');
    L.Add('#   rect    <col> x0 y0 x1 y1');
    L.Add('#   ellipse <col> cx cy rx ry');
    L.Add('#   poly    <col> x y x y ...        (convex, up to 8 points)');
    L.Add('#   image   <name> x0 y0 x1 y1       (data/bitmaps/<name>.bmp)');
    L.Add('#   glow    <col> cx cy r            light that shines only at night');
    L.Add('');
    L.Add('width 660');
    L.Add('solid 1');
    L.Add('lod 250,200,30');
    L.Add('shadow 0');
    L.Add('mirror variant');
    L.Add('variants 1');
    L.Add('rect 110,110,115 -25 0 25 800');
    L.Add('poly 25,25,25 0 1470 340 1130 0 790 -340 1130');
    L.Add('poly 250,200,30 0 1425 295 1130 0 835 -295 1130');
    L.Add('poly 25,25,25 -50 930 10 930 10 1120 -50 1120');
    L.Add('poly 25,25,25 1 1099 121 1219 79 1261 -41 1141');
    L.Add('poly 25,25,25 152 1188 175 1315 48 1292');
  end;
end;

end.
